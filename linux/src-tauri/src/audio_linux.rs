use serde::Serialize;
use std::{
    io::Read,
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
};
use tauri::{AppHandle, Emitter};

#[derive(Default)]
pub struct Capture {
    child: Arc<Mutex<Option<Child>>>,
    generation: Arc<AtomicU64>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Stream {
    pub index: u32,
    pub name: String,
    pub binary: String,
    pub monitor: String,
}
fn pactl(kind: &str) -> Result<serde_json::Value, String> {
    let output = Command::new("pactl")
        .args(["--format=json", "list", kind])
        .output()
        .map_err(|_| {
            "Install pulseaudio-utils and ensure PipeWire-Pulse or PulseAudio is running."
                .to_string()
        })?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().into());
    }
    serde_json::from_slice(&output.stdout).map_err(|e| e.to_string())
}
pub fn streams() -> Result<Vec<Stream>, String> {
    let sinks = pactl("sinks")?;
    let inputs = pactl("sink-inputs")?;
    Ok(inputs
        .as_array()
        .ok_or("Invalid audio stream list.")?
        .iter()
        .filter_map(|input| {
            let index = u32::try_from(input["index"].as_u64()?).ok()?;
            let sink = sinks
                .as_array()?
                .iter()
                .find(|sink| sink["index"] == input["sink"])?;
            let properties = &input["properties"];
            Some(Stream {
                index,
                name: properties["application.name"]
                    .as_str()
                    .unwrap_or("Audio stream")
                    .into(),
                binary: properties["application.process.binary"]
                    .as_str()
                    .unwrap_or("")
                    .into(),
                monitor: sink["monitor_source"]
                    .as_str()
                    .or_else(|| sink["monitor_source_name"].as_str())?
                    .into(),
            })
        })
        .collect())
}
impl Capture {
    pub fn stop(&self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        if let Some(mut child) = self.child.lock().unwrap().take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
    pub fn start(&self, app: AppHandle, index: u32) -> Result<(), String> {
        self.stop();
        let stream = streams()?
            .into_iter()
            .find(|s| s.index == index)
            .ok_or("This audio stream has ended. Refresh the stream list.")?;
        let mut child = Command::new("parec")
            .args([
                format!("--monitor-stream={}", stream.index),
                format!("--device={}", stream.monitor),
                "--raw".into(),
                "--format=float32le".into(),
                "--rate=48000".into(),
                "--channels=2".into(),
                "--latency-msec=50".into(),
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| e.to_string())?;
        let mut stdout = child.stdout.take().ok_or("Unable to open audio stream.")?;
        *self.child.lock().unwrap() = Some(child);
        let generation = self.generation.clone();
        let children = self.child.clone();
        let token = generation.load(Ordering::SeqCst);
        std::thread::spawn(move || {
            use rustfft::{num_complex::Complex, FftPlanner};
            let fft = FftPlanner::<f32>::new().plan_fft_forward(2048);
            let mut bytes = vec![0; 2048 * 8];
            let mut bins = vec![Complex::new(0.0, 0.0); 2048];
            while stdout.read_exact(&mut bytes).is_ok()
                && generation.load(Ordering::SeqCst) == token
            {
                let mut rms = 0.0;
                for (i, frame) in bytes.chunks_exact(8).enumerate() {
                    let left = f32::from_le_bytes(frame[..4].try_into().unwrap());
                    let right = f32::from_le_bytes(frame[4..].try_into().unwrap());
                    let sample = (left + right) * 0.5;
                    let sample = if sample.is_finite() {
                        sample.clamp(-1.0, 1.0)
                    } else {
                        0.0
                    };
                    rms += sample * sample;
                    bins[i] = Complex::new(
                        sample * (0.5 - 0.5 * (std::f32::consts::TAU * i as f32 / 2047.0).cos()),
                        0.0,
                    );
                }
                fft.process(&mut bins);
                let bands: Vec<f32> = (0..32)
                    .map(|b| {
                        let lo = (40.0_f32 * 400.0_f32.powf(b as f32 / 32.0) * 2048.0 / 48000.0)
                            as usize;
                        let hi = (40.0_f32 * 400.0_f32.powf((b + 1) as f32 / 32.0) * 2048.0
                            / 48000.0)
                            .ceil() as usize;
                        let magnitude = bins[lo.max(1)..hi.max(lo.max(1) + 1).min(1024)]
                            .iter()
                            .map(|v| v.norm() * 4.0 / 2048.0)
                            .fold(0.0_f32, f32::max);
                        ((20.0 * magnitude.max(1e-7).log10() + 65.0) / 60.0).clamp(0.0, 1.0)
                    })
                    .collect();
                let _=app.emit("audio-frame",serde_json::json!({"level":((rms/2048.0).sqrt().sqrt()*1.8).min(1.0),"bands":bands}));
            }
            if generation.load(Ordering::SeqCst) == token {
                if let Some(mut ended) = children.lock().unwrap().take() {
                    let _ = ended.wait();
                }
                let _ = app.emit(
                    "audio-ended",
                    "The selected stream ended or changed output. Refresh and reconnect beat sync.",
                );
            }
        });
        Ok(())
    }
}
impl Drop for Capture {
    fn drop(&mut self) {
        self.stop();
    }
}

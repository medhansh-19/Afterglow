//! WASAPI process-loopback capture. There is deliberately no endpoint loopback
//! fallback: unavailable process capture must never analyze unrelated system sound.
use serde::Serialize;
use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    time::Duration,
};
use tauri::{AppHandle, Emitter};
use windows::{
    core::{implement, IUnknown, Interface, Ref, HRESULT, PWSTR},
    Win32::{
        Foundation::CloseHandle,
        Media::Audio::*,
        System::{
            Com::{StructuredStorage::*, *},
            Threading::*,
            Variant::VT_BLOB,
        },
    },
};

#[derive(Default)]
pub struct Capture {
    operation: Mutex<()>,
    worker: Mutex<Option<std::thread::JoinHandle<()>>>,
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
fn process_name(pid: u32) -> Option<String> {
    unsafe {
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buffer = vec![0u16; 32768];
        let mut length = buffer.len() as u32;
        let result = QueryFullProcessImageNameW(
            handle,
            PROCESS_NAME_WIN32,
            PWSTR(buffer.as_mut_ptr()),
            &mut length,
        );
        let _ = CloseHandle(handle);
        if result.is_err() {
            return None;
        }
        std::path::Path::new(&String::from_utf16_lossy(&buffer[..length as usize]))
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
    }
}
pub fn streams() -> Result<Vec<Stream>, String> {
    let _apartment = crate::windows::Apartment::new()?;
    unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).map_err(|e| e.to_string())?;
        let devices = enumerator
            .EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)
            .map_err(|e| e.to_string())?;
        let mut output = std::collections::BTreeMap::new();
        for device in 0..devices.GetCount().map_err(|e| e.to_string())? {
            let Ok(device) = devices.Item(device) else {
                continue;
            };
            let Ok(manager) = device.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else {
                continue;
            };
            let Ok(sessions) = manager.GetSessionEnumerator() else {
                continue;
            };
            for index in 0..sessions.GetCount().unwrap_or_default() {
                let Ok(session) = sessions
                    .GetSession(index)
                    .and_then(|s| s.cast::<IAudioSessionControl2>())
                else {
                    continue;
                };
                if session.GetState().ok() != Some(AudioSessionStateActive) {
                    continue;
                }
                let Ok(pid) = session.GetProcessId() else {
                    continue;
                };
                if pid == 0 || pid == std::process::id() || output.contains_key(&pid) {
                    continue;
                }
                let Some(binary) = process_name(pid) else {
                    continue;
                };
                let name = session
                    .GetDisplayName()
                    .ok()
                    .and_then(|name| {
                        let text = name.to_string().ok();
                        CoTaskMemFree(Some(name.0.cast()));
                        text
                    })
                    .filter(|n| !n.is_empty() && !n.starts_with('@'))
                    .unwrap_or_else(|| binary.clone());
                output.insert(
                    pid,
                    Stream {
                        index: pid,
                        name: format!("{name} · PID {pid}"),
                        binary,
                        monitor: "Selected process and its child processes".into(),
                    },
                );
            }
        }
        Ok(output.into_values().collect())
    }
}
// IAudioClient from process-loopback activation is used exclusively in the MTA.
// Windows invokes the agile completion callback in the same MTA; its reference
// is transferred once to the dedicated capture worker, never concurrently used.
struct MtaClient(IAudioClient);
unsafe impl Send for MtaClient {}
struct Activation {
    _params: Box<AUDIOCLIENT_ACTIVATION_PARAMS>,
    variant: Box<PROPVARIANT>,
}
// Read-only, heap-stable activation memory stays alive through callback release.
unsafe impl Send for Activation {}
unsafe impl Sync for Activation {}
#[implement(IActivateAudioInterfaceCompletionHandler, IAgileObject)]
struct Completion {
    sender: Mutex<Option<mpsc::SyncSender<Result<MtaClient, String>>>>,
    _activation: Arc<Activation>,
}
impl IAgileObject_Impl for Completion_Impl {}
impl IActivateAudioInterfaceCompletionHandler_Impl for Completion_Impl {
    fn ActivateCompleted(
        &self,
        operation: Ref<'_, IActivateAudioInterfaceAsyncOperation>,
    ) -> windows::core::Result<()> {
        let result = (|| -> windows::core::Result<MtaClient> {
            let mut status = HRESULT(0); let mut object:Option<IUnknown> = None;
            unsafe { operation.ok()?.GetActivateResult(&mut status,&mut object)?; }
            status.ok()?;
            Ok(MtaClient(object.ok_or_else(|| windows::core::Error::from_hresult(HRESULT(0x80004005u32 as i32)))?.cast()?))
        })().map_err(|e| format!("Player-only audio is unavailable. Windows 11 (build 20348+) and an unprotected player stream are required. {e}"));
        if let Some(sender) = self.sender.lock().unwrap().take() {
            let _ = sender.send(result);
        }
        Ok(())
    }
}
fn activate(pid: u32, generation: &AtomicU64, token: u64) -> Result<IAudioClient, String> {
    let mut params = Box::new(AUDIOCLIENT_ACTIVATION_PARAMS {
        ActivationType: AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,
        Anonymous: AUDIOCLIENT_ACTIVATION_PARAMS_0 {
            ProcessLoopbackParams: AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
                TargetProcessId: pid,
                ProcessLoopbackMode: PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE,
            },
        },
    });
    let variant = Box::new(PROPVARIANT {
        Anonymous: PROPVARIANT_0 {
            Anonymous: std::mem::ManuallyDrop::new(PROPVARIANT_0_0 {
                vt: VT_BLOB,
                Anonymous: PROPVARIANT_0_0_0 {
                    blob: BLOB {
                        cbSize: std::mem::size_of::<AUDIOCLIENT_ACTIVATION_PARAMS>() as u32,
                        pBlobData: (&mut *params as *mut AUDIOCLIENT_ACTIVATION_PARAMS).cast(),
                    },
                },
                ..Default::default()
            }),
        },
    });
    let activation = Arc::new(Activation {
        _params: params,
        variant,
    });
    let (sender, receiver) = mpsc::sync_channel(1);
    let handler: IActivateAudioInterfaceCompletionHandler = Completion {
        sender: Mutex::new(Some(sender)),
        _activation: activation.clone(),
    }
    .into();
    let _operation = unsafe {
        ActivateAudioInterfaceAsync(
            VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
            &IAudioClient::IID,
            Some(&*activation.variant),
            &handler,
        )
    }
    .map_err(|e| {
        format!("Player-only capture needs Windows 11 and a supported player stream: {e}")
    })?;
    let deadline = std::time::Instant::now() + Duration::from_secs(8);
    loop {
        if generation.load(Ordering::SeqCst) != token {
            return Err("Audio capture canceled.".into());
        }
        match receiver.recv_timeout(Duration::from_millis(20)) {
            Ok(result) => return result.map(|client| client.0),
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return Err("Windows audio activation disconnected.".into())
            }
            Err(_) if std::time::Instant::now() >= deadline => {
                return Err(
                    "Windows did not activate player-only audio within 8 seconds. Try again."
                        .into(),
                )
            }
            Err(_) => {}
        }
    }
}
impl Capture {
    pub fn stop(&self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        // Cancellation never blocks the UI/power-message thread behind an in-flight
        // Windows audio-session query. The starting worker observes its token.
        if let Ok(_guard) = self.operation.try_lock() {
            if let Some(worker) = self.worker.lock().unwrap().take() {
                let _ = worker.join();
            }
        }
    }
    pub fn start(&self, app: AppHandle, index: u32) -> Result<(), String> {
        let token = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let _guard = self.operation.lock().unwrap();
        if generation_changed(&self.generation, token, &app) {
            return Err("Audio capture canceled.".into());
        }
        if let Some(worker) = self.worker.lock().unwrap().take() {
            let _ = worker.join();
        }
        let selected = streams()?
            .into_iter()
            .find(|s| s.index == index)
            .ok_or("The selected player process is no longer producing audio. Refresh streams.")?;
        if generation_changed(&self.generation, token, &app) {
            return Err("Audio capture canceled.".into());
        }
        let binary = selected.binary;
        let generation = self.generation.clone();
        let (ready, receiver) = mpsc::sync_channel(1);
        let worker = std::thread::spawn(move || {
            let result = capture(&app, index, &binary, &generation, token, &ready);
            let _ =
                ready.try_send(Err(result.as_ref().err().cloned().unwrap_or_else(|| {
                    "The selected player ended its audio stream.".into()
                })));
            if generation.load(Ordering::SeqCst) == token {
                let _ = app.emit("audio-ended",result.err().unwrap_or_else(|| "The selected player ended its audio stream. Refresh streams to reconnect.".into()));
            }
        });
        *self.worker.lock().unwrap() = Some(worker);
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        loop {
            let canceled = self.generation.load(Ordering::SeqCst) != token;
            let result = if canceled {
                Some(Err("Audio capture canceled.".into()))
            } else {
                match receiver.recv_timeout(Duration::from_millis(20)) {
                    Ok(value) => Some(value),
                    Err(mpsc::RecvTimeoutError::Disconnected) => {
                        Some(Err("Audio capture worker stopped.".into()))
                    }
                    Err(_) if std::time::Instant::now() >= deadline => {
                        Some(Err("Player-only audio initialization timed out.".into()))
                    }
                    Err(_) => None,
                }
            };
            if let Some(result) = result {
                if result.is_err() {
                    let _ = self.generation.compare_exchange(
                        token,
                        token + 1,
                        Ordering::SeqCst,
                        Ordering::SeqCst,
                    );
                    if let Some(worker) = self.worker.lock().unwrap().take() {
                        let _ = worker.join();
                    }
                }
                return result;
            }
        }
    }
}
fn generation_changed(generation: &AtomicU64, token: u64, app: &AppHandle) -> bool {
    use tauri::Manager;
    generation.load(Ordering::SeqCst) != token
        || app
            .state::<crate::power::Power>()
            .sleeping
            .load(Ordering::SeqCst)
}
impl Drop for Capture {
    fn drop(&mut self) {
        self.stop();
    }
}
struct Process(windows::Win32::Foundation::HANDLE);
impl Drop for Process {
    fn drop(&mut self) {
        let _ = unsafe { CloseHandle(self.0) };
    }
}
fn capture(
    app: &AppHandle,
    pid: u32,
    binary: &str,
    generation: &AtomicU64,
    token: u64,
    ready: &mpsc::SyncSender<Result<(), String>>,
) -> Result<(), String> {
    let _apartment = crate::windows::Apartment::new()?;
    // Open before async activation: the held process object prevents PID reuse
    // from redirecting a delayed activation to a newly started process.
    let process = Process(
        unsafe {
            OpenProcess(
                PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE,
                false,
                pid,
            )
        }
        .map_err(|e| e.to_string())?,
    );
    if process_name(pid).as_deref() != Some(binary)
        || unsafe { WaitForSingleObject(process.0, 0) } != windows::Win32::Foundation::WAIT_TIMEOUT
    {
        return Err("The selected player process has ended. Refresh audio streams.".into());
    }
    let client = activate(pid, generation, token)?;
    if generation.load(Ordering::SeqCst) != token {
        return Ok(());
    }
    // Process loopback supports this fixed IEEE-float stereo format independent
    // of the physical endpoint. AUTOCONVERTPCM handles differing source formats.
    let format = WAVEFORMATEX {
        wFormatTag: 3,
        nChannels: 2,
        nSamplesPerSec: 48_000,
        nAvgBytesPerSec: 384_000,
        nBlockAlign: 8,
        wBitsPerSample: 32,
        cbSize: 0,
    };
    unsafe {
        client.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
            200_000,
            0,
            &format,
            None,
        )
    }
    .map_err(|e| e.to_string())?;
    let capture: IAudioCaptureClient = unsafe { client.GetService() }.map_err(|e| e.to_string())?;
    if generation_changed(generation, token, app) {
        return Err("Audio capture canceled.".into());
    }
    unsafe { client.Start() }.map_err(|e| e.to_string())?;
    let _ = ready.send(Ok(()));
    let result = analyze(app, &capture, &process, pid, binary, generation, token);
    let _ = unsafe { client.Stop() };
    result
}
fn analyze(
    app: &AppHandle,
    capture: &IAudioCaptureClient,
    process: &Process,
    pid: u32,
    binary: &str,
    generation: &AtomicU64,
    token: u64,
) -> Result<(), String> {
    use rustfft::{num_complex::Complex, FftPlanner};
    let fft = FftPlanner::<f32>::new().plan_fft_forward(2048);
    let mut bins = vec![Complex::new(0.0, 0.0); 2048];
    let mut samples = Vec::with_capacity(2048);
    let mut last_check = std::time::Instant::now();
    while generation.load(Ordering::SeqCst) == token {
        if last_check.elapsed() >= Duration::from_secs(1) {
            if unsafe { WaitForSingleObject(process.0, 0) }
                != windows::Win32::Foundation::WAIT_TIMEOUT
                || process_name(pid).as_deref() != Some(binary)
            {
                return Err("The selected player process has ended. Refresh audio streams.".into());
            }
            last_check = std::time::Instant::now();
        }
        let mut packets = unsafe { capture.GetNextPacketSize() }.map_err(|e| e.to_string())?;
        while packets > 0 && generation.load(Ordering::SeqCst) == token {
            let mut pointer = std::ptr::null_mut();
            let mut frames = 0;
            let mut flags = 0;
            unsafe { capture.GetBuffer(&mut pointer, &mut frames, &mut flags, None, None) }
                .map_err(|e| e.to_string())?;
            // Always release the acquired WASAPI buffer before returning or emitting.
            let silent = flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0;
            let mut packet = Vec::with_capacity(frames as usize);
            for frame in 0..frames as usize {
                let sample = if silent || pointer.is_null() {
                    0.0
                } else {
                    unsafe {
                        let left = std::ptr::read_unaligned(pointer.add(frame * 8).cast::<f32>());
                        let right =
                            std::ptr::read_unaligned(pointer.add(frame * 8 + 4).cast::<f32>());
                        let value = (left + right) * 0.5;
                        if value.is_finite() {
                            value.clamp(-1.0, 1.0)
                        } else {
                            0.0
                        }
                    }
                };
                packet.push(sample);
            }
            unsafe { capture.ReleaseBuffer(frames) }.map_err(|e| e.to_string())?;
            if generation.load(Ordering::SeqCst) != token {
                return Ok(());
            }
            for sample in packet {
                samples.push(sample);
                if samples.len() == 2048 {
                    let mut rms = 0.0;
                    for (i, sample) in samples.iter().enumerate() {
                        rms += sample * sample;
                        bins[i] = Complex::new(
                            sample
                                * (0.5 - 0.5 * (std::f32::consts::TAU * i as f32 / 2047.0).cos()),
                            0.0,
                        );
                    }
                    fft.process(&mut bins);
                    let bands: Vec<f32> = (0..32)
                        .map(|b| {
                            let low = (40.0_f32 * 400.0_f32.powf(b as f32 / 32.0) * 2048.0
                                / 48_000.0) as usize;
                            let high = (40.0_f32 * 400.0_f32.powf((b + 1) as f32 / 32.0) * 2048.0
                                / 48_000.0)
                                .ceil() as usize;
                            let magnitude = bins[low.max(1)..high.max(low.max(1) + 1).min(1024)]
                                .iter()
                                .map(|v| v.norm() * 4.0 / 2048.0)
                                .fold(0.0_f32, f32::max);
                            ((20.0 * magnitude.max(1e-7).log10() + 65.0) / 60.0).clamp(0.0, 1.0)
                        })
                        .collect();
                    if generation.load(Ordering::SeqCst) != token {
                        return Ok(());
                    }
                    let _ = app.emit("audio-frame",serde_json::json!({"level":((rms/2048.0).sqrt().sqrt()*1.8).min(1.0),"bands":bands}));
                    samples.clear();
                }
            }
            packets = unsafe { capture.GetNextPacketSize() }.map_err(|e| e.to_string())?;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    Ok(())
}

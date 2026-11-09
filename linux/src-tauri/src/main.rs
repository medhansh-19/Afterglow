#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod artwork;
mod audio;
mod desktop;
mod player;
mod power;
mod shortcuts;
#[cfg(target_os = "windows")]
mod windows;
use std::{
    io::{Read, Write},
    process::{Command, Stdio},
    sync::Mutex,
    time::{Duration, Instant},
};
#[derive(Default)]
struct Lifecycle {
    ready: std::sync::atomic::AtomicBool,
    pending: Mutex<Option<String>>,
}
fn smoke_log(message: &str) {
    if let Some(path) = std::env::var_os("AFTERGLOW_SMOKE_LOG") {
        if let Ok(mut file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
        {
            let _ = writeln!(file, "{message}");
        }
    }
}
static LYRICS_LOCK: Mutex<()> = Mutex::new(());
static LYRICS_GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
use base64::Engine;
use tauri::{Emitter, Manager, State};

#[tauri::command]
async fn artwork(bus: String) -> Result<Option<String>, String> {
    tauri::async_runtime::spawn_blocking(move || artwork::fetch(bus))
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn players(selected: Option<String>) -> Result<Vec<player::Snapshot>, String> {
    tauri::async_runtime::spawn_blocking(move || player::players(selected))
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn transport(bus: String, action: String, position: Option<f64>) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || player::control(bus, action, position))
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn lyrics(
    app: tauri::AppHandle,
    request: serde_json::Value,
) -> Result<serde_json::Value, String> {
    smoke_log(&format!(
        "lyrics:{}",
        request
            .get("command")
            .and_then(|v| v.as_str())
            .unwrap_or("lookup")
    ));
    let generation = LYRICS_GENERATION.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
    let input = serde_json::to_vec(&request).map_err(|e| e.to_string())?;
    if input.len() > 600_000 {
        return Err("Lyrics request exceeds 600 KB.".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = LYRICS_LOCK
            .lock()
            .map_err(|_| "Lyrics service lock unavailable")?;
        if LYRICS_GENERATION.load(std::sync::atomic::Ordering::SeqCst) != generation {
            return Err("Lyrics lookup superseded.".into());
        }
        let executable = std::env::current_exe().map_err(|e| e.to_string())?;
        let executable = executable
            .parent()
            .ok_or("Missing executable directory")?
            .join(if cfg!(windows) {
                "afterglow-lyrics.exe"
            } else {
                "afterglow-lyrics"
            });
        let executable = if executable.exists() {
            executable
        } else {
            // Development helper has the target-triple suffix required by Tauri packaging.
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("binaries")
                .join(format!(
                    "afterglow-lyrics-{}{}",
                    env!("AFTERGLOW_TARGET"),
                    if cfg!(windows) { ".exe" } else { "" }
                ))
        };
        let mut command = Command::new(executable);
        if let Ok(resources) = app.path().resource_dir() {
            let runtime = resources.join("runtime");
            if runtime.is_dir() {
                #[cfg(not(target_os = "windows"))]
                command.env("LD_LIBRARY_PATH", runtime);
                #[cfg(target_os = "windows")]
                {
                    let mut paths = vec![runtime];
                    paths.extend(std::env::split_paths(
                        &std::env::var_os("PATH").unwrap_or_default(),
                    ));
                    command.env(
                        "PATH",
                        std::env::join_paths(paths).map_err(|e| e.to_string())?,
                    );
                }
            }
        }
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000); // CREATE_NO_WINDOW for the console sidecar.
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("Lyrics service could not start: {e}"))?;
        child
            .stdin
            .take()
            .ok_or("Missing service input")?
            .write_all(&input)
            .map_err(|e| e.to_string())?;
        let mut stdout = child.stdout.take().ok_or("Missing service output")?;
        let reader = std::thread::spawn(move || {
            let mut output = Vec::new();
            stdout
                .by_ref()
                .take(4_000_001)
                .read_to_end(&mut output)
                .map(|_| output)
        });
        let deadline = Instant::now() + Duration::from_secs(90);
        let status = loop {
            if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
                break status;
            }
            if Instant::now() > deadline
                || LYRICS_GENERATION.load(std::sync::atomic::Ordering::SeqCst) != generation
            {
                let _ = child.kill();
                let _ = child.wait();
                let _ = reader.join();
                return Err("Lyrics lookup timed out. Try again or import lyrics.".into());
            }
            std::thread::sleep(Duration::from_millis(20));
        };
        let output = reader
            .join()
            .map_err(|_| "Lyrics reader stopped")?
            .map_err(|e| e.to_string())?;
        if !status.success() || output.len() > 4_000_000 {
            return Err("Lyrics service stopped unexpectedly.".into());
        }
        serde_json::from_slice(&output).map_err(|e| format!("Invalid lyrics service response: {e}"))
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn load_library(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let path = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("library.json");
    if !path.exists() {
        return Ok(serde_json::json!({}));
    }
    if path.metadata().map_err(|e| e.to_string())?.len() > 20_000_000 {
        return Err("Library exceeds 20 MB.".into());
    }
    serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?)
        .map_err(|e| format!("Library could not be read; the original has been preserved: {e}"))
}
#[tauri::command]
fn save_library(app: tauri::AppHandle, library: serde_json::Value) -> Result<(), String> {
    let data = serde_json::to_vec(&library).map_err(|e| e.to_string())?;
    if data.len() > 20_000_000 {
        return Err("Library exceeds 20 MB. Remove unused wallpaper copies.".into());
    }
    let directory = app.path().app_data_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&directory).map_err(|e| e.to_string())?;
    let path = directory.join("library.json");
    let temporary = directory.join("library.json.tmp");
    let mut file = std::fs::File::create(&temporary).map_err(|e| e.to_string())?;
    file.write_all(&data)
        .and_then(|_| file.sync_all())
        .map_err(|e| e.to_string())?;
    #[cfg(target_os = "windows")]
    windows::storage::replace(&temporary, &path)?;
    #[cfg(not(target_os = "windows"))]
    std::fs::rename(&temporary, &path).map_err(|e| e.to_string())?;
    smoke_log(&format!("library-path:{}", path.display()));
    smoke_log("library-saved");
    Ok(())
}
#[tauri::command]
async fn audio_streams() -> Result<Vec<audio::Stream>, String> {
    tauri::async_runtime::spawn_blocking(audio::streams)
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn audio_start(app: tauri::AppHandle, index: u32) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        if app
            .state::<power::Power>()
            .sleeping
            .load(std::sync::atomic::Ordering::SeqCst)
        {
            return Err("Audio capture is suspended while the system sleeps.".into());
        }
        app.state::<audio::Capture>().start(app.clone(), index)
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn audio_stop(app: tauri::AppHandle) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || app.state::<audio::Capture>().stop())
        .await
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn desktop_mode(app: tauri::AppHandle, enabled: bool) -> Result<(), String> {
    desktop::set(&app, enabled)
}
#[tauri::command]
fn publish_display(app: tauri::AppHandle, state: serde_json::Value) -> Result<(), String> {
    app.emit_to("wallpaper", "display-state", state)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn disable_shortcuts(app: tauri::AppHandle) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    return windows::shortcuts::stop(&app);
    #[cfg(not(target_os = "windows"))]
    Err("Restart Afterglow to release this desktop shortcut session.".into())
}
#[tauri::command]
fn enable_shortcuts(app: tauri::AppHandle) -> Result<(), String> {
    shortcuts::start(app)
}
#[tauri::command]
fn client_error(message: String) {
    smoke_log(&format!(
        "client-error: {}",
        message.chars().take(2000).collect::<String>()
    ));
    eprintln!(
        "Afterglow UI error: {}",
        message.chars().take(2000).collect::<String>()
    );
}
#[tauri::command]
fn ui_ready(app: tauri::AppHandle) -> Option<String> {
    let state = app.state::<Lifecycle>();
    state.ready.store(true, std::sync::atomic::Ordering::SeqCst);
    eprintln!("Afterglow UI ready");
    smoke_log("ui-ready");
    #[cfg(target_os = "windows")]
    {
        let power = app.state::<power::Power>();
        let _ = app.emit_to(
            "main",
            "power-state",
            serde_json::json!({
                "sleeping": power.sleeping.load(std::sync::atomic::Ordering::SeqCst),
                "onBattery": power.on_battery.load(std::sync::atomic::Ordering::SeqCst)
            }),
        );
    }
    let pending = state.pending.lock().unwrap().take();
    pending
}
#[tauri::command]
fn export_png(path: String, data: String) -> Result<(), String> {
    let path = std::path::Path::new(&path);
    if !path
        .extension()
        .and_then(|s| s.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case("png"))
    {
        return Err("Choose a .png filename.".into());
    }
    if data.len() > 16_000_000 {
        return Err("Image is too large.".into());
    }
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(data)
        .map_err(|e| e.to_string())?;
    if !bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Err("Invalid PNG image.".into());
    }
    std::fs::write(path, bytes).map_err(|e| e.to_string())
}
fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                if let Some(index) = args.iter().position(|a| a == "--action") {
                    if let Some(action) = args.get(index + 1) {
                        smoke_log(&format!("single-instance:{action}"));
                        if app.get_webview_window("wallpaper").is_none() {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                        let lifecycle = app.state::<Lifecycle>();
                        if lifecycle.ready.load(std::sync::atomic::Ordering::SeqCst) {
                            let _ = window.emit("action", action);
                        } else {
                            *lifecycle.pending.lock().unwrap() = Some(action.clone());
                        }
                    }
                } else {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(Lifecycle::default())
        .manage(audio::Capture::default())
        .manage(power::Power::default())
        .manage(shortcuts::Shortcuts::default())
        .setup(|app| {
            power::start(app.handle().clone());
            let arguments: Vec<String> = std::env::args().collect();
            if let Some(index) = arguments.iter().position(|a| a == "--action") {
                if let Some(action) = arguments.get(index + 1) {
                    *app.state::<Lifecycle>().pending.lock().unwrap() = Some(action.clone());
                }
            }
            use tauri::{
                menu::{Menu, MenuItem},
                tray::TrayIconBuilder,
            };
            let open = MenuItem::with_id(app, "open", "Open Afterglow", true, None::<&str>)?;
            let restore =
                MenuItem::with_id(app, "restore", "Return to Window", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Afterglow", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &restore, &quit])?;
            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/icon.png"))?;
            TrayIconBuilder::new()
                .icon(icon)
                .tooltip("Afterglow")
                .menu(&menu)
                .on_menu_event(|app, event| {
                    if event.id.as_ref() == "quit" {
                        app.state::<audio::Capture>().stop();
                        app.exit(0);
                        return;
                    }
                    if let Some(window) = app.get_webview_window("main") {
                        match event.id.as_ref() {
                            "open" => {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                            "restore" => {
                                let _ = desktop::set(app, false);
                                let _ = window.emit("restore-window", ());
                            }
                            _ => {}
                        }
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(target_os = "windows")]
            if window.label() == "main" {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = window.hide();
                    if window
                        .app_handle()
                        .get_webview_window("wallpaper")
                        .is_none()
                    {
                        window.app_handle().state::<audio::Capture>().stop();
                    }
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            players,
            transport,
            artwork,
            lyrics,
            load_library,
            save_library,
            audio_streams,
            audio_start,
            audio_stop,
            desktop_mode,
            publish_display,
            enable_shortcuts,
            disable_shortcuts,
            ui_ready,
            client_error,
            export_png
        ])
        .run(tauri::generate_context!())
        .expect("Afterglow could not start");
}

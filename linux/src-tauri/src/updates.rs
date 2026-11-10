//! Signed Windows and Linux updates. No renderer-controlled URLs or installation commands.
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex,
};
use std::time::Duration;
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem},
    Manager,
};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
use tauri_plugin_updater::UpdaterExt;

static BUSY: AtomicBool = AtomicBool::new(false);
static PROMPTED: Mutex<Option<String>> = Mutex::new(None);
struct BusyGuard;
impl Drop for BusyGuard {
    fn drop(&mut self) {
        BUSY.store(false, Ordering::Release);
    }
}

fn preference(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|p| p.join("automatic-updates-disabled"))
        .map_err(|e| e.to_string())
}
fn enabled(app: &tauri::AppHandle) -> bool {
    preference(app).is_ok_and(|p| !p.exists())
}
fn message(app: &tauri::AppHandle, text: impl Into<String>) {
    app.dialog()
        .message(text)
        .title("Afterglow updates")
        .blocking_show();
}
fn confirm(app: &tauri::AppHandle, text: String, action: &str) -> bool {
    app.dialog()
        .message(text)
        .title("Afterglow updates")
        .buttons(MessageDialogButtons::OkCancelCustom(
            action.into(),
            "Later".into(),
        ))
        .blocking_show()
}
fn should_prompt(previous: &Option<String>, version: &str, manual: bool) -> bool {
    manual || previous.as_deref() != Some(version)
}
pub fn check(app: tauri::AppHandle, manual: bool) {
    if BUSY
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_err()
    {
        if manual {
            std::thread::spawn(move || {
                message(&app, "An update check or download is already in progress.")
            });
        }
        return;
    }
    std::thread::spawn(move || {
        let _guard = BusyGuard;
        let mut downloading = false;
        let mut installing = false;
        let result: Result<(), String> = tauri::async_runtime::block_on(async {
            let updater = app
                .updater_builder()
                .timeout(Duration::from_secs(30))
                .build()
                .map_err(|e| e.to_string())?;
            let Some(mut update) = updater.check().await.map_err(|e| e.to_string())? else {
                if manual {
                    message(&app, "You have the latest version of Afterglow.");
                }
                return Ok(());
            };
            {
                let mut prompted = PROMPTED.lock().map_err(|_| "Update state unavailable")?;
                if !should_prompt(&prompted, &update.version, manual) {
                    return Ok(());
                }
                *prompted = Some(update.version.clone());
            }
            if !confirm(&app, format!("Afterglow {} is available. You have {}.\n\nDownload the update? Your settings and library will be preserved.", update.version, update.current_version), "Download update") { return Ok(()); }
            downloading = true;
            if let Some(tray) = app.tray_by_id("main") {
                let _ = tray.set_tooltip(Some("Afterglow — downloading update…"));
            }
            // Installers bundle the Swift runtime and can be large on slow links.
            update.timeout = Some(Duration::from_secs(30 * 60));
            let bytes = update
                .download(|_, _| {}, || {})
                .await
                .map_err(|e| e.to_string());
            if let Some(tray) = app.tray_by_id("main") {
                let _ = tray.set_tooltip(Some("Afterglow"));
            }
            let bytes = bytes?; // Tauri verifies the signature before returning bytes.
            if confirm(&app, format!("Afterglow {} is downloaded and verified.\n\nClose Afterglow and install the update now?", update.version), "Install and restart") {
                installing = true;
                app.state::<crate::audio::Capture>().stop();
                update.install(bytes).map_err(|e| e.to_string())?;
                // Windows' NSIS installer handles relaunch. Linux updates in place.
                #[cfg(target_os = "linux")]
                app.restart();
            }
            Ok(())
        });
        if result.is_err() {
            // Allow retry after transient errors. Never install unverified content.
            if let Ok(mut prompted) = PROMPTED.lock() {
                *prompted = None;
            }
            if manual || downloading {
                if installing {
                    message(&app, "Couldn’t finish installing the update. Check installation permissions and try again. If needed, reinstall the latest Afterglow package; your library and settings are stored separately.");
                } else {
                    message(&app, "Couldn’t check or verify the update. Check your connection and try Check for Updates again. Your current installation has not been changed.");
                }
            }
        }
    });
}

pub fn setup(app: &mut tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    app.handle()
        .plugin(tauri_plugin_updater::Builder::new().build())?;
    let app = app.handle().clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(30));
        loop {
            if enabled(&app) {
                check(app.clone(), false);
            }
            std::thread::sleep(Duration::from_secs(6 * 60 * 60));
        }
    });
    Ok(())
}
pub fn add_menu(app: &tauri::App, menu: &Menu<tauri::Wry>) -> tauri::Result<()> {
    menu.append(&MenuItem::with_id(
        app,
        "check-updates",
        "Check for Updates…",
        true,
        None::<&str>,
    )?)?;
    menu.append(&CheckMenuItem::with_id(
        app,
        "automatic-updates",
        "Automatically Check for Updates",
        true,
        enabled(app.handle()),
        None::<&str>,
    )?)?;
    Ok(())
}
pub fn menu_event(app: &tauri::AppHandle, id: &str) -> bool {
    match id {
        "check-updates" => {
            check(app.clone(), true);
            true
        }
        "automatic-updates" => {
            let result = preference(app).and_then(|path| {
                if path.exists() {
                    std::fs::remove_file(path).map_err(|e| e.to_string())
                } else {
                    std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
                    std::fs::write(path, b"disabled").map_err(|e| e.to_string())
                }
            });
            if result.is_err() {
                let app = app.clone();
                std::thread::spawn(move || {
                    message(
                        &app,
                        "Couldn’t save the update preference. Please try again.",
                    )
                });
            }
            true
        }
        _ => false,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn automatic_prompts_once_per_version_manual_can_retry() {
        assert!(should_prompt(&None, "0.2.1", false));
        assert!(!should_prompt(&Some("0.2.1".into()), "0.2.1", false));
        assert!(should_prompt(&Some("0.2.1".into()), "0.2.1", true));
        assert!(should_prompt(&Some("0.2.1".into()), "0.3.0", false));
    }
    #[test]
    fn guard_releases_after_error() {
        BUSY.store(true, Ordering::Relaxed);
        {
            let _guard = BusyGuard;
        }
        assert!(!BUSY.load(Ordering::Acquire));
    }
}

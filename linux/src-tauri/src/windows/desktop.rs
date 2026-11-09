//! Explorer's WorkerW wallpaper host is undocumented. Attach only when it exists;
//! never present an ordinary always-on-top window as a desktop wallpaper.
use tauri::{Emitter, Manager};
use windows::{core::w, Win32::{Foundation::{BOOL, HWND, LPARAM, WPARAM, POINT}, UI::WindowsAndMessaging::*, Graphics::Gdi::ScreenToClient}};

unsafe extern "system" fn find_host(window: HWND, data: LPARAM) -> BOOL {
    if FindWindowExW(Some(window), None, w!("SHELLDLL_DefView"), None).is_ok() {
        if let Ok(worker) = FindWindowExW(None, Some(window), w!("WorkerW"), None) {
            *(data.0 as *mut HWND) = worker;
            return BOOL(0);
        }
    }
    BOOL(1)
}
fn host() -> Result<HWND, String> {
    unsafe {
        let progman = FindWindowW(w!("Progman"), None).map_err(|_| "Windows Explorer desktop is unavailable. Use Focus Mode.")?;
        let mut result = 0;
        SendMessageTimeoutW(progman, 0x052c, WPARAM(0), LPARAM(0), SMTO_ABORTIFHUNG, 1000, Some(&mut result));
        let mut host = HWND::default();
        let _ = EnumWindows(Some(find_host), LPARAM((&mut host as *mut HWND) as isize));
        if host.0.is_null() { Err("This Windows desktop does not expose a wallpaper host. Use Focus Mode.".into()) }
        else { Ok(host) }
    }
}
pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<(), String> {
    let main = app.get_webview_window("main").ok_or("Main window unavailable")?;
    if !enabled {
        if let Some(wallpaper) = app.get_webview_window("wallpaper") { wallpaper.close().map_err(|e| e.to_string())?; }
        main.show().and_then(|_| main.set_focus()).map_err(|e| e.to_string())?;
        return Ok(());
    }
    if app.get_webview_window("wallpaper").is_some() { return Ok(()); }
    let host = host()?;
    let monitor = main.current_monitor().map_err(|e| e.to_string())?.ok_or("Display unavailable")?;
    let wallpaper = tauri::WebviewWindowBuilder::new(app, "wallpaper", tauri::WebviewUrl::App("index.html".into()))
        .title("Afterglow Wallpaper").visible(false).decorations(false).skip_taskbar(true).focused(false)
        .initialization_script("window.__AFTERGLOW_WALLPAPER__=true;").build().map_err(|e| e.to_string())?;
    let outcome = (|| -> Result<(), String> {
        let native = wallpaper.hwnd().map_err(|e| e.to_string())?;
        // Tauri and this adapter may use different windows-rs revisions.
        let native = HWND(native.0);
        unsafe {
            let style = GetWindowLongPtrW(native, GWL_STYLE) as u32;
            SetWindowLongPtrW(native, GWL_STYLE, ((style & !WS_POPUP.0) | WS_CHILD.0) as isize);
            // SetParent may legitimately return NULL for a previous top-level parent.
            windows::Win32::Foundation::SetLastError(windows::Win32::Foundation::WIN32_ERROR(0));
            let previous = SetParent(native, Some(host));
            if previous.is_err() && windows::Win32::Foundation::GetLastError().0 != 0 {
                return Err("Windows could not attach the wallpaper to Explorer.".into());
            }
            let mut position = POINT { x: monitor.position().x, y: monitor.position().y };
            if !ScreenToClient(host, &mut position).as_bool() { return Err("Wallpaper display coordinates unavailable.".into()); }
            SetWindowPos(native, Some(HWND_BOTTOM), position.x, position.y, monitor.size().width as i32,
                monitor.size().height as i32, SWP_NOACTIVATE | SWP_FRAMECHANGED).map_err(|e| e.to_string())?;
        }
        wallpaper.set_ignore_cursor_events(true).map_err(|e| e.to_string())?;
        wallpaper.show().map_err(|e| e.to_string())?;
        main.hide().map_err(|e| e.to_string())?;
        Ok(())
    })();
    if outcome.is_err() { let _ = wallpaper.close(); return outcome; }
    // Explorer can recreate its desktop host. Restore controls instead of leaving
    // the only visible app surface orphaned. A later Desktop action may reconnect.
    let handle = app.clone();
    let host_address = host.0 as usize;
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_secs(2));
        if handle.get_webview_window("wallpaper").is_none() { break; }
        if !unsafe { IsWindow(Some(HWND(host_address as *mut _))) }.as_bool() {
            let ui = handle.clone();
            let _ = handle.run_on_main_thread(move || {
                let _ = set(&ui, false);
                let _ = ui.emit_to("main", "restore-window", ());
                let _ = ui.emit_to("main", "desktop-error", "Windows Explorer restarted. Desktop Mode was restored to a window.");
            });
            break;
        }
    });
    Ok(())
}

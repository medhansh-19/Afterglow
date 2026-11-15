use tauri::{Emitter, Manager};
use windows::Win32::UI::{Input::KeyboardAndMouse::*, WindowsAndMessaging::*};

static THREAD: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
pub fn stop(_: &tauri::AppHandle) -> Result<(), String> {
    let thread = THREAD.load(std::sync::atomic::Ordering::SeqCst);
    if thread == 0 {
        return Err("Global shortcuts are not active yet.".into());
    }
    unsafe {
        PostThreadMessageW(
            thread,
            WM_QUIT,
            windows::Win32::Foundation::WPARAM(0),
            windows::Win32::Foundation::LPARAM(0),
        )
    }
    .map_err(|e| e.to_string())
}
pub fn run(app: &tauri::AppHandle) -> Result<(), String> {
    let bindings = [
        ("focus", b'F'),
        ("desktop", b'D'),
        ("beats", b'B'),
        ("appearance", b'A'),
        ("capture", b'M'),
    ];
    let mut registered = Vec::new();
    let mut unavailable = Vec::new();
    for (index, (_, key)) in bindings.iter().enumerate() {
        let id = 0xA610 + index as i32;
        if unsafe {
            RegisterHotKey(
                None,
                id,
                MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT,
                *key as u32,
            )
        }
        .is_ok()
        {
            registered.push(id);
        } else {
            unavailable.push(format!("Ctrl+Shift+{}", *key as char));
        }
    }
    if registered.is_empty() {
        return Err("Windows could not register any Afterglow shortcuts. Free the keys in other apps and retry.".into());
    }
    // Ensure the thread message queue exists before exposing the thread ID.
    let mut pending = MSG::default();
    unsafe {
        let _ = PeekMessageW(&mut pending, None, 0, 0, PM_NOREMOVE);
    }
    THREAD.store(
        unsafe { windows::Win32::System::Threading::GetCurrentThreadId() },
        std::sync::atomic::Ordering::SeqCst,
    );
    let status = if unavailable.is_empty() {
        "Global shortcuts enabled: Ctrl+Shift+F/D/B/A/M.".to_owned()
    } else {
        format!("Global shortcuts enabled. Unavailable: {}. Free these keys and disable and re-enable shortcuts to retry.", unavailable.join(", "))
    };
    let _ = app.emit("shortcut-state", status);
    let mut message = MSG::default();
    while unsafe { GetMessageW(&mut message, None, 0, 0) }.0 > 0 {
        if message.message == WM_HOTKEY {
            if let Some((action, _)) = bindings.get(message.wParam.0.wrapping_sub(0xA610)) {
                if !super::desktop::active(app) {
                    if let Some(window) = app.get_webview_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                let _ = app.emit_to("main", "action", action);
            }
        }
    }
    for id in registered {
        let _ = unsafe { UnregisterHotKey(None, id) };
    }
    THREAD.store(0, std::sync::atomic::Ordering::SeqCst);
    let _ = app.emit("shortcut-state", "Global shortcuts disabled.");
    Ok(())
}

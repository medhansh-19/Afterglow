use tauri::Emitter;
use windows::Win32::UI::{Input::KeyboardAndMouse::*, WindowsAndMessaging::*};

static THREAD: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
pub fn stop(_: &tauri::AppHandle) -> Result<(), String> {
    let thread = THREAD.load(std::sync::atomic::Ordering::SeqCst);
    if thread == 0 { return Err("Global shortcuts are not active yet.".into()); }
    unsafe { PostThreadMessageW(thread, WM_QUIT, windows::Win32::Foundation::WPARAM(0), windows::Win32::Foundation::LPARAM(0)) }.map_err(|e| e.to_string())
}
pub fn run(app: &tauri::AppHandle) -> Result<(), String> {
    let bindings = [("focus", b'F'), ("desktop", b'D'), ("beats", b'B'), ("appearance", b'A'), ("capture", b'M')];
    let mut registered = Vec::new();
    for (index, (_, key)) in bindings.iter().enumerate() {
        let id = 0xA610 + index as i32;
        if let Err(error) = unsafe { RegisterHotKey(None, id, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, *key as u32) } {
            for id in registered { let _ = unsafe { UnregisterHotKey(None, id) }; }
            return Err(format!("Ctrl+Shift+{} is already used or unavailable. Afterglow has released its other global bindings. Focused shortcuts remain available. ({error})", *key as char));
        }
        registered.push(id);
    }
    // Ensure the thread message queue exists before exposing the thread ID.
    let mut pending = MSG::default();
    unsafe { PeekMessageW(&mut pending, None, 0, 0, PM_NOREMOVE); }
    THREAD.store(unsafe { windows::Win32::System::Threading::GetCurrentThreadId() }, std::sync::atomic::Ordering::SeqCst);
    let _ = app.emit("shortcut-state", "Global shortcuts enabled: Ctrl+Shift+F/D/B/A/M.");
    let mut message = MSG::default();
    while unsafe { GetMessageW(&mut message, None, 0, 0) }.0 > 0 {
        if message.message == WM_HOTKEY {
            if let Some((action, _)) = bindings.get(message.wParam.0.wrapping_sub(0xA610)) {
                let _ = app.emit_to("main", "action", action);
            }
        }
    }
    for id in registered { let _ = unsafe { UnregisterHotKey(None, id) }; }
    THREAD.store(0, std::sync::atomic::Ordering::SeqCst);
    let _ = app.emit("shortcut-state", "Global shortcuts disabled.");
    Ok(())
}

//! Explorer wallpaper windows. Both legacy WorkerW and Windows 11's raised
//! desktop are supported; no foreground/topmost substitute is ever created.
use std::{
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use tauri::{Emitter, Manager};
use windows::{
    core::{w, BOOL},
    Win32::{
        Foundation::{COLORREF, HWND, LPARAM, POINT, WPARAM},
        Graphics::Gdi::ScreenToClient,
        UI::{HiDpi::*, WindowsAndMessaging::*},
    },
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Host {
    parent: usize,
    below: usize,
    owner: u32,
    layered: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Screen {
    name: String,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    scale: u64,
    bottom_inset: u32,
}
struct Layout {
    host: Host,
    screens: Vec<Screen>,
    labels: Vec<String>,
    ready: Vec<String>,
    created: Instant,
}
#[derive(Default)]
pub struct Desktop {
    operation: Mutex<()>,
    enabled: AtomicBool,
    generation: Arc<AtomicU64>,
    serial: AtomicU64,
    layout: Mutex<Option<Layout>>,
    hide_when_ready: AtomicBool,
}
pub fn active(app: &tauri::AppHandle) -> bool {
    app.state::<Desktop>().enabled.load(Ordering::SeqCst)
}
fn hwnd(value: usize) -> HWND {
    HWND(value as *mut _)
}
fn owner(window: HWND) -> u32 {
    let mut pid = 0;
    unsafe {
        GetWindowThreadProcessId(window, Some(&mut pid));
    }
    pid
}
unsafe extern "system" fn find_legacy(window: HWND, data: LPARAM) -> BOOL {
    if FindWindowExW(Some(window), None, w!("SHELLDLL_DefView"), None).is_ok() {
        if let Ok(worker) = FindWindowExW(None, Some(window), w!("WorkerW"), None) {
            *(data.0 as *mut HWND) = worker;
            return BOOL(0);
        }
    }
    BOOL(1)
}
fn host() -> Result<Host, String> {
    unsafe {
        let progman = FindWindowW(w!("Progman"), None)
            .map_err(|_| "Windows Explorer desktop is unavailable.")?;
        let mut result = 0;
        SendMessageTimeoutW(
            progman,
            0x052c,
            WPARAM(0xD),
            LPARAM(1),
            SMTO_ABORTIFHUNG,
            1000,
            Some(&mut result),
        );
        // Current Windows 11 places icons and wallpaper under Progman. Place our
        // layered child immediately below the icons, above the system wallpaper.
        if GetWindowLongPtrW(progman, GWL_EXSTYLE) as u32 & WS_EX_NOREDIRECTIONBITMAP.0 != 0 {
            if let (Ok(icons), Ok(_)) = (
                FindWindowExW(Some(progman), None, w!("SHELLDLL_DefView"), None),
                FindWindowExW(Some(progman), None, w!("WorkerW"), None),
            ) {
                return Ok(Host {
                    parent: progman.0 as usize,
                    below: icons.0 as usize,
                    owner: owner(progman),
                    layered: true,
                });
            }
        }
        let mut worker = HWND::default();
        let _ = EnumWindows(
            Some(find_legacy),
            LPARAM((&mut worker as *mut HWND) as isize),
        );
        if worker.0.is_null() {
            return Err("This desktop does not expose a wallpaper layer. Afterglow kept its window available.".into());
        }
        Ok(Host {
            parent: worker.0 as usize,
            below: 0,
            owner: owner(worker),
            layered: false,
        })
    }
}
fn valid(host: Host) -> bool {
    unsafe {
        IsWindow(Some(hwnd(host.parent))).as_bool()
            && owner(hwnd(host.parent)) == host.owner
            && (host.below == 0 || IsWindow(Some(hwnd(host.below))).as_bool())
    }
}
fn screens(app: &tauri::AppHandle) -> Result<Vec<Screen>, String> {
    let main = app
        .get_webview_window("main")
        .ok_or("Main window unavailable")?;
    let mut screens: Vec<_> = main
        .available_monitors()
        .map_err(|e| e.to_string())?
        .iter()
        .map(|m| Screen {
            name: m.name().cloned().unwrap_or_default(),
            x: m.position().x,
            y: m.position().y,
            width: m.size().width,
            height: m.size().height,
            scale: m.scale_factor().to_bits(),
            bottom_inset: (m.position().y as i64 + m.size().height as i64
                - m.work_area().position.y as i64
                - m.work_area().size.height as i64)
                .clamp(0, m.size().height as i64) as u32,
        })
        .filter(|m| m.width > 0 && m.height > 0)
        .collect();
    screens.sort_by(|a, b| (&a.name, a.x, a.y).cmp(&(&b.name, b.x, b.y)));
    if screens.is_empty() {
        return Err("No connected display is available.".into());
    }
    Ok(screens)
}
struct DpiScope(DPI_AWARENESS_CONTEXT);
impl Drop for DpiScope {
    fn drop(&mut self) {
        unsafe {
            SetThreadDpiAwarenessContext(self.0);
        }
    }
}
fn create(app: &tauri::AppHandle, label: &str, host: Host, screen: &Screen) -> Result<(), String> {
    // A reparented window must share Explorer's awareness context. Preserve the
    // main window's thread context after creating this wallpaper child.
    let context = unsafe { GetWindowDpiAwarenessContext(hwnd(host.parent)) };
    let previous = unsafe { SetThreadDpiAwarenessContext(context) };
    if previous.0.is_null() {
        return Err("Windows could not match the desktop display scale.".into());
    }
    let _dpi = DpiScope(previous);
    let scale = f64::from_bits(screen.scale).max(1.0);
    let wallpaper =
        tauri::WebviewWindowBuilder::new(app, label, tauri::WebviewUrl::App("index.html".into()))
            .title("Afterglow Wallpaper")
            .visible(false)
            .decorations(false)
            .skip_taskbar(true)
            .focused(false)
            .inner_size(screen.width as f64 / scale, screen.height as f64 / scale)
            .initialization_script(format!(
                "window.__AFTERGLOW_WALLPAPER__=true;window.__AFTERGLOW_INSET_BOTTOM__={};",
                screen.bottom_inset
            ))
            .build()
            .map_err(|e| e.to_string())?;
    let outcome = (|| -> Result<(), String> {
        let native = HWND(wallpaper.hwnd().map_err(|e| e.to_string())?.0);
        unsafe {
            let style = GetWindowLongPtrW(native, GWL_STYLE) as u32;
            SetWindowLongPtrW(
                native,
                GWL_STYLE,
                ((style & !WS_POPUP.0) | WS_CHILD.0) as isize,
            );
            let extended = GetWindowLongPtrW(native, GWL_EXSTYLE) as u32;
            let flags = extended | WS_EX_NOACTIVATE.0 | WS_EX_TOOLWINDOW.0 | WS_EX_TRANSPARENT.0;
            SetWindowLongPtrW(
                native,
                GWL_EXSTYLE,
                (flags | if host.layered { WS_EX_LAYERED.0 } else { 0 }) as isize,
            );
            if host.layered {
                SetLayeredWindowAttributes(native, COLORREF(0), 255, LWA_ALPHA)
                    .map_err(|e| e.to_string())?;
            }
            windows::Win32::Foundation::SetLastError(windows::Win32::Foundation::WIN32_ERROR(0));
            let result = SetParent(native, Some(hwnd(host.parent)));
            if result.is_err() && windows::Win32::Foundation::GetLastError().0 != 0 {
                return Err("Windows could not attach the wallpaper behind desktop icons.".into());
            }
            let mut point = POINT {
                x: screen.x,
                y: screen.y,
            };
            if !ScreenToClient(hwnd(host.parent), &mut point).as_bool() {
                return Err("Desktop display coordinates unavailable.".into());
            }
            let below = if host.below == 0 {
                HWND_BOTTOM
            } else {
                hwnd(host.below)
            };
            SetWindowPos(
                native,
                Some(below),
                point.x,
                point.y,
                screen.width as i32,
                screen.height as i32,
                SWP_NOACTIVATE | SWP_FRAMECHANGED,
            )
            .map_err(|e| e.to_string())?;
        }
        wallpaper
            .set_size(tauri::PhysicalSize::new(screen.width, screen.height))
            .map_err(|e| e.to_string())?;
        wallpaper
            .set_ignore_cursor_events(true)
            .map_err(|e| e.to_string())?;
        Ok(())
    })();
    if outcome.is_err() {
        let _ = wallpaper.close();
    }
    outcome
}
fn close(app: &tauri::AppHandle, labels: &[String]) {
    for label in labels {
        if let Some(window) = app.get_webview_window(label) {
            let _ = window.close();
        }
    }
}
fn rebuild(app: &tauri::AppHandle, force: bool) -> Result<(), String> {
    let desktop = app.state::<Desktop>();
    let displays = screens(app)?;
    let previous_host = desktop.layout.lock().unwrap().as_ref().map(|l| l.host);
    let target = if let Some(host) = previous_host.filter(|h| valid(*h)) {
        host
    } else {
        host()?
    };
    {
        let layout = desktop.layout.lock().unwrap();
        if let Some(current) = layout.as_ref() {
            let intact = current.labels.iter().all(|label| {
                app.get_webview_window(label)
                    .and_then(|w| w.hwnd().ok())
                    .is_some_and(|w| unsafe {
                        GetParent(HWND(w.0)).ok() == Some(hwnd(target.parent))
                    })
            });
            if !force && current.screens == displays && current.host == target && intact {
                if current.ready.len() != current.labels.len()
                    && current.created.elapsed() > Duration::from_secs(12)
                {
                    return Err("The desktop view did not become ready. Return to the window and try again.".into());
                }
                return Ok(());
            }
        }
    }
    let serial = desktop.serial.fetch_add(1, Ordering::SeqCst);
    let mut labels = Vec::new();
    for (index, screen) in displays.iter().enumerate() {
        let label = format!("wallpaper-{serial}-{index}");
        if let Err(error) = create(app, &label, target, screen) {
            close(app, &labels);
            return Err(error);
        }
        labels.push(label);
    }
    let previous = desktop.layout.lock().unwrap().replace(Layout {
        host: target,
        screens: displays,
        labels,
        ready: Vec::new(),
        created: Instant::now(),
    });
    if let Some(previous) = previous {
        close(app, &previous.labels);
    }
    crate::smoke_log("desktop-created");
    let _ = app.emit_to("main", "display-request", ());
    Ok(())
}
pub fn ready(app: &tauri::AppHandle, label: &str) -> Result<(), String> {
    let desktop = app.state::<Desktop>();
    if !desktop.enabled.load(Ordering::SeqCst) {
        return Ok(());
    }
    if desktop
        .layout
        .lock()
        .unwrap()
        .as_ref()
        .is_some_and(|l| l.labels.iter().any(|s| s == label))
    {
        if let Some(window) = app.get_webview_window(label) {
            window.show().map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
pub fn presented(app: &tauri::AppHandle, label: &str) -> Result<(), String> {
    let desktop = app.state::<Desktop>();
    if !desktop.enabled.load(Ordering::SeqCst) {
        return Ok(());
    }
    let mut layout = desktop.layout.lock().unwrap();
    let Some(current) = layout.as_mut() else {
        return Ok(());
    };
    if !current.labels.iter().any(|s| s == label) {
        return Ok(());
    }
    if let Some(window) = app.get_webview_window(label) {
        window.show().map_err(|e| e.to_string())?;
    }
    if !current.ready.iter().any(|s| s == label) {
        current.ready.push(label.into());
    }
    if current.ready.len() == current.labels.len() {
        crate::smoke_log("desktop-ready");
        if desktop.hide_when_ready.swap(false, Ordering::SeqCst) {
            if let Some(main) = app.get_webview_window("main") {
                main.hide().map_err(|e| e.to_string())?;
            }
        }
    }
    Ok(())
}
pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<(), String> {
    // WebView2 creation deadlocks in synchronous commands and event handlers.
    // Every entry point (IPC, tray and shortcuts) uses this serialized worker.
    let app = app.clone();
    std::thread::spawn(move || {
        let desktop = app.state::<Desktop>();
        let _operation = desktop.operation.lock().unwrap();
        if let Err(error) = set_inner(&app, enabled) {
            crate::smoke_log(&format!("desktop-error:{error}"));
            let _ = app.emit_to("main", "desktop-error", error);
        }
    });
    Ok(())
}
fn set_inner(app: &tauri::AppHandle, enabled: bool) -> Result<(), String> {
    let desktop = app.state::<Desktop>();
    if !enabled {
        desktop.enabled.store(false, Ordering::SeqCst);
        desktop.generation.fetch_add(1, Ordering::SeqCst);
        desktop.hide_when_ready.store(false, Ordering::SeqCst);
        if let Some(layout) = desktop.layout.lock().unwrap().take() {
            close(app, &layout.labels);
        }
        if let Some(main) = app.get_webview_window("main") {
            main.show()
                .and_then(|_| main.set_focus())
                .map_err(|e| e.to_string())?;
        }
        let _ = app.emit_to(
            "main",
            "desktop-state",
            serde_json::json!({"enabled":false}),
        );
        crate::smoke_log("desktop-stopped");
        return Ok(());
    }
    if desktop.enabled.load(Ordering::SeqCst) {
        return Ok(());
    }
    desktop.hide_when_ready.store(true, Ordering::SeqCst);
    desktop.enabled.store(true, Ordering::SeqCst);
    if let Err(error) = rebuild(app, true) {
        desktop.enabled.store(false, Ordering::SeqCst);
        desktop.hide_when_ready.store(false, Ordering::SeqCst);
        return Err(error);
    }
    let generation = desktop.generation.clone();
    let token = generation.fetch_add(1, Ordering::SeqCst) + 1;
    let _ = app.emit_to("main", "desktop-state", serde_json::json!({"enabled":true}));
    let handle = app.clone();
    std::thread::spawn(move || {
        let mut failures = 0;
        loop {
            std::thread::sleep(Duration::from_secs(1));
            let desktop = handle.state::<Desktop>();
            let _operation = desktop.operation.lock().unwrap();
            if generation.load(Ordering::SeqCst) != token {
                break;
            }
            // Keep WebView2 creation off the UI thread during recovery too.
            if let Err(error) = rebuild(&handle, false) {
                failures += 1;
                if failures >= 10 {
                    let _ = set_inner(&handle, false);
                    let _ = handle.emit_to(
                        "main",
                        "desktop-error",
                        format!("Desktop Mode returned to its window: {error}"),
                    );
                }
            } else {
                failures = 0;
            }
        }
    });
    Ok(())
}

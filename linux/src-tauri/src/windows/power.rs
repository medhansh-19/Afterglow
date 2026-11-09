use std::sync::atomic::Ordering;
use tauri::{Emitter, Manager};
use windows::{core::{w, GUID}, Win32::{Foundation::*, System::{Power::*, RemoteDesktop::*, LibraryLoader::GetModuleHandleW}, UI::WindowsAndMessaging::*}};
const DISPLAY: GUID = GUID::from_u128(0x6fe69556_704a_47a0_8f24_c28d936fda47);
struct Monitor { app: tauri::AppHandle, suspended: bool, locked: bool, display_off: bool }
impl Monitor {
    fn publish(&self) {
        let sleeping = self.suspended || self.locked || self.display_off;
        let mut status = SYSTEM_POWER_STATUS::default();
        let battery = unsafe { GetSystemPowerStatus(&mut status) }.is_ok() && (status.ACLineStatus == 0 || status.SystemStatusFlag == 1);
        let power = self.app.state::<crate::power::Power>();
        power.sleeping.store(sleeping, Ordering::SeqCst);
        power.on_battery.store(battery, Ordering::SeqCst);
        if sleeping { self.app.state::<crate::audio::Capture>().stop(); }
        let _ = self.app.emit("power-state", serde_json::json!({"sleeping":sleeping,"onBattery":battery}));
    }
}
unsafe extern "system" fn procedure(window: HWND, message: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    if message == WM_NCCREATE {
        let create = &*(lp.0 as *const CREATESTRUCTW);
        SetWindowLongPtrW(window, GWLP_USERDATA, create.lpCreateParams as isize);
    }
    let pointer = GetWindowLongPtrW(window, GWLP_USERDATA) as *mut Monitor;
    if !pointer.is_null() {
        let state = &mut *pointer;
        match message {
            WM_TIMER => state.publish(),
            WM_WTSSESSION_CHANGE => {
                if wp.0 == 7 { state.locked = true; }
                if wp.0 == 8 { state.locked = false; }
                state.publish();
            },
            WM_POWERBROADCAST => {
                match wp.0 as u32 {
                    PBT_APMSUSPEND => state.suspended = true,
                    PBT_APMRESUMEAUTOMATIC | PBT_APMRESUMESUSPEND => state.suspended = false,
                    PBT_POWERSETTINGCHANGE if lp.0 != 0 => {
                        let settings = &*(lp.0 as *const POWERBROADCAST_SETTING);
                        if settings.PowerSetting == DISPLAY && settings.DataLength == 4 {
                            let value = std::ptr::read_unaligned(settings.Data.as_ptr() as *const u32);
                            state.display_off = value == 0;
                        }
                    },
                    _ => {},
                }
                state.publish();
                return LRESULT(1);
            },
            _ => {},
        }
    }
    DefWindowProcW(window, message, wp, lp)
}
pub fn start(app: tauri::AppHandle) {
    std::thread::spawn(move || unsafe {
        let Ok(module) = GetModuleHandleW(None) else { return };
        let class = WNDCLASSW { lpfnWndProc: Some(procedure), hInstance: module.into(), lpszClassName: w!("AfterglowPowerMonitor"), ..Default::default() };
        if RegisterClassW(&class) == 0 { return; }
        let mut state = Box::new(Monitor { app, suspended:false, locked:false, display_off:false });
        let Ok(window) = CreateWindowExW(WINDOW_EX_STYLE(0), w!("AfterglowPowerMonitor"), w!("Afterglow power events"), WINDOW_STYLE(0), 0,0,0,0,None,None,Some(module.into()),Some((&mut *state as *mut Monitor).cast())) else { return };
        let notification = RegisterPowerSettingNotification(HANDLE(window.0), &DISPLAY, DEVICE_NOTIFY_WINDOW_HANDLE).ok();
        let _ = WTSRegisterSessionNotification(window, NOTIFY_FOR_THIS_SESSION);
        SetTimer(Some(window), 1, 30_000, None);
        state.publish();
        let mut message = MSG::default();
        while GetMessageW(&mut message, None, 0, 0).0 > 0 {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if let Some(notification) = notification { let _ = UnregisterPowerSettingNotification(notification); }
        let _ = WTSUnRegisterSessionNotification(window);
        let _ = DestroyWindow(window);
    });
}

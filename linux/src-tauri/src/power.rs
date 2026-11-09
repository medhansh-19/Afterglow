use std::sync::atomic::AtomicBool;
#[cfg(target_os = "linux")]
use std::sync::atomic::Ordering;
#[cfg(target_os = "linux")]
use tauri::{Emitter, Manager};
#[derive(Default)]
pub struct Power {
    pub sleeping: AtomicBool,
    pub on_battery: AtomicBool,
}
#[cfg(target_os = "linux")]
pub fn start(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        use dbus::blocking::stdintf::org_freedesktop_dbus::Properties;
        use dbus::{blocking::Connection, message::MatchRule};
        use std::time::{Duration, Instant};
        let Ok(connection) = Connection::new_system() else {
            return;
        };
        let handle = app.clone();
        let rule = MatchRule::new_signal("org.freedesktop.login1.Manager", "PrepareForSleep");
        let _ = connection.add_match(rule, move |(sleeping,): (bool,), _, _| {
            handle
                .state::<Power>()
                .sleeping
                .store(sleeping, Ordering::SeqCst);
            if sleeping {
                handle.state::<crate::audio::Capture>().stop();
            }
            let _ = handle.emit("power-state", serde_json::json!({"sleeping":sleeping}));
            true
        });
        let mut next = Instant::now();
        loop {
            let _ = connection.process(Duration::from_secs(1));
            if Instant::now() >= next {
                let proxy = connection.with_proxy(
                    "org.freedesktop.UPower",
                    "/org/freedesktop/UPower",
                    Duration::from_secs(1),
                );
                if let Ok(battery) = proxy.get::<bool>("org.freedesktop.UPower", "OnBattery") {
                    let _ = app.emit("power-state", serde_json::json!({"onBattery":battery}));
                }
                next = Instant::now() + Duration::from_secs(30);
            }
        }
    });
}
#[cfg(not(any(target_os = "linux", target_os = "windows")))]
pub fn start(_: tauri::AppHandle) {}

#[cfg(target_os = "windows")]
pub use crate::windows::power::start;

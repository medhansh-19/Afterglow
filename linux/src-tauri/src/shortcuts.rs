use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{Emitter, Manager};
#[derive(Default)]
pub struct Shortcuts(pub AtomicBool);
pub fn start(app: tauri::AppHandle) -> Result<(), String> {
    if app.state::<Shortcuts>().0.swap(true, Ordering::SeqCst) {
        return Err(
            "Shortcut setup is already active. Restart Afterglow to bind a new session.".into(),
        );
    }
    std::thread::spawn(move || {
        let result = run(&app);
        app.state::<Shortcuts>().0.store(false, Ordering::SeqCst);
        if let Err(error) = result {
            let _ = app.emit("shortcut-state", error);
        }
    });
    Ok(())
}
#[cfg(target_os = "linux")]
fn run(app: &tauri::AppHandle) -> Result<(), String> {
    use dbus::{
        arg::{PropMap, RefArg, Variant},
        blocking::Connection,
        message::MatchRule,
        Path,
    };
    use std::{
        sync::{Arc, Mutex},
        time::{Duration, Instant},
    };
    const INTERFACE: &str = "org.freedesktop.portal.GlobalShortcuts";
    fn options(token: &str) -> PropMap {
        let mut p = PropMap::new();
        p.insert("handle_token".into(), Variant(Box::new(token.to_owned())));
        p
    }
    fn response<F>(connection: &Connection, token: &str, request: F) -> Result<PropMap, String>
    where
        F: FnOnce() -> Result<(Path<'static>,), dbus::Error>,
    {
        let sender = connection
            .unique_name()
            .trim_start_matches(':')
            .replace('.', "_");
        let expected = format!("/org/freedesktop/portal/desktop/request/{sender}/{token}");
        let result = Arc::new(Mutex::new(None));
        let pending = result.clone();
        let rule = MatchRule::new_signal("org.freedesktop.portal.Request", "Response")
            .with_path(expected.clone());
        let subscription = connection
            .add_match(rule, move |(code, values): (u32, PropMap), _, _| {
                *pending.lock().unwrap() = Some((code, values));
                true
            })
            .map_err(|e| e.to_string())?;
        let outcome = (|| {
            let (actual,) = request()
                .map_err(|e| format!("Global shortcuts are unavailable on this desktop: {e}"))?;
            if actual.to_string() != expected {
                return Err("The shortcut portal returned an unexpected request path.".into());
            }
            let deadline = Instant::now() + Duration::from_secs(120);
            while Instant::now() < deadline {
                connection
                    .process(Duration::from_millis(250))
                    .map_err(|e| e.to_string())?;
                if let Some((code, values)) = result.lock().unwrap().take() {
                    return if code == 0 {
                        Ok(values)
                    } else {
                        Err("Global shortcut permission was not granted. Focused shortcuts remain available.".into())
                    };
                }
            }
            let proxy = connection.with_proxy(
                "org.freedesktop.portal.Desktop",
                actual,
                Duration::from_secs(2),
            );
            let _: Result<(), _> = proxy.method_call("org.freedesktop.portal.Request", "Close", ());
            Err("Shortcut setup timed out. You can try again.".into())
        })();
        let _ = connection.remove_match(subscription);
        outcome
    }
    let connection = Connection::new_session().map_err(|e| e.to_string())?;
    let proxy = connection.with_proxy(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        Duration::from_secs(5),
    );
    let mut opts = options("afterglow_create");
    opts.insert(
        "session_handle_token".into(),
        Variant(Box::new("afterglow_shortcuts".to_owned())),
    );
    let created = response(&connection, "afterglow_create", || {
        proxy.method_call(INTERFACE, "CreateSession", (opts,))
    })?;
    let session = created
        .get("session_handle")
        .and_then(|v| v.0.as_str())
        .ok_or("Shortcut session was not created")?
        .to_owned();
    let path = Path::new(session.clone()).map_err(|e| e.to_string())?;
    let shortcuts: Vec<(String, PropMap)> = [
        ("focus", "Focus Mode", "CTRL+SHIFT+f"),
        ("desktop", "Desktop Mode", "CTRL+SHIFT+d"),
        ("beats", "Beat Sync Settings", "CTRL+SHIFT+b"),
        ("appearance", "Appearance", "CTRL+SHIFT+a"),
        ("capture", "Capture Lyric Map", "CTRL+SHIFT+m"),
    ]
    .into_iter()
    .map(|(id, description, trigger)| {
        let mut values = PropMap::new();
        values.insert(
            "description".into(),
            Variant(Box::new(description.to_owned())),
        );
        values.insert(
            "preferred_trigger".into(),
            Variant(Box::new(trigger.to_owned())),
        );
        (id.into(), values)
    })
    .collect();
    let bound = response(&connection, "afterglow_bind", || {
        proxy.method_call(
            INTERFACE,
            "BindShortcuts",
            (path, shortcuts, "", options("afterglow_bind")),
        )
    })?;
    if bound
        .get("shortcuts")
        .and_then(|v| v.0.as_iter())
        .map(|items| items.count())
        .unwrap_or(0)
        == 0
    {
        return Err(
            "The desktop did not bind any shortcuts. Use desktop keyboard settings instead.".into(),
        );
    }
    let handle = app.clone();
    connection
        .add_match(
            MatchRule::new_signal(INTERFACE, "Activated"),
            move |(active, id, _time, _options): (Path<'static>, String, u64, PropMap), _, _| {
                if active.to_string() == session {
                    let _ = handle.emit_to("main", "action", id);
                }
                true
            },
        )
        .map_err(|e| e.to_string())?;
    let _ = app.emit(
        "shortcut-state",
        "Global shortcuts enabled. Manage their bindings in your desktop settings.",
    );
    loop {
        connection
            .process(Duration::from_secs(1))
            .map_err(|e| e.to_string())?;
    }
}
#[cfg(not(any(target_os = "linux", target_os = "windows")))]
fn run(_: &tauri::AppHandle) -> Result<(), String> {
    Err("Global shortcut integration requires Linux.".into())
}

#[cfg(target_os = "windows")]
fn run(app: &tauri::AppHandle) -> Result<(), String> {
    crate::windows::shortcuts::run(app)
}

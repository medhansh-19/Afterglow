//! Cached display state and a ready handshake prevent dropped first frames or images.
use serde_json::Value;
use std::sync::Mutex;
use tauri::{Emitter, Manager};
#[derive(Default)]
pub struct Display(pub Mutex<Option<Value>>);
pub fn is_wallpaper(label: &str) -> bool {
    label == "wallpaper" || label.starts_with("wallpaper-")
}
fn merge(current: &mut Value, incoming: &Value) {
    let (Some(target), Some(update)) = (current.as_object_mut(), incoming.as_object()) else {
        return;
    };
    for (key, value) in update {
        if key == "settings" {
            if let (Some(old), Some(new)) = (
                target.get_mut(key).and_then(Value::as_object_mut),
                value.as_object(),
            ) {
                old.extend(new.clone());
                continue;
            }
        }
        target.insert(key.clone(), value.clone());
    }
}
pub fn publish(app: &tauri::AppHandle, state: Value) -> Result<(), String> {
    {
        let display = app.state::<Display>();
        let mut cached = display.0.lock().map_err(|_| "Display state unavailable")?;
        if let Some(current) = cached.as_mut() {
            merge(current, &state);
        } else {
            *cached = Some(state.clone());
        }
    }
    for (label, _) in app.webview_windows() {
        if is_wallpaper(&label) {
            app.emit_to(&label, "display-state", &state)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
pub fn ready(app: &tauri::AppHandle, label: &str) -> Result<(), String> {
    if !is_wallpaper(label) {
        return Err("This command belongs to the wallpaper renderer.".into());
    }
    if let Some(state) = app
        .state::<Display>()
        .0
        .lock()
        .map_err(|_| "Display state unavailable")?
        .as_ref()
    {
        app.emit_to(label, "display-state", state)
            .map_err(|e| e.to_string())?;
    }
    app.emit_to("main", "display-request", ())
        .map_err(|e| e.to_string())?;
    #[cfg(target_os = "windows")]
    crate::windows::desktop::ready(app, label)?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn deltas_retain_wallpaper_lyrics_and_merge_preferences() {
        let mut state = serde_json::json!({"settings":{"wallpaper":"data:image","color":"#fff"},"lyrics":[{"text":"Light"}],"sample":{"position":1}});
        merge(
            &mut state,
            &serde_json::json!({"settings":{"color":"#aaa"},"sample":{"position":2}}),
        );
        assert_eq!(state["settings"]["wallpaper"], "data:image");
        assert_eq!(state["settings"]["color"], "#aaa");
        assert_eq!(state["lyrics"][0]["text"], "Light");
        assert_eq!(state["sample"]["position"], 2);
        merge(
            &mut state,
            &serde_json::json!({"settings":{"wallpaper":null},"lyrics":[]}),
        );
        assert!(state["settings"]["wallpaper"].is_null());
        assert_eq!(state["lyrics"].as_array().unwrap().len(), 0);
    }
}

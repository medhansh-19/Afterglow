#[cfg(target_os = "linux")]
use tauri::Manager;
#[cfg(target_os = "linux")]
pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<(), String> {
    use gtk::prelude::*;
    use gtk_layer_shell::LayerShell;
    let main = app
        .get_webview_window("main")
        .ok_or("Main window unavailable")?;
    if !enabled {
        if let Some(wallpaper) = app.get_webview_window("wallpaper") {
            wallpaper.close().map_err(|e| e.to_string())?;
        }
        main.show().map_err(|e| e.to_string())?;
        main.set_focus().map_err(|e| e.to_string())?;
        return Ok(());
    }
    if app.get_webview_window("wallpaper").is_some() {
        return Ok(());
    }
    let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some()
        && std::env::var("GDK_BACKEND").unwrap_or_default() != "x11";
    if wayland && !gtk_layer_shell::is_supported() {
        return Err("This Wayland desktop does not support Layer Shell (GNOME requires a separate integration). Focus Mode remains available.".into());
    }
    let monitor = main
        .current_monitor()
        .map_err(|e| e.to_string())?
        .ok_or("Display unavailable")?;
    let wallpaper = tauri::WebviewWindowBuilder::new(
        app,
        "wallpaper",
        tauri::WebviewUrl::App("index.html".into()),
    )
    .title("Afterglow Wallpaper")
    .visible(false)
    .decorations(false)
    .skip_taskbar(true)
    .focused(false)
    .initialization_script("window.__AFTERGLOW_WALLPAPER__=true;")
    .build()
    .map_err(|e| e.to_string())?;
    let native = wallpaper.gtk_window().map_err(|e| e.to_string())?;
    if wayland {
        if native.is_realized() {
            let _ = wallpaper.close();
            return Err("The wallpaper surface was realized too early. This desktop needs the dedicated wallpaper host; use Focus Mode.".into());
        }
        native.init_layer_shell();
        native.set_layer(gtk_layer_shell::Layer::Background);
        native.set_namespace("afterglow");
        native.set_exclusive_zone(-1);
        native.set_keyboard_mode(gtk_layer_shell::KeyboardMode::None);
        for edge in [
            gtk_layer_shell::Edge::Top,
            gtk_layer_shell::Edge::Bottom,
            gtk_layer_shell::Edge::Left,
            gtk_layer_shell::Edge::Right,
        ] {
            native.set_anchor(edge, true);
        }
        let display = native.display();
        if let Some(gdk_monitor) =
            display.monitor_at_point(monitor.position().x, monitor.position().y)
        {
            native.set_monitor(&gdk_monitor);
        }
    } else {
        native.set_type_hint(gtk::gdk::WindowTypeHint::Desktop);
        native.stick();
        native.set_keep_below(true);
        native.set_skip_taskbar_hint(true);
        native.set_skip_pager_hint(true);
        wallpaper
            .set_position(*monitor.position())
            .map_err(|e| e.to_string())?;
        wallpaper
            .set_size(*monitor.size())
            .map_err(|e| e.to_string())?;
    }
    // GTK needs a realized GdkWindow before the input region can be changed.
    wallpaper.show().map_err(|e| e.to_string())?;
    wallpaper
        .set_ignore_cursor_events(true)
        .map_err(|e| e.to_string())?;
    main.hide().map_err(|e| e.to_string())?;
    eprintln!(
        "Afterglow wallpaper ready: {}",
        if wayland { "Wayland" } else { "X11" }
    );
    Ok(())
}
#[cfg(not(any(target_os = "linux", target_os = "windows")))]
pub fn set(_: &tauri::AppHandle, _: bool) -> Result<(), String> {
    Err("Desktop mode requires Linux.".into())
}

#[cfg(target_os = "windows")]
pub use crate::windows::desktop::set;

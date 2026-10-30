import AppKit
import SwiftUI

struct AfterglowMenu: View {
  @ObservedObject var model: DisplayModel
  @ObservedObject var beats: BeatCapture
  @ObservedObject var desktop: DesktopMode
  @ObservedObject var shortcut: FocusShortcut
  @ObservedObject var desktopShortcut: FocusShortcut
  @ObservedObject var beatShortcut: FocusShortcut
  @ObservedObject var panels: DisplayPanels
  var includeQuit = true
  @Environment(\.openWindow) private var openWindow
  @AppStorage("afterglow.clock") private var showClock = true
  @AppStorage("afterglow.motion") private var motion = true
  @AppStorage("afterglow.estimatedWords") private var estimatedWords = true
  @AppStorage("afterglow.tint") private var tintName = Tint.album.rawValue

  var body: some View {
    if let track = model.track {
      Text(track.title)
      Text(track.artist)
      Text(model.isDemo ? "Demo" : model.playing ? "Playing" : "Paused")
    } else {
      Text("Afterglow")
    }
    Divider()
    Button(desktop.isFocused ? "Exit Focus Mode" : "Focus Mode — Hide Widgets & Stage Manager") {
      desktop.toggleFocus()
    }
    .disabled(desktop.window == nil || desktop.isTransitioning)
    Toggle(
      "Desktop Mode", isOn: Binding(get: { desktop.isEnabled }, set: { _ in desktop.toggle() })
    )
    .disabled(desktop.window == nil || desktop.isTransitioning)
    Button(desktop.isEnabled ? "Return to Window Mode" : "Open Afterglow") {
      if desktop.isEnabled { desktop.restore() }
      openWindow(id: "display")
      NSApp.activate(ignoringOtherApps: true)
      desktop.window?.makeKeyAndOrderFront(nil)
    }
    .disabled(desktop.isFocused || desktop.isTransitioning)
    Button("Enter or Exit Full Screen") { desktop.window?.toggleFullScreen(nil) }
      .disabled(desktop.window == nil || desktop.isQuiet || desktop.isTransitioning)
    Divider()
    if model.connected {
      Button(model.playing ? "Pause" : "Play") {
        if model.isDemo { model.toggleDemo() } else { model.transport(.togglePlayPause) }
      }
      if !model.isDemo {
        Button("Previous Track") { model.transport(.previous) }
        Button("Next Track") { model.transport(.next) }
        Button("Stop Playback") { model.transport(.stop) }
      }
    }
    Menu("Music Player") {
      Button("Connect Spotify") { model.connect(.spotify) }
      Button("Connect Apple Music") { model.connect(.music) }
      Button("Try Demo") { model.demo() }
      if model.connected { Button("Disconnect") { model.disconnect() } }
    }
    Menu("Keyboard Shortcuts") {
      Toggle(
        "Use ⇧⌘F Globally",
        isOn: Binding(get: { shortcut.isEnabled }, set: { shortcut.setEnabled($0) }))
      Text(shortcut.status)
      Toggle("Use ⇧⌘D Globally", isOn: Binding(
        get: { desktopShortcut.isEnabled }, set: { desktopShortcut.setEnabled($0) }))
      Text(desktopShortcut.status)
      Toggle("Use ⇧⌘B Globally", isOn: Binding(
        get: { beatShortcut.isEnabled }, set: { beatShortcut.setEnabled($0) }))
      Text(beatShortcut.status)
    }
    Button("Appearance & Wallpaper…") { present(.wallpaper) }
    Button("Lyric Library & Imports…") { present(.library) }
    if model.track != nil, !model.isDemo, model.lines.isEmpty {
      Button(model.loading ? "Finding Synced Lyrics…" : "Retry Synced Lyrics") { model.retryLyrics() }
        .disabled(model.loading)
    }
    Menu("Lyric Timing") {
      Button("Timing Settings…") { present(.timing) }
      Toggle("Word-by-Word Progression", isOn: $estimatedWords)
      Text(model.timingDescription)
      Text(String(format: "Adjustment: %+.2f s", model.timingDelay))
      Button("Lyrics Earlier (0.1 s)") { model.setTimingDelay(model.timingDelay - 0.1) }
        .disabled(model.track == nil || model.timingDelay <= -5)
      Button("Lyrics Later (0.1 s)") { model.setTimingDelay(model.timingDelay + 0.1) }
        .disabled(model.track == nil || model.timingDelay >= 5)
      Button("Reset Timing for This Recording") { model.setTimingDelay(0) }
        .disabled(model.track == nil)
    }
    Button("Beat Sync Settings…") { present(.beats) }
    Text(beats.state)
    if beats.running || beats.starting {
      Button("Disable Beat Sync") { beats.stop() }
        .keyboardShortcut("b", modifiers: [.command, .shift])
    } else {
      Button("Enable Beat Sync") {
        guard let source = model.source else { return }
        Task { await beats.start(source: source) }
      }
      .keyboardShortcut("b", modifiers: [.command, .shift])
      .disabled(model.source == nil)
    }
    if !model.message.isEmpty { Text(model.message) }
    if let error = model.error ?? model.controlError { Text(error) }
    if includeQuit {
      Divider()
      Button("Quit Afterglow") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
  }

  private func present(_ panel: DisplayPanels.Panel) {
    if desktop.isEnabled { desktop.restore() }
    openWindow(id: "display")
    NSApp.activate(ignoringOtherApps: true)
    desktop.window?.makeKeyAndOrderFront(nil)
    panels.presented = panel
  }
}

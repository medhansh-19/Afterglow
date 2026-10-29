import AppKit
import SwiftUI

@main
struct AfterglowApp: App {
  @NSApplicationDelegateAdaptor(AfterglowDelegate.self) private var delegate
  @StateObject private var shortcut = FocusShortcut()
  @StateObject private var model = DisplayModel()
  @StateObject private var beats = BeatCapture()
  @StateObject private var desktop = DesktopMode()
  @StateObject private var appearance = WallpaperAppearance()
  @StateObject private var panels = DisplayPanels()
  var body: some Scene {
    Window("Afterglow", id: "display") {
      DisplayView(model: model, beats: beats, desktop: desktop, panels: panels, appearance: appearance)
        .background(DisplayWindowReader(mode: desktop))
        .modifier(FocusShortcutSetup(shortcut: shortcut, desktop: desktop, delegate: delegate))
        .frame(minWidth: 720, minHeight: 640)
        .preferredColorScheme(.dark)
        .onAppear {
          if ProcessInfo.processInfo.arguments.contains("--demo") { model.demo() }
          if ProcessInfo.processInfo.arguments.contains("--onboarding") { model.disconnect() }
        }
    }
    .defaultSize(width: 1120, height: 740)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandMenu("Controls") {
        AfterglowMenu(model: model, beats: beats, desktop: desktop, shortcut: shortcut, panels: panels, includeQuit: false)
      }
      CommandMenu("Display") {
        Button(desktop.isFocused ? "Exit Focus Mode" : "Focus Mode — Hide Widgets & Stage Manager")
        {
          desktop.toggleFocus()
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .disabled(desktop.window == nil || desktop.isTransitioning)
        Button("Enter or exit full screen") { DisplayWindow.toggleFullScreen() }
          .disabled(desktop.isQuiet || desktop.isTransitioning)
          .keyboardShortcut("f", modifiers: .command)
        Toggle(
          "Desktop Mode", isOn: Binding(get: { desktop.isEnabled }, set: { _ in desktop.toggle() })
        )
        .keyboardShortcut("w", modifiers: [.command, .option])
        .disabled(desktop.window == nil || desktop.isTransitioning || desktop.isFocused)
        Toggle(
          "Use ⇧⌘F Globally",
          isOn: Binding(get: { shortcut.isEnabled }, set: { shortcut.setEnabled($0) }))
        Text(shortcut.status)
        Button("Try demo") { model.demo() }
          .keyboardShortcut("d", modifiers: .command)
        Button("Disconnect player") { model.disconnect() }
      }
    }
    MenuBarExtra("Afterglow", systemImage: "waveform.path") {
      AfterglowMenu(model: model, beats: beats, desktop: desktop, shortcut: shortcut, panels: panels)
    }
  }
}

@MainActor
enum DisplayWindow {
  static var window: NSWindow? {
    NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
  }
  static func toggleFullScreen() { window?.toggleFullScreen(nil) }
  static func exitFullScreen() {
    if let window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
  }
}

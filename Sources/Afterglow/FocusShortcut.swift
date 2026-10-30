import AppKit
import Carbon
import SwiftUI

/// Claims a named shortcut; no event tap, keyboard monitor, or Accessibility grant.
@MainActor
final class FocusShortcut: ObservableObject {
  @Published private(set) var isEnabled: Bool
  @Published private(set) var isRegistered = false
  @Published private(set) var status = ""
  private let keyCode: UInt32
  private let identifier: UInt32
  private let preferenceKey: String
  private let keyLabel: String
  private let actionLabel: String
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var action: (@MainActor () -> Void)?
  private static let signature: OSType = 0x4146_474C  // AFGL

  init(keyCode: UInt32 = UInt32(kVK_ANSI_F), identifier: UInt32 = 1,
       preferenceKey: String = "afterglow.globalFocusShortcut", keyLabel: String = "⇧⌘F",
       actionLabel: String = "Focus") {
    self.keyCode = keyCode
    self.identifier = identifier
    self.preferenceKey = preferenceKey
    self.keyLabel = keyLabel
    self.actionLabel = actionLabel
    isEnabled = UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
  }

  static func desktop() -> FocusShortcut {
    .init(keyCode: UInt32(kVK_ANSI_D), identifier: 2,
          preferenceKey: "afterglow.globalDesktopShortcut", keyLabel: "⇧⌘D", actionLabel: "Desktop view")
  }

  static func beatSync() -> FocusShortcut {
    .init(keyCode: UInt32(kVK_ANSI_B), identifier: 3,
          preferenceKey: "afterglow.globalBeatShortcut", keyLabel: "⇧⌘B", actionLabel: "Beat Sync")
  }

  func configure(action: @escaping @MainActor () -> Void) {
    self.action = action
    if isEnabled { register() }
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: preferenceKey)
    if enabled { register() } else { unregister() }
  }

  private func register() {
    guard hotKey == nil else { return }
    if handler == nil {
      var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let result = InstallEventHandler(
        GetEventDispatcherTarget(),
        { _, event, context in
          guard let event, let context else { return OSStatus(eventNotHandledErr) }
          var identifier = EventHotKeyID()
          let result = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
            MemoryLayout<EventHotKeyID>.size, nil, &identifier)
          guard result == noErr, identifier.signature == 0x4146_474C else {
            return OSStatus(eventNotHandledErr)
          }
          return MainActor.assumeIsolated {
            let shortcut = Unmanaged<FocusShortcut>.fromOpaque(context).takeUnretainedValue()
            guard identifier.id == shortcut.identifier else { return OSStatus(eventNotHandledErr) }
            shortcut.action?()
            return noErr
          }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
      guard result == noErr else {
        status = "Global shortcut could not start. Use the waveform menu."
        return
      }
    }
    let result = RegisterEventHotKey(
      keyCode, UInt32(cmdKey | shiftKey),
      EventHotKeyID(signature: Self.signature, id: identifier),
      GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
    isRegistered = result == noErr
    status =
      isRegistered
      ? "\(keyLabel) toggles \(actionLabel) from any app."
      : "\(keyLabel) is unavailable. Release it in the other app, then toggle this setting again."
  }

  private func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    isRegistered = false
    status = "\(keyLabel) works only while Afterglow is active."
  }

  isolated deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
  }
}

/// Keeps the global action available even after closing the ordinary display window.
struct FocusShortcutSetup: ViewModifier {
  @ObservedObject var shortcut: FocusShortcut
  @ObservedObject var desktopShortcut: FocusShortcut
  @ObservedObject var beatShortcut: FocusShortcut
  let desktop: DesktopMode
  let beats: BeatCapture
  let model: DisplayModel
  let panels: DisplayPanels
  let delegate: AfterglowDelegate
  @Environment(\.openWindow) private var openWindow

  func body(content: Content) -> some View {
    content.onAppear {
      shortcut.configure {
        if desktop.window != nil {
          desktop.toggleFocus()
        } else {
          openWindow(id: "display")
          Task { @MainActor in
            // Wait for SwiftUI to attach the reopened window, without blocking the UI.
            for _ in 0..<20 {
              if desktop.window != nil {
                desktop.toggleFocus()
                return
              }
              try? await Task.sleep(for: .milliseconds(50))
            }
          }
        }
      }
      desktopShortcut.configure {
        if desktop.window != nil {
          desktop.toggle()
        } else {
          openWindow(id: "display")
          Task { @MainActor in
            for _ in 0..<20 {
              if desktop.window != nil { desktop.toggle(); return }
              try? await Task.sleep(for: .milliseconds(50))
            }
          }
        }
      }
      beatShortcut.configure {
        if beats.running || beats.starting { beats.stop(); return }
        guard let source = model.source else {
          openWindow(id: "display")
          NSApp.activate(ignoringOtherApps: true)
          panels.presented = .beats
          return
        }
        Task { await beats.start(source: source) }
      }
      delegate.reopen = {
        guard desktop.isEnabled else { return true }
        desktop.toggleFocus()
        return false
      }
    }
  }
}

@MainActor
final class AfterglowDelegate: NSObject, NSApplicationDelegate {
  var reopen: (() -> Bool)?
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    reopen?() ?? true
  }
}

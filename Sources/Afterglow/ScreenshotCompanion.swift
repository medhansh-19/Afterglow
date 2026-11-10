import AppKit
import CoreGraphics

/// Observes screenshot gestures. The listen-only tap cannot consume or change an event.
@MainActor
final class ScreenshotCompanion: ObservableObject {
  @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "afterglow.screenshotCompanion")
  @Published private(set) var status = "Enable to offer a lyric map after ⇧⌘3 or ⇧⌘4."
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var pending: LyricMapCapture?
  private var pendingSince: Date?
  private var presentation: Task<Void, Never>?
  private weak var panels: DisplayPanels?

  func configure(panels: DisplayPanels) {
    self.panels = panels
    if enabled { start(requestAccess: false) }
  }
  func setEnabled(_ value: Bool) {
    enabled = value
    UserDefaults.standard.set(value, forKey: "afterglow.screenshotCompanion")
    if value { start(requestAccess: true) } else { stop(); status = "Screenshot companion is off." }
  }
  func retry() { if enabled { start(requestAccess: true) } }
  private func start(requestAccess: Bool) {
    guard tap == nil else { return }
    guard CGPreflightListenEventAccess() || (requestAccess && CGRequestListenEventAccess()) else {
      status = "Allow Afterglow in System Settings → Privacy & Security → Input Monitoring, then retry."
      return
    }
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
    guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
      options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        // This tap is attached only to the main run loop.
        MainActor.assumeIsolated {
          let observer = Unmanaged<ScreenshotCompanion>.fromOpaque(context).takeUnretainedValue()
          if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = observer.tap { CGEvent.tapEnable(tap: tap, enable: true) }
          } else {
            observer.observe(type: type, key: event.getIntegerValueField(.keyboardEventKeycode),
              flags: event.flags, repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
          }
        }
        return Unmanaged.passUnretained(event)
      }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
      status = "Screenshot companion couldn’t start. Check Input Monitoring and retry."
      return
    }
    tap = port
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    status = "Afterglow offers a card after screenshots while its lyric map is visible."
  }
  static func screenshotKey(_ key: Int64, flags: CGEventFlags, repeating: Bool) -> Bool {
    let modifiers = flags.intersection([.maskCommand, .maskShift, .maskAlternate])
    return !repeating && modifiers == [.maskCommand, .maskShift] && (key == 20 || key == 21)
  }
  private func observe(type: CGEventType, key: Int64, flags: CGEventFlags, repeating: Bool) {
    if let since = pendingSince, Date().timeIntervalSince(since) > 120 { pending = nil; pendingSince = nil }
    if type == .keyDown {
      if key == 53 { pending = nil; pendingSince = nil; presentation?.cancel(); return }
      if Self.screenshotKey(key, flags: flags, repeating: repeating) {
        presentation?.cancel()
        // Freeze before the system screenshot UI appears. Never bring Afterglow forward here.
        pending = panels?.captureLyricMap?()
        pendingSince = pending == nil ? nil : Date()
        if key == 20 { presentAfterScreenshot() } // ANSI 3; ANSI 4 waits for the selection.
      } else if key == 36, pending != nil {
        presentAfterScreenshot()
      }
    } else if type == .leftMouseUp, pending != nil {
      presentAfterScreenshot()
    }
  }
  private func presentAfterScreenshot() {
    guard let captured = pending else { return }
    pending = nil; pendingSince = nil
    presentation?.cancel()
    presentation = Task { @MainActor [weak self] in
      // Let macOS complete its capture before showing our separate preview.
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
      guard let self, self.enabled else { return }
      self.panels?.showCapturedMap(captured)
    }
  }
  private func stop() {
    presentation?.cancel(); pending = nil; pendingSince = nil
    if let tap { CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil; source = nil
  }
  isolated deinit {
    presentation?.cancel()
    if let tap { CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
  }
}

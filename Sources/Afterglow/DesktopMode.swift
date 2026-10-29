import AppKit
import SwiftUI

/// Reuses the existing display, so changing modes never creates a second audio stream.
@MainActor
final class DesktopMode: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var isVisible = true
  @Published private(set) var isTransitioning = false
  @Published private(set) var isFocused = false
  var isQuiet: Bool { isEnabled || isFocused }
  private var returnToDesktop = false
  private var desktopAfterFullScreenExit = false
  private(set) weak var window: NSWindow?
  private var saved: WindowState?
  private var displayID: CGDirectDisplayID?
  private var observers: [NSObjectProtocol] = []

  private struct WindowState {
    let frame: NSRect
    let style: NSWindow.StyleMask
    let behavior: NSWindow.CollectionBehavior
    let level: NSWindow.Level
    let shadow: Bool
    let canHide: Bool
    let minimum: NSSize
  }

  func attach(_ window: NSWindow) {
    guard self.window !== window else { return }
    self.window = window
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    observe(NSWindow.didExitFullScreenNotification, object: window) { mode in
      let resumeDesktop =
        mode.desktopAfterFullScreenExit || (mode.isFocused && mode.returnToDesktop)
      mode.isTransitioning = false
      mode.isFocused = false
      mode.returnToDesktop = false
      mode.desktopAfterFullScreenExit = false
      if resumeDesktop { mode.enable() }
    }
    observe(NSWindow.didEnterFullScreenNotification, object: window) { $0.isTransitioning = false }
    observe(NSWindow.didChangeOcclusionStateNotification, object: window) { mode in
      mode.isVisible = mode.window?.occlusionState.contains(.visible) == true
    }
    observe(NSApplication.didChangeScreenParametersNotification) { $0.fitDesktop() }
    observe(NSWindow.willCloseNotification, object: window) { mode in
      mode.restore(activate: false)
      mode.isTransitioning = false
      mode.isFocused = false
      mode.returnToDesktop = false
      mode.desktopAfterFullScreenExit = false
      mode.window = nil
    }
  }

  private func observe(
    _ name: Notification.Name, object: AnyObject? = nil,
    action: @escaping @MainActor (DesktopMode) -> Void
  ) {
    observers.append(
      NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated { if let self { action(self) } }
      })
  }

  func toggle() {
    guard !isTransitioning else { return }
    if isEnabled { restore() } else { enable() }
  }

  func toggleFocus() {
    guard !isTransitioning else { return }
    if isFocused { exitFocus() } else { enterFocus() }
  }

  private func enterFocus() {
    guard let window else { return }
    returnToDesktop = isEnabled
    if isEnabled { restore() }
    isFocused = true
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    if !window.styleMask.contains(.fullScreen) {
      isTransitioning = true
      window.toggleFullScreen(nil)
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard let self, self.isTransitioning, self.isFocused else { return }
        self.isTransitioning = false
        if self.window?.styleMask.contains(.fullScreen) != true {
          self.isFocused = false
          let resumeDesktop = self.returnToDesktop
          self.returnToDesktop = false
          if resumeDesktop { self.enable() }
        }
      }
    }
  }

  func exitFocus() {
    guard isFocused, !isTransitioning, let window else { return }
    if window.styleMask.contains(.fullScreen) {
      isTransitioning = true
      window.toggleFullScreen(nil)
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        if self?.isTransitioning == true { self?.isTransitioning = false }
      }
    } else {
      isFocused = false
      let resumeDesktop = returnToDesktop
      returnToDesktop = false
      if resumeDesktop { enable() }
    }
  }

  private func enable() {
    guard let window, !isEnabled else { return }
    if window.styleMask.contains(.fullScreen) {
      isTransitioning = true
      desktopAfterFullScreenExit = true
      window.toggleFullScreen(nil)
      // AppKit reports full-screen failure through its existing SwiftUI delegate.
      // Release the toggle if no exit notification arrives, without replacing that delegate.
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        if self?.isTransitioning == true {
          self?.isTransitioning = false
          self?.desktopAfterFullScreenExit = false
        }
      }
      return
    }
    saved = WindowState(
      frame: window.frame, style: window.styleMask,
      behavior: window.collectionBehavior, level: window.level,
      shadow: window.hasShadow, canHide: window.canHide, minimum: window.minSize)
    displayID =
      (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
      .uint32Value
    window.ignoresMouseEvents = true
    window.styleMask = [.borderless]
    window.minSize = .zero
    window.hasShadow = false
    window.canHide = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    // Above the system wallpaper, below Finder's desktop icons and ordinary windows.
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    isEnabled = true
    fitDesktop()
    window.orderFrontRegardless()
    window.resignKey()
    window.resignMain()
  }

  func restore(activate: Bool = true) {
    guard let window, let saved, isEnabled else { return }
    isEnabled = false
    window.orderOut(nil)
    window.level = saved.level
    window.collectionBehavior = saved.behavior
    window.styleMask = saved.style
    window.minSize = saved.minimum
    window.hasShadow = saved.shadow
    window.canHide = saved.canHide
    window.ignoresMouseEvents = false
    // If its old display was unplugged, bring the controls back onto an available screen.
    let screen = NSScreen.screens.first { $0.visibleFrame.intersects(saved.frame) } ?? NSScreen.main
    var frame = saved.frame
    if let visible = screen?.visibleFrame {
      frame.size.width = min(frame.width, visible.width)
      frame.size.height = min(frame.height, visible.height)
      frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
      frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
    }
    window.setFrame(frame, display: true)
    self.saved = nil
    if activate {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func fitDesktop() {
    guard isEnabled, let window else { return }
    let screen =
      NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == displayID
      } ?? NSScreen.main
    if let screen { window.setFrame(screen.frame, display: true) }
  }
}

struct DisplayWindowReader: NSViewRepresentable {
  let mode: DesktopMode
  func makeNSView(context: Context) -> Reader { Reader(mode: mode) }
  func updateNSView(_ view: Reader, context: Context) {}

  final class Reader: NSView {
    let mode: DesktopMode
    init(mode: DesktopMode) {
      self.mode = mode
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window { mode.attach(window) }
    }
  }
}

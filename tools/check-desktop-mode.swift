import AppKit
import SwiftUI

@main struct DesktopModeChecks {
  @MainActor static func main() {
    _ = NSApplication.shared
    let mode = DesktopMode()
    let window = NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 850, height: 650),
      styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 720, height: 640)
    let originalFrame = window.frame
    let originalStyle = window.styleMask
    let originalBehavior = window.collectionBehavior
    let originalLevel = window.level
    let originalMinimum = window.minSize
    mode.attach(window)
    var count = 0
    func check(_ condition: Bool, _ name: String) {
      precondition(condition, name)
      count += 1
      print("PASS \(name)")
    }
    for _ in 0..<3 {
      mode.toggle()
      check(mode.isEnabled, "desktop mode enables")
      check(window.styleMask == [.borderless], "wallpaper has no window chrome")
      check(window.ignoresMouseEvents, "desktop clicks pass through")
      check(
        window.level.rawValue > Int(CGWindowLevelForKey(.desktopWindow)), "above system wallpaper")
      check(
        window.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow)), "below desktop icons")
      check(window.level.rawValue < NSWindow.Level.normal.rawValue, "below ordinary app windows")
      check(window.collectionBehavior.contains(.canJoinAllSpaces), "wallpaper joins desktop spaces")
      check(!window.canHide, "hiding Afterglow preserves wallpaper")
      check(
        NSScreen.screens.contains { $0.frame == window.frame },
        "wallpaper fits one complete display")
      NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
      check(
        NSScreen.screens.contains { $0.frame == window.frame },
        "screen change keeps wallpaper fitted")
      mode.restore()
      check(!mode.isEnabled, "returns to window mode")
      check(!window.ignoresMouseEvents, "window controls accept clicks again")
      check(window.styleMask == originalStyle, "original window style restored")
      check(window.collectionBehavior == originalBehavior, "original space behavior restored")
      check(window.level == originalLevel, "ordinary window layer restored")
      check(window.minSize == originalMinimum, "minimum size restored")
      check(window.frame == originalFrame, "original window geometry restored")
    }
    mode.toggle()
    window.close()
    check(!mode.isEnabled, "closing clears desktop state")
    check(mode.window == nil, "closed window is detached")
    check(window.styleMask == originalStyle, "closed window retains regular style for reopening")
    print("ALL \(count) DESKTOP CHECKS PASSED")
  }
}

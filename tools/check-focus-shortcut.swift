import AppKit
import Carbon

@main struct FocusShortcutChecks {
  @MainActor static func main() {
    _ = NSApplication.shared
    let defaults = UserDefaults.standard
    let keys = ["afterglow.globalFocusShortcut", "afterglow.globalDesktopShortcut", "afterglow.globalBeatShortcut"]
    let prior = keys.map { defaults.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, prior) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
      }
    }
    var count = 0
    func check(_ value: Bool, _ name: String) {
      precondition(value, name)
      count += 1
      print("PASS \(name)")
    }
    var first: FocusShortcut? = FocusShortcut()
    first!.configure {}
    first!.setEnabled(true)
    check(first!.isRegistered, "global shortcut registers with macOS")
    first!.configure {}
    check(first!.isRegistered, "repeated view appearances preserve one registration")
    let second = FocusShortcut()
    second.configure {}
    second.setEnabled(true)
    check(!second.isRegistered, "exclusive registration detects shortcut conflict")
    check(second.status.contains("unavailable"), "conflict has a visible recovery message")
    first!.setEnabled(false)
    check(!first!.isRegistered, "disabling releases the global shortcut")
    second.setEnabled(true)
    check(second.isRegistered, "retry succeeds after conflict is released")
    second.setEnabled(false)
    first!.setEnabled(true)
    check(first!.isRegistered, "shortcut can be enabled again")
    first = nil
    second.setEnabled(true)
    check(second.isRegistered, "deinitialization releases registration and event handler")
    second.setEnabled(false)
    var fired = [0, 0, 0]
    let focus = FocusShortcut(), desktop = FocusShortcut.desktop(), beat = FocusShortcut.beatSync()
    let shortcuts = [focus, desktop, beat]
    for (index, shortcut) in shortcuts.enumerated() {
      shortcut.configure { fired[index] += 1 }
      shortcut.setEnabled(true)
      check(shortcut.isRegistered, "independent shortcut \(index) registers")
    }
    for identifier in UInt32(1)...3 {
      var event: EventRef?
      check(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                        0, EventAttributes(0), &event) == noErr, "create shortcut event")
      if let event {
        var hotKey = EventHotKeyID(signature: 0x4146_474C, id: identifier)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size, &hotKey)
        check(SendEventToEventTarget(event, GetEventDispatcherTarget()) == noErr, "dispatch shortcut \(identifier)")
        ReleaseEvent(event)
      }
    }
    check(fired == [1, 1, 1], "each shortcut dispatches only its own action")
    desktop.setEnabled(false)
    check(focus.isRegistered && beat.isRegistered && !desktop.isRegistered,
          "disabling desktop leaves Focus and Beat Sync registered")
    shortcuts.forEach { $0.setEnabled(false) }
    print("ALL \(count) GLOBAL SHORTCUT CHECKS PASSED")
  }
}

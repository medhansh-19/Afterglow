import AppKit
import Carbon

@main struct FocusShortcutChecks {
  @MainActor static func main() {
    _ = NSApplication.shared
    let defaults = UserDefaults.standard
    let prior = defaults.object(forKey: "afterglow.globalFocusShortcut")
    defer {
      if let prior {
        defaults.set(prior, forKey: "afterglow.globalFocusShortcut")
      } else {
        defaults.removeObject(forKey: "afterglow.globalFocusShortcut")
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
    print("ALL \(count) GLOBAL SHORTCUT CHECKS PASSED")
  }
}

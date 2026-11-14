import Foundation

/// Old releases enabled estimated highlighting automatically. Make accuracy the default once,
/// then preserve the listener's choice if they explicitly enable estimates again.
public enum WordTimingPreferences {
    public static func prepare(_ defaults: UserDefaults) {
        let marker = "afterglow.suppliedWordTimingDefaultApplied"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(false, forKey: "afterglow.estimatedWords")
        defaults.set(true, forKey: marker)
    }
}

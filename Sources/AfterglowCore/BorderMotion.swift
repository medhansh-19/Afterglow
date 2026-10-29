import Foundation

/// A restrained track light: slower than the lyric animation and independent of song seeks.
public struct BorderMotion: Sendable {
    public private(set) var progress = 0.0
    public private(set) var glow = 0.0
    private var previous: Double?
    public init() {}
    public mutating func advance(at time: Double, energy: Double, pulse: Double, playing: Bool, reducedMotion: Bool) {
        guard time.isFinite else { return }
        let dt = min(0.1, max(0, time - (previous ?? time)))
        previous = time
        guard playing, !reducedMotion else { return }
        let level = energy.isFinite ? min(1, max(0, energy)) : 0
        let onset = pulse.isFinite ? min(1, max(0, pulse)) : 0
        let target = min(1, level * 0.65 + onset * 0.35)
        glow += (target - glow) * (1 - exp(-dt / (target > glow ? 0.09 : 0.32)))
        progress = (progress + dt * (1.0 / 42 + glow / 180)).truncatingRemainder(dividingBy: 1)
    }
}

import Foundation

/// Display-clock smoothing; never changes the music or lyric clock.
public struct WaveDynamics: Sendable {
    public private(set) var bands = Array(repeating: 0.0, count: 32)
    public private(set) var peaks = Array(repeating: 0.0, count: 32)
    public private(set) var pulse = 0.0
    public private(set) var phase = 0.0
    public private(set) var energy = 0.0
    private var previous: Double?
    public init() {}
    public mutating func advance(at time: Double, frame: BeatFrame, live: Bool, playing: Bool, reducedMotion: Bool) {
        guard time.isFinite else { return }
        let dt = min(0.1, max(0, time - (previous ?? time)))
        previous = time
        guard playing, !reducedMotion else { return }
        let age = max(0, time - frame.timestamp)
        let fresh = live && age < 0.3
        let level = fresh && frame.level.isFinite ? min(1, max(0, frame.level)) : 0
        energy += (level - energy) * (1 - exp(-dt / 0.10))
        let onset = fresh && frame.pulse.isFinite ? min(1, max(0, frame.pulse)) : 0
        pulse += (onset - pulse) * (1 - exp(-dt / (onset > pulse ? 0.018 : 0.14)))
        // Ambient mode is deliberately animated, never described as beat synchronized.
        // Never wrap this phase: the layered waves use non-integer harmonics.
        // Wrapping at 2π would jump their geometry even though the base sine is periodic.
        phase += dt * (live ? 1 + energy * 2.4 + pulse * 0.6 : 1.65)
        for i in bands.indices {
            let raw = fresh && i < frame.bars.count ? frame.bars[i] : 0
            let target = raw.isFinite ? min(1, max(0, raw)) : 0
            let constant = target > bands[i] ? 0.07 : 0.19
            bands[i] += (target - bands[i]) * (1 - exp(-dt / constant))
            peaks[i] = max(bands[i], peaks[i] - dt * 0.7)
        }
    }
}

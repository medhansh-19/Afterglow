import Foundation

/// A monotonic host clock interpolates playback, independent of wall-clock corrections.
public struct PlaybackClock: Sendable {
    private var anchorPosition = 0.0
    private var anchorUptime = 0.0
    private var playing = false
    private var initialized = false
    private var lastSampledAt = -Double.infinity

    public init() {}

    public func position(at uptime: Double) -> Double {
        max(0, anchorPosition + (playing ? max(0, uptime - anchorUptime) : 0))
    }

    public mutating func sample(position: Double, playing: Bool, sampledAt: Double, receivedAt: Double, force: Bool = false) {
        guard position.isFinite, sampledAt.isFinite, receivedAt.isFinite else { return }
        guard force || sampledAt >= lastSampledAt else { return }
        lastSampledAt = sampledAt
        let receivedPosition = max(0, position) + (playing ? max(0, receivedAt - sampledAt) : 0)
        let predicted = self.position(at: receivedAt)
        let drift = receivedPosition - predicted
        if initialized && self.playing && playing && !force && abs(drift) <= 0.3 {
            // Correct small sampling jitter gradually; a seek or transport change snaps immediately.
            anchorPosition = max(0, predicted + drift * 0.2)
        } else {
            anchorPosition = receivedPosition
        }
        anchorUptime = receivedAt
        self.playing = playing
        initialized = true
    }
}

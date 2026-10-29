import Foundation

public struct BeatFrame: Sendable {
    public let level: Double
    public let pulse: Double
    public let beatCount: Int
    public let bars: [Double]
    public let timestamp: Double
    public init(level: Double, pulse: Double, beatCount: Int, bars: [Double], timestamp: Double) {
        self.level = level; self.pulse = pulse; self.beatCount = beatCount; self.bars = bars; self.timestamp = timestamp
    }
    public static let silent = BeatFrame(level: 0, pulse: 0, beatCount: 0, bars: Array(repeating: 0, count: 32), timestamp: 0)
}

/// A local energy/onset detector, not a claim of perfect musical beat tracking.
public struct BeatAnalyzer {
    private var low = 0.0, average = 0.005, envelope = 0.0, pulse = 0.0
    private var lastBeat = -100.0, lastTime = 0.0
    private var count = 0
    private var spectrum = SpectrumAnalyzer()
    public init() {}

    public mutating func process(samples: [Float], sampleRate: Double, at time: Double) -> BeatFrame {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 0, time.isFinite else { return .silent }
        var energy = 0.0, bass = 0.0
        let coefficient = min(1, 2 * Double.pi * 180 / sampleRate)
        for value in samples {
            let x = value.isFinite ? min(1, max(-1, Double(value))) : 0
            low += coefficient * (x - low)
            energy += x * x; bass += low * low
        }
        let rms = sqrt(energy / Double(samples.count))
        let bassRMS = sqrt(bass / Double(samples.count))
        let dt = lastTime == 0 ? Double(samples.count) / sampleRate : max(0.001, min(1, time - lastTime))
        let novelty = max(rms * 0.7, bassRMS)
        let onset = novelty > max(0.009, average * 1.55) && time - lastBeat >= 0.22
        average += (novelty - average) * (1 - exp(-dt / 0.45))
        if onset { count += 1; lastBeat = time }
        pulse = onset ? 1 : pulse * exp(-dt / 0.19)
        let target = min(1, sqrt(rms) * 1.8)
        envelope += (target - envelope) * (1 - exp(-dt / (target > envelope ? 0.025 : 0.22)))
        let bars = spectrum.process(samples, sampleRate: sampleRate)
        lastTime = time
        return BeatFrame(level: envelope, pulse: pulse, beatCount: count, bars: bars, timestamp: time)
    }
}

import Foundation
import Accelerate

/// Hann-windowed 2048-sample FFT. Log bands represent frequency, not slices of a waveform.
private final class FFTPlan {
    let setup = vDSP_DFT_zop_CreateSetup(nil, 2048, .FORWARD)
    deinit { if let setup { vDSP_DFT_DestroySetup(setup) } }
}

struct SpectrumAnalyzer {
    private let size = 2048
    private let plan = FFTPlan()
    private var pending: [Float] = []
    private var rate = 0.0
    private var latest = Array(repeating: 0.0, count: 32)
    mutating func process(_ samples: [Float], sampleRate: Double) -> [Double] {
        guard let setup = plan.setup, sampleRate.isFinite, sampleRate > 0 else { return latest }
        if rate != sampleRate { pending.removeAll(keepingCapacity: true); rate = sampleRate; latest = Array(repeating: 0, count: 32) }
        pending.append(contentsOf: samples.map { $0.isFinite ? min(1, max(-1, $0)) : 0 })
        guard pending.count >= size else { return latest }
        // Analyze the newest complete window; never queue old visual frames behind live playback.
        let window = Array(pending.suffix(size))
        pending = Array(pending.suffix(size / 2))
        let real = window.enumerated().map { i, x in x * Float(0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(size - 1))) }
        let imaginary = Array(repeating: Float(0), count: size)
        var outputReal = imaginary, outputImaginary = imaginary
        vDSP_DFT_Execute(setup, real, imaginary, &outputReal, &outputImaginary)
        let highest = min(16000, sampleRate * 0.48)
        guard highest > 40 else { return Array(repeating: 0, count: 32) }
        for band in 0..<32 {
            let low = 40 * pow(highest / 40, Double(band) / 32)
            let high = 40 * pow(highest / 40, Double(band + 1) / 32)
            let start = max(1, min(size / 2 - 1, Int(low * Double(size) / sampleRate)))
            let end = max(start + 1, min(size / 2, Int(ceil(high * Double(size) / sampleRate))))
            var magnitude = 0.0
            for bin in start..<end {
                magnitude = max(magnitude, hypot(Double(outputReal[bin]), Double(outputImaginary[bin])) * 4 / Double(size))
            }
            // Fixed -65 to -5 dB display range; no gain pump that invents energy during silence.
            latest[band] = min(1, max(0, (20 * log10(max(0.0000001, magnitude)) + 65) / 60))
        }
        return latest
    }
}

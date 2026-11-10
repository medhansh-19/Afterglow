import Foundation
#if canImport(Accelerate)
import Accelerate

/// Hann-windowed 2048-sample FFT. Log bands represent frequency, not slices of a waveform.
private final class FFTPlan {
    let setup = vDSP_DFT_zop_CreateSetup(nil, 2048, .FORWARD)
    deinit { if let setup { vDSP_DFT_DestroySetup(setup) } }
}

#endif

struct SpectrumAnalyzer {
    private let size = 2048
    private static let window: [Float] = (0..<2048).map {
        Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / 2047))
    }
    #if canImport(Accelerate)
    private let plan = FFTPlan()
    #endif
    private var pending: [Float] = []
    private var rate = 0.0
    private var latest = Array(repeating: 0.0, count: 32)
    private var real = Array(repeating: Float(0), count: 2048)
    private let imaginary = Array(repeating: Float(0), count: 2048)
    private var outputReal = Array(repeating: Float(0), count: 2048)
    private var outputImaginary = Array(repeating: Float(0), count: 2048)
    private var bins: [Range<Int>] = []
    mutating func process(_ samples: [Float], sampleRate: Double) -> [Double] {
        guard sampleRate.isFinite, sampleRate > 0 else { return latest }
        #if canImport(Accelerate)
        guard let setup = plan.setup else { return latest }
        #endif
        if rate != sampleRate {
            pending.removeAll(keepingCapacity: true)
            rate = sampleRate
            latest = Array(repeating: 0, count: 32)
            let highest = min(16000, sampleRate * 0.48)
            bins = highest > 40 ? (0..<32).map { band in
                let low = 40 * pow(highest / 40, Double(band) / 32)
                let high = 40 * pow(highest / 40, Double(band + 1) / 32)
                let start = max(1, min(size / 2 - 1, Int(low * Double(size) / sampleRate)))
                let end = max(start + 1, min(size / 2, Int(ceil(high * Double(size) / sampleRate))))
                return start..<end
            } : []
        }
        pending.reserveCapacity(pending.count + samples.count)
        for sample in samples { pending.append(sample.isFinite ? min(1, max(-1, sample)) : 0) }
        guard pending.count >= size else { return latest }
        // Analyze the newest complete window; never queue old visual frames behind live playback.
        let start = pending.count - size
        for index in 0..<size { real[index] = pending[start + index] * Self.window[index] }
        pending.removeFirst(pending.count - size / 2)
        #if canImport(Accelerate)
        vDSP_DFT_Execute(setup, real, imaginary, &outputReal, &outputImaginary)
        #else
        (outputReal, outputImaginary) = PortableFFT.forward(real)
        #endif
        guard !bins.isEmpty else { return latest }
        for band in 0..<32 {
            var magnitude = 0.0
            for bin in bins[band] {
                magnitude = max(magnitude, hypot(Double(outputReal[bin]), Double(outputImaginary[bin])) * 4 / Double(size))
            }
            // Fixed -65 to -5 dB display range; no gain pump that invents energy during silence.
            latest[band] = min(1, max(0, (20 * log10(max(0.0000001, magnitude)) + 65) / 60))
        }
        return latest
    }
}

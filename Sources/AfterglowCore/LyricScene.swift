import Foundation

/// Deterministic from the media clock: seeks and backward scrubs never retain an old scene.
public struct LyricScene: Sendable {
    public let lineIndex: Int?
    public let waveOpacity: Double
    public static func isVocal(_ line: LyricLine) -> Bool {
        let value = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return false }
        if value.allSatisfy({ "♪♫♬♩♭♮♯….- ".contains($0) }) { return false }
        return !["[instrumental]", "(instrumental)", "[music]", "(music)", "[interlude]", "(interlude)"].contains(value.lowercased())
    }

    /// Some providers set a lyric's end to the next timestamp across a multi-minute break.
    /// Limit only sparse, line-only holds over 30 seconds; real word timestamps remain authoritative.
    public static func displayEnd(for index: Int, lines: [LyricLine], duration: Double) -> Double {
        let line = lines[index]
        let next = index + 1 < lines.count ? lines[index + 1].time : duration
        let end = min(next, line.end ?? next)
        guard isVocal(line), line.words.isEmpty, end - line.time > 30 else { return end }
        let count = line.text.split(whereSeparator: \.isWhitespace).count
        return min(end, line.time + min(16, max(8, Double(count) * 0.8)))
    }

    public static func resolve(lines: [LyricLine], at position: Double, duration: Double) -> LyricScene {
        guard position.isFinite, duration.isFinite, duration > 0, position >= 0, position < duration else {
            return .init(lineIndex: nil, waveOpacity: 0)
        }
        let index = Lyrics.index(at: position, in: lines)
        if let index, isVocal(lines[index]), position < displayEnd(for: index, lines: lines, duration: duration) {
            return .init(lineIndex: index, waveOpacity: 0)
        }
        let next = lines.indices.first { lines[$0].time > position && isVocal(lines[$0]) }
        let stop = min(duration, next.map { lines[$0].time } ?? duration)
        var start = index.map { isVocal(lines[$0]) ? displayEnd(for: $0, lines: lines, duration: duration) : lines[$0].time } ?? 0
        var previous: Int?
        if let index {
            for i in stride(from: index, through: 0, by: -1) {
                if isVocal(lines[i]) {
                    previous = i
                    if i == index { start = displayEnd(for: i, lines: lines, duration: duration) }
                    else { start = min(start, displayEnd(for: i, lines: lines, duration: duration)) }
                    break
                }
                start = min(start, lines[i].time)
            }
        }
        // Breaths/rounding gaps are not instrumental scenes. Keep the prior text, no active word.
        if stop - start < 0.7 { return .init(lineIndex: previous, waveOpacity: 0) }
        func smooth(_ value: Double) -> Double {
            let x = min(1, max(0, value))
            return x * x * (3 - 2 * x)
        }
        let opacity = min(smooth((position - start) / 0.18), smooth((stop - position) / 0.18))
        return .init(lineIndex: nil, waveOpacity: opacity)
    }
}

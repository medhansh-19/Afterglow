import Foundation

public struct LyricLine: Equatable, Codable, Sendable, Identifiable {
    public let time: Double
    public let text: String
    public let end: Double?
    public let words: [LyricWord]
    public var id: Double { time }
    public init(time: Double, text: String, end: Double? = nil, words: [LyricWord] = []) {
        self.time = time; self.text = text; self.end = end; self.words = words
    }
}

public struct LyricWord: Equatable, Codable, Sendable {
    public let text: String
    public let time: Double
    public let end: Double?
    public init(text: String, time: Double, end: Double? = nil) {
        self.text = text; self.time = time; self.end = end
    }
}

public enum Lyrics {
    /// LRC timestamps, including repeated tags and the standard millisecond offset.
    public static func parse(_ source: String) -> [LyricLine] {
        let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]"#)
        let offsetTag = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        let ns = source as NSString
        var offset = 0.0
        if let match = offsetTag.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) {
            offset = (Double(ns.substring(with: match.range(at: 1))) ?? 0) / 1000
        }
        var lines: [LyricLine] = []
        for row in source.components(separatedBy: .newlines) {
            let value = row as NSString
            let matches = tag.matches(in: row, range: NSRange(location: 0, length: value.length))
            guard let last = matches.last else { continue }
            let text = value.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minute = Double(value.substring(with: match.range(at: 1))) ?? 0
                let second = Double(value.substring(with: match.range(at: 2))) ?? 0
                guard second < 60, minute.isFinite, minute < 1440 else { continue }
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = value.substring(with: match.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                // Positive LRC offset advances lyrics relative to the audio clock.
                lines.append(.init(time: max(0, minute * 60 + second + fraction - offset), text: text))
            }
        }
        // One deterministic entry per timestamp also keeps SwiftUI identities unique.
        var unique: [Double: LyricLine] = [:]
        for line in lines { unique[line.time] = line }
        return unique.values.sorted { $0.time < $1.time }
    }

    public static func index(at time: Double, in lines: [LyricLine]) -> Int? {
        guard let first = lines.first, time >= first.time else { return nil }
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low - 1
    }

    /// Word timing is an interpolation within an LRC line, never advertised as exact.
    public static func wordIndex(progress: Double, words: [String]) -> Int {
        guard !words.isEmpty else { return 0 }
        let weights = words.map { Double(max(2, $0.count)) }
        let target = min(max(progress, 0), 0.999999) * weights.reduce(0, +)
        var sum = 0.0
        for (i, weight) in weights.enumerated() {
            sum += weight
            if target < sum { return i }
        }
        return words.count - 1
    }
}

public struct Track: Hashable, Codable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public init(title: String, artist: String, album: String, duration: Double) {
        self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}

public enum Demo {
    /// Synthetic timestamps for the original, silent demonstration; never used for a real song.
    public static var wordTimedLines: [LyricLine] {
        lines.map { line in
            let tokens = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
            let step = 5.0 / Double(tokens.count)
            return .init(time: line.time, text: line.text, end: line.time + 5,
                         words: tokens.enumerated().map { i, text in
                             .init(text: text, time: line.time + Double(i) * step, end: line.time + Double(i + 1) * step)
                         })
        }
    }
    public static let track = Track(title: "A little after midnight", artist: "Afterglow · original demo", album: "", duration: 48)
    public static let lines: [LyricLine] = [
        .init(time: 0, text: "Let the city fall asleep"),
        .init(time: 6, text: "Leave a little light for me"),
        .init(time: 12, text: "Every word becomes a star"),
        .init(time: 18, text: "Drawing lines to where you are"),
        .init(time: 24, text: "We are echoes in the blue"),
        .init(time: 30, text: "All the light comes back to you"),
        .init(time: 36, text: "Let the silence find its glow"),
        .init(time: 42, text: "Stay a while before you go"),
    ]
}

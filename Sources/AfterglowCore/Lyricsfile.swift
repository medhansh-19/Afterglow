import Foundation
import Yams

/// Typed YAML decoding; never evaluates tags, scripts, or external resources.
public enum Lyricsfile {
    private struct Document: Decodable { let lines: [Line]? }
    private struct Line: Decodable {
        let text: String
        let start_ms: Double?
        let end_ms: Double?
        let words: [Word]?
    }
    private struct Word: Decodable {
        let text: String
        let start_ms: Double
        let end_ms: Double?
    }

    public static func parse(_ yaml: String) -> [LyricLine] {
        guard yaml.utf8.count <= 500_000,
              let document = try? YAMLDecoder().decode(Document.self, from: yaml),
              let source = document.lines, source.count <= 5000 else { return [] }
        var output: [Double: LyricLine] = [:]
        for line in source {
            guard let start = line.start_ms, valid(start), line.text.count < 10000 else { continue }
            let end = line.end_ms.flatMap { valid($0) && $0 >= start ? $0 / 1000 : nil }
            let original = line.words ?? []
            var words: [LyricWord] = []
            var last = start
            var wellFormed = original.count <= 500
            for word in original.prefix(500) {
                guard valid(word.start_ms), word.start_ms >= last,
                      word.start_ms >= start,
                      end == nil || word.start_ms / 1000 <= end!,
                      !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      word.text.count < 1000 else { wellFormed = false; break }
                if let stop = word.end_ms, !valid(stop) || stop < word.start_ms || (end != nil && stop / 1000 > end!) {
                    wellFormed = false; break
                }
                words.append(.init(text: word.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   time: word.start_ms / 1000, end: word.end_ms.map { $0 / 1000 }))
                last = word.start_ms
            }
            // Mismatched word text must never light up against a different line.
            let joined = original.map(\.text)
            if normalize(joined.joined()) != normalize(line.text)
                && normalize(joined.joined(separator: " ")) != normalize(line.text) { wellFormed = false }
            output[start / 1000] = .init(time: start / 1000, text: line.text, end: end,
                                        words: wellFormed ? words : [])
        }
        return output.values.sorted { $0.time < $1.time }
    }

    private static func valid(_ time: Double) -> Bool { time.isFinite && time >= 0 && time <= 86_400_000 }
    private static func normalize(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}

public enum LyricTiming {
    /// nil means highlight the entire line or an actual gap between timed words.
    public static func activeWord(in line: LyricLine, at time: Double, estimated: Bool, nextLineTime: Double) -> Int? {
        guard time >= line.time, line.end == nil || time < line.end! else { return nil }
        if !line.words.isEmpty {
            guard let index = line.words.lastIndex(where: { $0.time <= time }) else { return nil }
            if let end = line.words[index].end, time >= end { return nil }
            return index
        }
        guard estimated else { return nil }
        let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        return Lyrics.wordIndex(progress: (time - line.time) / max(0.1, min(nextLineTime, line.end ?? nextLineTime) - line.time), words: words)
    }
}

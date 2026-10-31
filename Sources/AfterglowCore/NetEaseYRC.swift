import Foundation

/// NetEase's supplied word timings are absolute milliseconds, not offsets within the line.
public enum NetEaseYRC {
    public static func parse(_ source: String) -> [LyricLine] {
        guard source.utf8.count <= 500_000 else { return [] }
        let header = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
        let token = try! NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)"#)
        var result: [Double: LyricLine] = [:]
        for row in source.components(separatedBy: .newlines) {
            let text = row as NSString
            guard let line = header.firstMatch(in: row, range: NSRange(location: 0, length: text.length)),
                let start = Double(text.substring(with: line.range(at: 1))).map({ $0 / 1000 }),
                let duration = Double(text.substring(with: line.range(at: 2))).map({ $0 / 1000 }),
                start.isFinite, duration.isFinite, start >= 0, duration > 0, start + duration <= 86400 else { continue }
            let matches = token.matches(in: row, range: NSRange(location: NSMaxRange(line.range), length: text.length - NSMaxRange(line.range)))
            guard !matches.isEmpty, matches.count <= 500,
                matches.first?.range.location == NSMaxRange(line.range) else { continue }
            var words: [LyricWord] = []
            var fragments: [String] = []
            var valid = true
            for (index, match) in matches.enumerated() {
                let startMS = Double(text.substring(with: match.range(at: 1))) ?? -1
                let durationMS = Double(text.substring(with: match.range(at: 2))) ?? -1
                let time = startMS / 1000
                let length = durationMS / 1000
                let wordEnd = (startMS + durationMS) / 1000
                let end = index + 1 < matches.count ? matches[index + 1].range.location : text.length
                let raw = text.substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
                let value = raw.trimmingCharacters(in: .whitespaces)
                guard time.isFinite, length.isFinite, time >= start, length >= 0,
                    wordEnd <= start + duration + 0.001,
                    time + 0.001 >= (words.last?.end ?? start), !value.isEmpty else { valid = false; break }
                fragments.append(raw)
                words.append(.init(text: value, time: time, end: wordEnd))
            }
            guard valid, !words.isEmpty else { continue }
            result[start] = .init(time: start, text: fragments.joined().trimmingCharacters(in: .whitespaces),
                end: start + duration, words: words)
        }
        return result.values.sorted { $0.time < $1.time }
    }
}

/// Role-labelled catalogue credits are metadata, never lyric graph nodes.
public enum LyricCredits {
    public static func isCredit(_ text: String) -> Bool {
        text.range(of: #"(?i)^\s*(?:作词|作詞|作曲|词曲|詞曲|编曲|編曲|制作人|製作人|制作|製作|监制|監製|录音|錄音|混音|母带|母帶|和声|和聲|演唱|出品|发行|發行|策划|企划|统筹|작사|작곡|편곡|composer|composed\s+by|lyricist|lyrics?\s+by|written\s+by|words?\s+by|songwriter|producer|produced\s+by|arranger|arranged\s+by|mix(?:ed|ing)?(?:\s+by)?|master(?:ed|ing)?(?:\s+by)?|record(?:ed|ing)?(?:\s+by)?)\s*[:：]"#,
            options: .regularExpression) != nil
    }
    public static func clean(_ lines: [LyricLine]) -> [LyricLine] {
        lines.map { isCredit($0.text) ? .init(time: $0.time, text: "", end: $0.end) : $0 }
    }
}

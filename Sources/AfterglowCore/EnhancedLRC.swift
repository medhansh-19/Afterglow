import Foundation

/// Karalyr's Enhanced LRC: retain supplied word timestamps, never estimate them.
public enum EnhancedLRC {
    public static func parse(_ source: String) -> [LyricLine] {
        guard source.utf8.count <= 500_000 else { return [] }
        let tags = try! NSRegularExpression(pattern: #"<(\d+):(\d{2})(?:\.(\d{1,3}))?>"#)
        let offsetTag = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
        let ns = source as NSString
        let offset = offsetTag.firstMatch(in: source, range: NSRange(location: 0, length: ns.length))
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        guard offset.isFinite, abs(offset) <= 86400 else { return [] }
        var output: [Double: LyricLine] = [:]
        for row in source.components(separatedBy: .newlines) {
            let text = row as NSString
            let range = NSRange(location: 0, length: text.length)
            let matches = tags.matches(in: row, range: range)
            let clean = tags.stringByReplacingMatches(in: row, range: range, withTemplate: "")
            let lines = Lyrics.parse("[offset:\(Int(offset * 1000))]\n" + clean)
            for line in lines {
                var words: [LyricWord] = []
                var valid = lines.count == 1 && matches.count <= 500 && !matches.isEmpty
                for (index, match) in matches.prefix(500).enumerated() {
                    let minutes = Double(text.substring(with: match.range(at: 1))) ?? 0
                    let seconds = Double(text.substring(with: match.range(at: 2))) ?? 0
                    let digits = match.range(at: 3).location == NSNotFound ? "" : text.substring(with: match.range(at: 3))
                    let time = minutes * 60 + seconds + (Double(digits) ?? 0) / pow(10, Double(digits.count)) - offset
                    let start = NSMaxRange(match.range)
                    let end = index + 1 < matches.count ? matches[index + 1].range.location : text.length
                    let token = text.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
                    // A trailing timestamp can mark the previous word's end.
                    if token.isEmpty && index == matches.count - 1 {
                        if let previous = words.popLast(), time >= previous.time, seconds < 60, time < 86400 {
                            words.append(.init(text: previous.text, time: previous.time, end: time))
                        } else { valid = false }
                        continue
                    }
                    guard seconds < 60, time >= line.time, time < 86400,
                          time >= (words.last?.time ?? line.time), !token.isEmpty,
                          !token.contains("<"), !token.contains(">") else { valid = false; break }
                    if let previous = words.popLast() {
                        words.append(.init(text: previous.text, time: previous.time, end: time))
                    }
                    words.append(.init(text: token, time: time))
                }
                func normalize(_ value: String) -> String { value.filter { !$0.isWhitespace } }
                valid = valid && normalize(words.map(\.text).joined()) == normalize(line.text)
                guard !line.text.contains("<"), !line.text.contains(">") else { continue }
                output[line.time] = .init(time: line.time, text: line.text, words: valid ? words : [])
            }
        }
        let lines = output.values.sorted { $0.time < $1.time }
        return lines.enumerated().map { index, line in
            let end = index + 1 < lines.count ? lines[index + 1].time : 86400
            let valid = line.words.allSatisfy { $0.time <= end && ($0.end ?? $0.time) <= end }
            return .init(time: line.time, text: line.text, words: valid ? line.words : [])
        }
    }
}

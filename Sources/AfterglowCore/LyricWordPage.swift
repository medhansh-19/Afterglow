import Foundation

/// A bounded constellation that follows the media clock without dropping any words.
public struct LyricWordPage: Equatable, Sendable {
    public let words: [String]
    public let range: Range<Int>
    public let activeIndex: Int?

    public static func resolve(line: LyricLine, at position: Double, nextLineTime: Double,
                               estimated: Bool, pageSize: Int = 24) -> LyricWordPage {
        let raw = line.words.isEmpty
            ? line.text.split(whereSeparator: \.isWhitespace).map(String.init)
            : line.words.map(\.text)
        let brackets = CharacterSet(charactersIn: "()[]{}（）【】「」『』《》")
        let visible = raw.enumerated().compactMap { index, token -> (index: Int, text: String)? in
            let text = token.trimmingCharacters(in: brackets)
            guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return (index, text)
        }
        let tokens = visible.map(\.text)
        guard !tokens.isEmpty else { return .init(words: [], range: 0..<0, activeIndex: nil) }
        let capacity = max(1, pageSize)
        let end = min(nextLineTime, line.end ?? nextLineTime)
        let vocal = position >= line.time && position < end
        // Timed words retain their original indices/timestamps; line-only estimates
        // use only visible words so bracket tokens consume no karaoke interval.
        let timingLine = line.words.isEmpty
            ? LyricLine(time: line.time, text: tokens.joined(separator: " "), end: line.end) : line
        let rawActive = vocal ? LyricTiming.activeWord(in: timingLine, at: position,
            estimated: estimated, nextLineTime: nextLineTime) : nil
        let active = line.words.isEmpty ? rawActive : rawActive.flatMap { original in
            visible.firstIndex { $0.index == original }
        }
        let anchor: Int
        if let active {
            anchor = active
        } else if !line.words.isEmpty {
            // Between timestamped words, keep the most recently reached page.
            let original = line.words.lastIndex { $0.time <= position } ?? 0
            anchor = visible.lastIndex { $0.index <= original } ?? 0
        } else {
            // Line-only sources need approximate page turns even with word emphasis off.
            // This never adds estimated word highlighting or changes provider timestamps.
            anchor = LyricTiming.activeWord(in: timingLine, at: position,
                estimated: true, nextLineTime: nextLineTime)
                ?? (position >= end ? tokens.count - 1 : 0)
        }
        let start = (min(tokens.count - 1, max(0, anchor)) / capacity) * capacity
        let range = start..<min(tokens.count, start + capacity)
        return .init(words: Array(tokens[range]), range: range,
                     activeIndex: active.flatMap { range.contains($0) ? $0 - start : nil })
    }
}

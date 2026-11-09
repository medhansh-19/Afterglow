import Foundation

/// A bounded constellation that follows the media clock without dropping any words.
public struct LyricWordPage: Equatable, Sendable {
    public let words: [String]
    public let range: Range<Int>
    public let activeIndex: Int?

    /// Providers sometimes omit whitespace between sentences ("word.Next").
    /// Keep punctuation with the preceding word, but never make it its own node.
    private static func pieces(_ source: String) -> [String] {
        let characters = Array(source)
        let boundaries: Set<Character> = [".", ";", "；", "。"]
        var result: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
                continue
            }
            current.append(character)
            guard boundaries.contains(character) else { continue }
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            // A decimal point is not a sentence boundary; ellipses stay together.
            if character == ".", previous?.isNumber == true, next?.isNumber == true { continue }
            if let next, boundaries.contains(next) { continue }
            result.append(current)
            current = ""
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Prepared once per displayed line, rather than tokenizing on every display tick.
    public struct Prepared: Sendable {
        private let line: LyricLine
        private let visible: [(index: Int, text: String)]
        private let tokens: [String]
        private let cumulativeWeights: [Double]
        private let groups: [Int: Range<Int>]

        public init(line: LyricLine) {
            self.line = line
            let raw = line.words.isEmpty
                ? line.text.split(whereSeparator: \.isWhitespace).map(String.init)
                : line.words.map(\.text)
            let brackets = CharacterSet(charactersIn: "()[]{}（）【】「」『』《》")
            visible = raw.enumerated().flatMap { index, token -> [(index: Int, text: String)] in
                LyricWordPage.pieces(token).compactMap { piece in
                    let text = piece.trimmingCharacters(in: brackets)
                    guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
                    return (index, text)
                }
            }
            tokens = visible.map(\.text)
            var weights = [0.0]
            for token in tokens { weights.append(weights.last! + Double(max(2, token.count))) }
            cumulativeWeights = weights
            var ranges: [Int: Range<Int>] = [:]
            for index in visible.indices {
                let original = visible[index].index
                ranges[original] = (ranges[original]?.lowerBound ?? index)..<(index + 1)
            }
            groups = ranges
        }

        private func weightedIndex(progress: Double, range: Range<Int>) -> Int {
            let base = cumulativeWeights[range.lowerBound]
            let total = cumulativeWeights[range.upperBound] - base
            let target = min(max(progress, 0), 0.999999) * total
            var low = range.lowerBound, high = range.upperBound
            while low < high {
                let mid = (low + high) / 2
                if cumulativeWeights[mid + 1] - base <= target { low = mid + 1 } else { high = mid }
            }
            return min(range.upperBound - 1, low)
        }

        private func estimatedIndex(at position: Double, end: Double) -> Int? {
            guard position >= line.time, line.end == nil || position < line.end! else { return nil }
            return weightedIndex(progress: (position - line.time) / max(0.1, end - line.time),
                range: tokens.indices)
        }

        public func resolve(at position: Double, nextLineTime: Double,
                            estimated: Bool, pageSize: Int = 24) -> LyricWordPage {
            guard !tokens.isEmpty else { return .init(words: [], range: 0..<0, activeIndex: nil) }
            let capacity = max(1, pageSize)
            let end = min(nextLineTime, line.end ?? nextLineTime)
            let vocal = position >= line.time && position < end
            let active: Int?
            if !vocal { active = nil }
            else if line.words.isEmpty { active = estimated ? estimatedIndex(at: position, end: end) : nil }
            else {
                active = LyricTiming.activeWord(in: line, at: position,
                    estimated: estimated, nextLineTime: nextLineTime).flatMap { original in
                    guard let matches = groups[original] else { return nil }
                    guard matches.count > 1, estimated else { return matches.lowerBound }
                    let start = line.words[original].time
                    let next = original + 1 < line.words.count ? line.words[original + 1].time : end
                    let stop = min(end, line.words[original].end ?? next)
                    return weightedIndex(progress: (position - start) / max(0.1, stop - start), range: matches)
                }
            }
            let anchor: Int
            if let active { anchor = active }
            else if !line.words.isEmpty {
                let original = line.words.lastIndex { $0.time <= position } ?? 0
                anchor = visible.lastIndex { $0.index <= original } ?? 0
            } else {
                anchor = estimatedIndex(at: position, end: end) ?? (position >= end ? tokens.count - 1 : 0)
            }
            let start = (min(tokens.count - 1, max(0, anchor)) / capacity) * capacity
            let range = start..<min(tokens.count, start + capacity)
            return .init(words: Array(tokens[range]), range: range,
                activeIndex: active.flatMap { range.contains($0) ? $0 - start : nil })
        }
    }

    public static func resolve(line: LyricLine, at position: Double, nextLineTime: Double,
                               estimated: Bool, pageSize: Int = 24) -> LyricWordPage {
        Prepared(line: line).resolve(at: position, nextLineTime: nextLineTime,
            estimated: estimated, pageSize: pageSize)
    }
}

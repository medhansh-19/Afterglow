import Foundation

/// Recognizes exact repeated passages after case, punctuation and whitespace normalization.
/// Analysis happens once per lyric document; rendering only looks up a canonical line index.
public struct ChorusMemory: Equatable, Sendable {
  public let canonicalLines: [Int]
  public let repeatedLineCount: Int

  public init(lines: [LyricLine]) {
    let keys = lines.map { line -> String in
      guard LyricScene.isVocal(line) else { return "" }
      return line.text.lowercased().unicodeScalars.map {
        CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
          ? String($0) : " "
      }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    var canonical = Array(lines.indices)
    var occurrences: [String: [Int]] = [:]
    for i in keys.indices where !keys[i].isEmpty {
      for first in occurrences[keys[i], default: []] {
        // Only begin at the start of a repeated run, avoiding quadratic run scans.
        if first > 0, i > 0, !keys[i - 1].isEmpty, keys[first - 1] == keys[i - 1] { continue }
        var length = 0
        var words = 0
        while first + length < i, i + length < keys.count,
          !keys[i + length].isEmpty, keys[first + length] == keys[i + length] {
          words += keys[i + length].split(separator: " ").count
          length += 1
        }
        // Short repeated filler ("oh", "yeah") is not sufficient evidence of a chorus.
        guard (length >= 2 && words >= 6) || (length == 1 && words >= 6) else { continue }
        for offset in 0..<length {
          canonical[i + offset] = min(canonical[i + offset], canonical[first + offset])
        }
      }
      occurrences[keys[i], default: []].append(i)
    }
    canonicalLines = canonical
    repeatedLineCount = canonical.indices.filter { canonical[$0] != $0 }.count
  }

  public func layoutSeed(for line: Int, pageStart: Int = 0) -> Int {
    let canonical = canonicalLines.indices.contains(line) ? canonicalLines[line] : line
    return max(0, canonical) &* 31 &+ max(0, pageStart)
  }
}

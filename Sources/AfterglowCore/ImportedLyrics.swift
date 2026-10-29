import Foundation

public enum ImportedLyrics {
    public static func parse(_ text: String, extension ext: String) -> LyricDocument? {
        guard text.utf8.count <= 500_000, !text.contains("\0") else { return nil }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        if ext.lowercased() == "txt" { return .init(plainText: content, source: .local) }
        if !["yaml", "yml"].contains(ext.lowercased()), content.range(of: #"<\d+:\d{2}(?:\.\d+)?>"#, options: .regularExpression) != nil { return nil }
        let lines = ["yaml", "yml"].contains(ext.lowercased()) ? Lyricsfile.parse(content) : Lyrics.parse(content)
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }
        return .init(lines: lines, plainText: lines.map(\.text).joined(separator: "\n"), source: .local)
    }
}

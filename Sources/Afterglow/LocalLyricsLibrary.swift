import Foundation
import CryptoKit
import AfterglowCore

enum LocalLyricsLibrary {
    private static func url(_ track: Track) throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true).appendingPathComponent("Afterglow/ImportedLyrics")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let identity = Data("\(track.title)|\(track.artist)|\(track.album)|\(Int(track.duration))".utf8)
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(key + ".json")
    }

    static func read(_ track: Track) -> LyricDocument? {
        guard let path = try? url(track), let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2_000_000, let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(LyricDocument.self, from: data)
    }
    static func save(_ document: LyricDocument, for track: Track) throws {
        try JSONEncoder().encode(document).write(to: url(track), options: .atomic)
    }
    static func useOnline(_ track: Track) throws {
        let path = try url(track)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        // Keep the previous import recoverable, rather than deleting the user's copy.
        let archive = path.deletingLastPathComponent().appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: path, to: archive.appendingPathComponent(UUID().uuidString + ".json"))
    }
}

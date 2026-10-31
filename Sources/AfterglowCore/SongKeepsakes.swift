import Foundation

/// Metadata identifies a recording without relying on a player-specific identifier.
public enum RecordingIdentity {
  public static func key(_ track: Track) -> String {
    // Length prefixes avoid collisions when metadata itself contains separators.
    [track.title, track.artist, track.album, String(Int(track.duration.isFinite ? max(0, track.duration) : 0))]
      .map { "\($0.utf8.count):\($0)" }.joined()
  }
}

public struct SongAppearance: Codable, Equatable, Sendable {
  public var tint: String
  public var opacity: Double
  public var marker: String
  public var emoji: String
  public var clock: Bool
  public var motion: Bool
  public var estimatedWords: Bool
  public var wallpaper: Data?
  public init(tint: String, opacity: Double, marker: String, emoji: String, clock: Bool,
              motion: Bool, estimatedWords: Bool, wallpaper: Data?) {
    self.tint = tint; self.opacity = min(1, max(0, opacity)); self.marker = marker
    self.emoji = String(emoji.prefix(1)); self.clock = clock; self.motion = motion
    self.estimatedWords = estimatedWords; self.wallpaper = wallpaper
  }
}

public struct SavedLyricExcerpt: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let track: Track
  public let text: String
  public let red: Double
  public let green: Double
  public let blue: Double
  public init(track: Track, text: String, color: GlowColor) {
    id = UUID(); self.track = track; self.text = text
    red = color.red; green = color.green; blue = color.blue
  }
  public static func text(from lines: [String], selected: Set<Int>) -> String? {
    let selectedLines = lines.indices.filter { selected.contains($0) }.map { lines[$0] }
    let text = selectedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, selectedLines.count <= 6, text.count <= 280 else { return nil }
    return text
  }
}

public struct SongKeepsakeStore: Sendable {
  public let folder: URL
  public init(folder: URL) { self.folder = folder }
  private func url(_ name: String) -> URL { folder.appendingPathComponent(name + ".json") }
  public func exists(name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }
  public func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
    guard let data = try? Data(contentsOf: url(name)) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
  public func write<T: Encodable>(_ value: T, name: String) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONEncoder().encode(value).write(to: url(name), options: .atomic)
  }
  public func remove(name: String) throws {
    let path = url(name)
    if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
  }
}

import Foundation

public struct SongCollection: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  /// nil inherits the song scene/default. Otherwise uses the existing Tint or RGB value.
  public var lyricColor: String?
  public var songs: [Track]
  public init(id: UUID = UUID(), name: String, lyricColor: String? = nil, songs: [Track] = []) {
    self.id = id; self.name = name; self.lyricColor = lyricColor; self.songs = songs
  }
  public func contains(_ track: Track) -> Bool {
    songs.contains { RecordingIdentity.key($0) == RecordingIdentity.key(track) }
  }
}

public struct SongCollectionLibrary: Codable, Equatable, Sendable {
  public var collections: [SongCollection]
  /// Explicit per-recording selection resolves overlapping memberships, including inheritance.
  public var colorSources: [String: UUID]
  public init(collections: [SongCollection] = [.init(name: "Liked"), .init(name: "Favorites")],
              colorSources: [String: UUID] = [:]) {
    self.collections = collections; self.colorSources = colorSources
  }
  public func colorCollection(for track: Track) -> SongCollection? {
    let memberships = collections.filter { $0.contains(track) }
    if let selected = colorSources[RecordingIdentity.key(track)],
       let collection = memberships.first(where: { $0.id == selected }) { return collection }
    return memberships.first { $0.lyricColor != nil }
  }
  public func color(for track: Track?) -> String? {
    track.flatMap { colorCollection(for: $0)?.lyricColor }
  }
  public mutating func setMembership(_ included: Bool, track: Track, collectionID: UUID) {
    guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
    if included {
      if !collections[index].contains(track) { collections[index].songs.append(track) }
    } else {
      collections[index].songs.removeAll { RecordingIdentity.key($0) == RecordingIdentity.key(track) }
      if colorSources[RecordingIdentity.key(track)] == collectionID {
        colorSources.removeValue(forKey: RecordingIdentity.key(track))
      }
    }
  }
  public mutating func removeCollection(_ id: UUID) {
    collections.removeAll { $0.id == id }
    colorSources = colorSources.filter { $0.value != id }
  }
  public func validName(_ value: String, excluding id: UUID? = nil) -> String? {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 40,
      !collections.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return nil }
    return name
  }
}

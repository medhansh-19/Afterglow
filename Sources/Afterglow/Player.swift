import AfterglowCore
import AppKit

enum PlayerSource: String, CaseIterable, Identifiable, Sendable {
  case spotify = "Spotify"
  case music = "Apple Music"
  var id: String { rawValue }
  var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

struct PlayerSnapshot: Sendable {
  let track: Track?
  let position: Double
  let playing: Bool
  let sampledAt: Double
}

enum TransportAction: Sendable {
  case previous, togglePlayPause, stop, next
}

enum PlayerError: LocalizedError {
  case denied, unavailable
  case failed(String)
  var errorDescription: String? {
    switch self {
    case .denied:
      "Allow Afterglow to read your player in System Settings → Privacy & Security → Automation, then reconnect."
    case .unavailable: "Open your music player and start a song, then reconnect."
    case .failed(let message): "Couldn’t read playback. \(message)"
    }
  }
}

/// Fixed AppleScript only; song titles and other external data never become executable code.
actor Player {
  static let shared = Player()
  private var compiled: [String: NSAppleScript] = [:]
  private var metadata: [PlayerSource: (identity: String, track: Track)] = [:]

  func artwork(_ source: PlayerSource) throws -> ArtworkReference? {
    try Task.checkCancellation()
    let script: String
    switch source {
    case .spotify:
      script =
        "with timeout of 3 seconds\ntell application id \"com.spotify.client\" to return artwork url of current track\nend timeout"
    case .music:
      script = """
        with timeout of 3 seconds
            tell application id "com.apple.Music"
                if (count of artworks of current track) is 0 then return ""
                return raw data of artwork 1 of current track
            end tell
        end timeout
        """
    }
    var error: NSDictionary?
    guard let command = NSAppleScript(source: script) else { return nil }
    let result = command.executeAndReturnError(&error)
    if error != nil { return nil }
    if source == .spotify {
      guard let value = result.stringValue, let url = URL(string: value), AlbumArtwork.allowed(url)
      else { return nil }
      return .remote(url)
    }
    let data = result.data
    return data.isEmpty ? nil : .embedded(data)
  }

  func control(_ action: TransportAction, source: PlayerSource) throws {
    try Task.checkCancellation()
    guard
      NSWorkspace.shared.runningApplications.contains(where: {
        $0.bundleIdentifier == source.bundleID
      })
    else {
      throw PlayerError.unavailable
    }
    // Commands and target identifiers come only from these fixed enums, never song metadata.
    let command: String
    switch action {
    case .previous: command = "previous track"
    case .next: command = "next track"
    case .togglePlayPause: command = "playpause"
    case .stop: command = source == .spotify ? "pause\nset player position to 0" : "stop"
    }
    let script =
      "with timeout of 3 seconds\ntell application id \"\(source.bundleID)\"\n\(command)\nend tell\nend timeout"
    var error: NSDictionary?
    guard let appleScript = NSAppleScript(source: script) else {
      throw PlayerError.failed("Playback command could not compile.")
    }
    _ = appleScript.executeAndReturnError(&error)
    if let error {
      if error[NSAppleScript.errorNumber] as? Int == -1743 { throw PlayerError.denied }
      throw PlayerError.failed(
        (error[NSAppleScript.errorBriefMessage] as? String) ?? "Try reconnecting.")
    }
  }

  func read(_ source: PlayerSource) throws -> PlayerSnapshot {
    try Task.checkCancellation()
    guard
      NSWorkspace.shared.runningApplications.contains(where: {
        $0.bundleIdentifier == source.bundleID
      })
    else {
      throw PlayerError.unavailable
    }
    // Stable identity + clock only; album/title/duration are fetched once per track change.
    let identity = source == .spotify ? "id" : "persistent ID"
    let script = """
      with timeout of 3 seconds
          tell application id "\(source.bundleID)"
              if player state is stopped then return {}
              return {\(identity) of current track, player position, (player state is playing)}
          end tell
      end timeout
      """
    let (result, sampledAt) = try execute(script, key: "clock." + source.rawValue)
    guard result.numberOfItems == 3 else {
      return .init(track: nil, position: 0, playing: false, sampledAt: sampledAt)
    }
    let trackID = result.atIndex(1)?.stringValue ?? ""
    let position = result.atIndex(2)?.doubleValue ?? 0
    guard position.isFinite else { throw PlayerError.failed("Invalid playback position.") }
    if let cached = metadata[source], !trackID.isEmpty, cached.identity == trackID {
      return .init(
        track: cached.track, position: min(86400, max(0, position)),
        playing: result.atIndex(3)?.booleanValue ?? false, sampledAt: sampledAt)
    }
    let duration = source == .spotify ? "(duration of t) / 1000" : "duration of t"
    let details = """
      with timeout of 3 seconds
          tell application id "\(source.bundleID)"
              if player state is stopped then return {}
              set t to current track
              return {\(identity) of t, name of t, artist of t, album of t, \(duration), player position, (player state is playing)}
          end tell
      end timeout
      """
    let (info, detailTime) = try execute(details, key: "track." + source.rawValue)
    guard info.numberOfItems == 7 else {
      return .init(track: nil, position: 0, playing: false, sampledAt: detailTime)
    }
    let newID = info.atIndex(1)?.stringValue ?? ""
    let title = info.atIndex(2)?.stringValue ?? ""
    let length = info.atIndex(5)?.doubleValue ?? 0
    let newPosition = info.atIndex(6)?.doubleValue ?? 0
    guard !title.isEmpty, length.isFinite, newPosition.isFinite else {
      throw PlayerError.failed("Invalid track metadata.")
    }
    let track = Track(
      title: title, artist: info.atIndex(3)?.stringValue ?? "",
      album: info.atIndex(4)?.stringValue ?? "", duration: min(86400, max(0, length)))
    metadata[source] = (newID, track)
    return .init(
      track: track, position: min(86400, max(0, newPosition)),
      playing: info.atIndex(7)?.booleanValue ?? false, sampledAt: detailTime)
  }

  private func execute(_ source: String, key: String) throws -> (NSAppleEventDescriptor, Double) {
    try Task.checkCancellation()
    var error: NSDictionary?
    let script: NSAppleScript
    if let cached = compiled[key] {
      script = cached
    } else {
      guard let created = NSAppleScript(source: source), created.compileAndReturnError(&error)
      else {
        throw PlayerError.failed("Script could not compile.")
      }
      compiled[key] = created
      script = created
    }
    let requestedAt = ProcessInfo.processInfo.systemUptime
    let result = script.executeAndReturnError(&error)
    let receivedAt = ProcessInfo.processInfo.systemUptime
    if let error {
      if error[NSAppleScript.errorNumber] as? Int == -1743 { throw PlayerError.denied }
      throw PlayerError.failed(
        (error[NSAppleScript.errorBriefMessage] as? String) ?? "Try reconnecting.")
    }
    return (result, (requestedAt + receivedAt) / 2)
  }
}

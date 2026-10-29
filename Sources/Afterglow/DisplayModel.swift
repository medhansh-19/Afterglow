import AfterglowCore
import CryptoKit
import SwiftUI

@MainActor
final class DisplayModel: ObservableObject {
  @Published private(set) var track: Track?
  @Published private(set) var lines: [LyricLine] = []
  @Published private(set) var source: PlayerSource?
  @Published private(set) var isDemo = false
  @Published private(set) var playing = false
  @Published private(set) var message = ""
  @Published private(set) var loading = false
  @Published private(set) var error: String?
  @Published private(set) var controlError: String?
  @Published private(set) var timingDelay = 0.0
  @Published private(set) var lyricDocument: LyricDocument?
  @Published private(set) var libraryError: String?
  @Published private(set) var albumColor: GlowColor?
  @Published private(set) var artworkStatus = "Connect a player to match its album cover."
  private var artworkTask: Task<Void, Never>?
  private var paletteCache: [String: GlowColor] = [:]
  private var clock = PlaybackClock()
  private var timer: Timer?
  private var lookup: Task<Void, Never>?
  private var generation = 0
  private var playerGeneration = 0
  private var polling: Task<Void, Never>?
  private var controlling: Task<Void, Never>?

  var connected: Bool { source != nil || isDemo }

  func position() -> Double {
    let value = clock.position(at: ProcessInfo.processInfo.systemUptime)
    if isDemo { return value.truncatingRemainder(dividingBy: Demo.track.duration) }
    return min(max(0, value), max(track?.duration ?? 0, 0))
  }

  var timingDescription: String {
    guard !lines.isEmpty else { return "Waiting for lyrics" }
    let count = lines.filter { !$0.text.isEmpty }.count
    let timed = lines.filter { !$0.words.isEmpty }.count
    let quality =
      timed == count ? "Word timestamps" : timed > 0 ? "Word + line timestamps" : "Line timestamps"
    return lyricDocument?.manualMatch == true ? "Manual version · " + quality : quality
  }

  func setTimingDelay(_ value: Double) {
    guard value.isFinite else { return }
    timingDelay = (min(5, max(-5, value)) * 20).rounded() / 20
    if let track { UserDefaults.standard.set(timingDelay, forKey: timingKey(track)) }
  }

  private func timingKey(_ track: Track) -> String {
    let bytes = Data("\(track.title)|\(track.artist)|\(track.album)|\(Int(track.duration))".utf8)
    return "afterglow.timing."
      + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  func connect(_ source: PlayerSource) {
    disconnect()
    self.source = source
    poll()
    if self.source != nil {
      let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.poll() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
  }

  func demo() {
    disconnect()
    isDemo = true
    track = Demo.track
    lines = Demo.wordTimedLines
    playing = true
    let now = ProcessInfo.processInfo.systemUptime
    clock.sample(position: 0, playing: true, sampledAt: now, receivedAt: now, force: true)
  }

  func toggleDemo() {
    guard isDemo else { return }
    let position = position()
    playing.toggle()
    let now = ProcessInfo.processInfo.systemUptime
    clock.sample(position: position, playing: playing, sampledAt: now, receivedAt: now, force: true)
  }

  func disconnect() {
    generation += 1
    playerGeneration += 1
    polling?.cancel()
    polling = nil
    controlling?.cancel()
    controlling = nil
    timer?.invalidate()
    timer = nil
    lookup?.cancel()
    lookup = nil
    artworkTask?.cancel()
    artworkTask = nil
    albumColor = nil
    artworkStatus = "Connect a player to match its album cover."
    source = nil
    isDemo = false
    track = nil
    lines = []
    lyricDocument = nil
    libraryError = nil
    playing = false
    clock = PlaybackClock()
    timingDelay = 0
    error = nil
    controlError = nil
    message = ""
    loading = false
  }

  func transport(_ action: TransportAction) {
    guard let source, !isDemo, controlling == nil else { return }
    let ticket = playerGeneration
    controlling = Task { [weak self] in
      do {
        try await Player.shared.control(action, source: source)
        guard let self, !Task.isCancelled, self.playerGeneration == ticket else { return }
        self.controlError = nil
        self.poll()
      } catch {
        guard let self, !Task.isCancelled, self.playerGeneration == ticket else { return }
        self.controlError = error.localizedDescription
      }
      if self?.playerGeneration == ticket { self?.controlling = nil }
    }
  }

  func retryLyrics() {
    guard let track, !isDemo else { return }
    fetch(track, bypassCache: true)
  }

  func importLyrics(from url: URL, for target: Track) {
    guard target == track else {
      libraryError = "The song changed. Open the importer again for the current recording."
      return
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 500_000 else {
        libraryError = "Choose a lyric file smaller than 500 KB."
        return
      }
      let text = try String(contentsOf: url, encoding: .utf8)
      guard let document = ImportedLyrics.parse(text, extension: url.pathExtension) else {
        libraryError =
          "No valid lyrics found. Choose a timed LRC, Lyricsfile YAML, or plain-text file."
        return
      }
      try LocalLyricsLibrary.save(document, for: target)
      generation += 1
      lookup?.cancel()
      loading = false
      libraryError = nil
      apply(document)
    } catch { libraryError = "Couldn’t read or save this file. Try a UTF-8 lyric file." }
  }

  func selectAlternative(_ alternative: LyricAlternative, for target: Track) {
    guard target == track else {
      libraryError = "The song changed. Review versions for the current song."
      return
    }
    do {
      try LocalLyricsLibrary.save(alternative.document, for: target)
      generation += 1
      lookup?.cancel()
      loading = false
      libraryError = nil
      apply(alternative.document)
    } catch { libraryError = "Couldn’t save this version. Try again." }
  }

  func useOnlineLyrics() {
    guard let track else { return }
    do {
      try LocalLyricsLibrary.useOnline(track)
      libraryError = nil
      fetch(track, bypassCache: true)
    } catch { libraryError = "Couldn’t switch this recording back to online lyrics." }
  }

  private func poll() {
    // One in-flight query: a slow player cannot accumulate timer work or stale snapshots.
    guard let source, polling == nil else { return }
    let ticket = playerGeneration
    polling = Task { [weak self] in
      defer { if self?.playerGeneration == ticket { self?.polling = nil } }
      do {
        let snapshot = try await Player.shared.read(source)
        guard let self, !Task.isCancelled, self.playerGeneration == ticket else { return }
        self.apply(snapshot, source: source)
      } catch {
        guard let self, !Task.isCancelled, self.playerGeneration == ticket else { return }
        let detail = error.localizedDescription
        self.disconnect()
        self.error = detail
      }
    }
  }

  private func apply(_ snapshot: PlayerSnapshot, source: PlayerSource) {
    // @Published emits even for nil → nil. Rebuilding native command menus on
    // every 400 ms poll interrupts hover tracking before submenus can open.
    if error != nil { error = nil }
    let changedTrack = track != snapshot.track
    clock.sample(
      position: snapshot.position, playing: snapshot.playing,
      sampledAt: snapshot.sampledAt, receivedAt: ProcessInfo.processInfo.systemUptime,
      force: changedTrack)
    if playing != snapshot.playing { playing = snapshot.playing }
    if changedTrack {
      lookup?.cancel()
      generation += 1
      track = snapshot.track
      lines = []
      lyricDocument = nil
      libraryError = nil
      loading = false
      updateArtwork(snapshot.track, source: source)
      let savedDelay =
        snapshot.track.map { UserDefaults.standard.double(forKey: timingKey($0)) } ?? 0
      timingDelay = savedDelay.isFinite ? min(5, max(-5, savedDelay)) : 0
      if let track { fetch(track) }
    }
    if snapshot.track == nil {
      let prompt = "Start a song in \(source.rawValue)."
      if message != prompt { message = prompt }
    }
  }

  private func updateArtwork(_ target: Track?, source: PlayerSource) {
    artworkTask?.cancel()
    guard let target else {
      albumColor = nil
      artworkStatus = "No album cover available."
      return
    }
    let key =
      "\(source.rawValue)|\(target.artist)|\(target.album.isEmpty ? target.title : target.album)"
    if let cached = paletteCache[key] {
      albumColor = cached
      artworkStatus = "Colors matched to the album cover."
      return
    }
    albumColor = nil
    artworkStatus = "Reading album cover…"
    artworkTask = Task { [weak self] in
      do {
        let reference = try await Player.shared.artwork(source)
        guard let self, !Task.isCancelled, self.track == target, self.source == source else {
          return
        }
        guard let reference else {
          self.artworkStatus = "Album cover unavailable; using Rose as a fallback."
          return
        }
        let color = try await AlbumArtwork.color(from: reference)
        guard !Task.isCancelled, self.track == target, self.source == source else { return }
        self.albumColor = color
        self.artworkStatus =
          color == nil
          ? "Album cover unavailable; using Rose as a fallback."
          : "Colors matched to the album cover."
        if let color {
          if self.paletteCache.count >= 40 { self.paletteCache.removeAll(keepingCapacity: true) }
          self.paletteCache[key] = color
        }
      } catch {
        guard let self, !Task.isCancelled, self.track == target else { return }
        self.artworkStatus = "Album cover unavailable; using Rose as a fallback."
      }
    }
  }

  private func fetch(_ target: Track, bypassCache: Bool = false) {
    lookup?.cancel()
    generation += 1
    if let document = LocalLyricsLibrary.read(target) {
      loading = false
      apply(document)
      return
    }
    let ticket = generation
    lyricDocument = nil
    lines = []
    loading = true
    message = "Finding synced lyrics…"
    let allowPlain =
      UserDefaults.standard.object(forKey: "afterglow.plainFallback") as? Bool ?? true
    lookup = Task { [weak self] in
      do {
        let result = try await LyricsClient().fetch(
          target, allowPlainFallback: allowPlain,
          allowTimedFallback: UserDefaults.standard.object(forKey: "afterglow.timedFallback") as? Bool ?? true,
          bypassCache: bypassCache)
        guard let self, !Task.isCancelled, self.generation == ticket, self.track == target else {
          return
        }
        self.loading = false
        if let result {
          self.apply(result)
        } else {
          self.message = "No lyrics found for this recording. Try importing a lyric file."
        }
      } catch {
        guard let self, !Task.isCancelled, self.generation == ticket else { return }
        self.loading = false
        self.message = "Lyrics couldn’t load. Check your connection and try again."
      }
    }
  }

  private func apply(_ document: LyricDocument) {
    lyricDocument = document
    lines = document.lines
    if document.timed {
      message = ""
    } else if document.instrumental {
      message = "Instrumental · let the music speak."
    } else if document.alternatives?.isEmpty == false {
      message = "No synced lyrics for this recording. Other timed versions are available in the lyric library."
    } else if document.plainText != nil {
      message = "Untimed lyrics available from \(document.source.name)."
    } else {
      message = "Timed versions found with different durations. Review them in the lyric library."
    }
  }
}

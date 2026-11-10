import AfterglowCore
import Combine
import CryptoKit
import SwiftUI

@MainActor
final class DisplayModel: ObservableObject {
  @Published private(set) var track: Track?
  @Published private(set) var lines: [LyricLine] = [] {
    didSet { if lines != oldValue { chorusMemory = ChorusMemory(lines: lines) } }
  }
  private(set) var chorusMemory = ChorusMemory(lines: [])
  @Published private(set) var source: PlayerSource?
  @Published private(set) var isDemo = false
  @Published private(set) var playing = false
  @Published private(set) var clockRevision = 0
  @Published private(set) var message = ""
  @Published private(set) var loading = false
  @Published private(set) var error: String?
  @Published private(set) var controlError: String?
  @Published private(set) var timingDelay = 0.0
  @Published private(set) var lyricDocument: LyricDocument?
  @Published private(set) var libraryError: String?
  @Published private(set) var albumColor: GlowColor?
  @Published private(set) var albumImage: NSImage?
  @Published private(set) var artworkStatus = "Connect a player to match its album cover."
  private var artworkTask: Task<Void, Never>?
  private var paletteCache: [String: GlowColor] = [:]
  private var artworkImages: [String: NSImage] = [:]
  private var clock = PlaybackClock()
  private var timer: Timer?
  private var lookup: Task<Void, Never>?
  private var generation = 0
  private var playerGeneration = 0
  private var polling: Task<Void, Never>?
  private var pollAgain = false
  private var controlling: Task<Void, Never>?
  private var activityVisible = true
  private var activityAwake = true
  private var energyBudget = EnergyBudget()
  private var playerObserver: NSObjectProtocol?
  private var energyObservation: AnyCancellable?

  init() {
    let monitor = EnergyMonitor.shared
    // The menu-bar model survives closing the display window; sleep handling must too.
    energyObservation = monitor.$isAwake.combineLatest(monitor.$budget).sink { [weak self] awake, budget in
      guard let self else { return }
      self.setActivity(visible: self.activityVisible, awake: awake, budget: budget)
    }
  }

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
    if lyricDocument?.automaticMatch == true { return "Automatic closest version · " + quality }
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
    // Notifications invalidate our own fixed player query; payload metadata is never trusted.
    let name = source == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"
    playerObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.poll() }
    }
    poll()
  }

  func setActivity(visible: Bool, awake: Bool, budget: EnergyBudget) {
    guard visible != activityVisible || awake != activityAwake || budget != energyBudget else { return }
    let resumed = awake && (!activityAwake || (visible && !activityVisible))
    activityVisible = visible
    activityAwake = awake
    energyBudget = budget
    timer?.invalidate()
    timer = nil
    if !awake { pollAgain = false; polling?.cancel() }
    else if resumed { poll() }
    else { schedulePoll() }
  }

  private func schedulePoll() {
    timer?.invalidate()
    timer = nil
    guard source != nil, activityAwake, polling == nil else { return }
    let interval = energyBudget.pollInterval(visible: activityVisible, playing: playing)
    let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.poll() }
    }
    next.tolerance = interval * 0.2
    RunLoop.main.add(next, forMode: .common)
    timer = next
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
    pollAgain = false
    controlling?.cancel()
    controlling = nil
    timer?.invalidate()
    timer = nil
    if let playerObserver { DistributedNotificationCenter.default().removeObserver(playerObserver) }
    playerObserver = nil
    lookup?.cancel()
    lookup = nil
    artworkTask?.cancel()
    artworkTask = nil
    albumColor = nil
    albumImage = nil
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
    guard let source, activityAwake else { return }
    // An event or completed transport command during a read needs a fresh read afterwards.
    if polling != nil { pollAgain = true; return }
    timer?.invalidate()
    timer = nil
    let ticket = playerGeneration
    polling = Task { [weak self] in
      defer {
        if let self, self.playerGeneration == ticket {
          self.polling = nil
          if self.pollAgain && self.activityAwake {
            self.pollAgain = false
            self.poll()
          } else { self.schedulePoll() }
        }
      }
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
    let previousPosition = position()
    clock.sample(
      position: snapshot.position, playing: snapshot.playing,
      sampledAt: snapshot.sampledAt, receivedAt: ProcessInfo.processInfo.systemUptime,
      force: changedTrack)
    if !snapshot.playing && abs(position() - previousPosition) > 0.001 {
      clockRevision &+= 1
    }
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
      albumImage = nil
      artworkStatus = "No album cover available."
      return
    }
    let key =
      "\(source.rawValue)|\(target.artist)|\(target.album.isEmpty ? target.title : target.album)"
    if let cached = paletteCache[key] {
      albumColor = cached
      albumImage = artworkImages[key]
      artworkStatus = "Colors matched to the album cover."
      return
    }
    albumColor = nil
    albumImage = nil
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
        let artwork = try await AlbumArtwork.load(from: reference)
        let color = artwork?.color
        guard !Task.isCancelled, self.track == target, self.source == source else { return }
        self.albumColor = color
        self.albumImage = artwork.map { NSImage(cgImage: $0.image, size: .zero) }
        self.artworkStatus =
          color == nil
          ? "Album cover unavailable; using Rose as a fallback."
          : "Colors matched to the album cover."
        if let color {
          if self.paletteCache.count >= 40 {
            self.paletteCache.removeAll(keepingCapacity: true)
            self.artworkImages.removeAll(keepingCapacity: true)
          }
          self.paletteCache[key] = color
          self.artworkImages[key] = self.albumImage
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
    loading = true
    message = "Finding synced lyrics…"
    let allowPlain =
      UserDefaults.standard.object(forKey: "afterglow.plainFallback") as? Bool ?? true
    lookup = Task { [weak self] in
      // Saved timings keep the graph available while the online library is checked.
      if let saved = await LyricCache.shared.read(target, allowPlain: allowPlain,
          allowTimedFallback: UserDefaults.standard.object(forKey: "afterglow.timedFallback") as? Bool ?? true,
          allowExpired: true), saved.timed,
          let self, !Task.isCancelled, self.generation == ticket, self.track == target {
        self.apply(saved)
        self.loading = false
      }
      // A transient outage or cached plain-text fallback must not leave the graph
      // unavailable for the whole song. Refresh a bounded number of times.
      for delay in [0, 15, 45] {
        if delay > 0 {
          do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
        guard !Task.isCancelled, self?.generation == ticket, self?.track == target else { return }
        do {
          let result = try await LyricsClient().fetch(
            target, allowPlainFallback: allowPlain,
            allowTimedFallback: UserDefaults.standard.object(forKey: "afterglow.timedFallback") as? Bool ?? true,
            bypassCache: true)
          guard let self, !Task.isCancelled, self.generation == ticket, self.track == target else {
            return
          }
          self.loading = false
          if let result {
            if result.timed || result.instrumental || self.lines.isEmpty { self.apply(result) }
            if (result.timed && result.retrievedFromCache != true) || result.instrumental { return }
          } else {
            self.message = "Synced lyrics aren’t available for this recording. Retry or import a timed lyric file."
          }
        } catch {
          guard let self, !Task.isCancelled, self.generation == ticket, self.track == target else { return }
          self.loading = false
          self.message = "Synced lyric sources couldn’t load. Retrying automatically…"
        }
      }
      guard let self, !Task.isCancelled, self.generation == ticket else { return }
      if self.lyricDocument == nil {
        self.message = "Synced lyric sources are unavailable. Retry or import a timed lyric file."
      }
    }
  }

  private func apply(_ input: LyricDocument) {
    let document = input.removingCredits()
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

import AfterglowCore
import CryptoKit
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WallpaperAppearance: ObservableObject {
  @Published private(set) var image: NSImage?
  @Published private(set) var loading = false
  @Published private(set) var error: String?
  private var task: Task<Void, Never>?
  private var generation = 0
  @Published private(set) var sceneTrack: Track?
  @Published private(set) var hasScene = false
  @Published private(set) var sceneMessage: String?
  private var baseline: SongAppearance?
  private var imageData: Data?
  private let store: SongKeepsakeStore
  private let defaults: UserDefaults
  private let imageURL: URL
  private func sceneKey(_ track: Track) -> String {
    SHA256.hash(data: Data(RecordingIdentity.key(track).utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func snapshot() -> SongAppearance {
    let d = defaults
    return SongAppearance(tint: d.string(forKey: "afterglow.tint") ?? Tint.album.rawValue,
      opacity: d.object(forKey: "afterglow.backgroundOpacity") as? Double ?? 0.15,
      marker: d.string(forKey: "afterglow.marker") ?? LyricMarker.diamond.rawValue,
      emoji: d.string(forKey: "afterglow.markerEmoji") ?? "✨",
      clock: d.object(forKey: "afterglow.clock") as? Bool ?? true,
      motion: d.object(forKey: "afterglow.motion") as? Bool ?? true,
      estimatedWords: d.object(forKey: "afterglow.estimatedWords") as? Bool ?? true,
      wallpaper: imageData, clockAppearance: ClockPreferences.read(from: d))
  }
  private func apply(_ value: SongAppearance) {
    let d = defaults
    d.set(value.tint, forKey: "afterglow.tint")
    d.set(value.opacity, forKey: "afterglow.backgroundOpacity")
    d.set(value.marker, forKey: "afterglow.marker")
    d.set(value.emoji, forKey: "afterglow.markerEmoji")
    d.set(value.clock, forKey: "afterglow.clock")
    ClockPreferences.write(value.clockAppearance ?? ClockAppearance(), to: d)
    d.set(value.motion, forKey: "afterglow.motion")
    d.set(value.estimatedWords, forKey: "afterglow.estimatedWords")
    imageData = value.wallpaper
    image = value.wallpaper.flatMap(NSImage.init(data:))
  }
  func activateScene(for track: Track?) {
    guard track != sceneTrack else { return }
    generation += 1
    task?.cancel(); loading = false
    sceneMessage = nil
    if let baseline { apply(baseline) }
    baseline = nil
    sceneTrack = track
    hasScene = false
    if let track, let saved = store.read(SongAppearance.self, name: sceneKey(track)) {
      let original = snapshot()
      do {
        // Recover global preferences after a crash or quit while a scene is active.
        try store.write(original, name: "default")
        baseline = original
        apply(saved)
        hasScene = true
      } catch { sceneMessage = "Couldn’t restore this scene. Your default appearance is still active." }
    } else {
      try? store.remove(name: "default")
    }
  }
  func saveScene() {
    guard let track = sceneTrack, !loading else { return }
    do {
      let value = snapshot()
      if baseline == nil {
        try store.write(value, name: "default")
        baseline = value
      }
      try store.write(value, name: sceneKey(track))
      hasScene = true
      sceneMessage = "Scene saved for \(track.title). It returns when this recording plays again."
    } catch { sceneMessage = "Couldn’t save this scene. Please try again." }
  }
  func removeScene() {
    guard let track = sceneTrack else { return }
    generation += 1; task?.cancel(); loading = false
    do {
      try store.remove(name: sceneKey(track))
      if let baseline { apply(baseline) }
      baseline = nil; hasScene = false
      try? store.remove(name: "default")
      sceneMessage = "Scene removed. This recording uses your default appearance."
    } catch { sceneMessage = "Couldn’t remove this scene. Please try again." }
  }

  init(defaults: UserDefaults = .standard,
       folder: URL = URL.applicationSupportDirectory.appending(path: "Afterglow")) {
    self.defaults = defaults
    store = SongKeepsakeStore(folder: folder.appending(path: "Scenes"))
    imageURL = folder.appending(path: "Wallpaper/background.png")
    let url = imageURL
    if let data = try? Data(contentsOf: url) { imageData = data; image = NSImage(data: data) }
    if let original = store.read(SongAppearance.self, name: "default") {
      apply(original)
      try? store.remove(name: "default")
    }
  }

  func chooseImage() {
    let panel = NSOpenPanel()
    panel.title = "Choose a wallpaper image"
    panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .webP]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    let ticket = generation
    panel.begin { [weak self] response in
      guard let self, self.generation == ticket, response == .OK, let url = panel.url else { return }
      self.load(url, importing: true)
    }
  }

  private func load(_ url: URL, importing: Bool) {
    guard !loading else { return }
    loading = true
    error = nil
    let destination = imageURL
    let ticket = generation
    task = Task {
      do {
        let data = try await Task.detached(priority: .utility) {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2560,
                  kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
          else { throw CocoaError(.fileReadCorruptFile) }
          let bitmap = NSBitmapImageRep(cgImage: thumbnail)
          guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
          }
          return data
        }.value
        guard !Task.isCancelled, generation == ticket else { return }
        if importing && baseline == nil {
          try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
          try data.write(to: destination, options: .atomic)
        }
        imageData = data
        image = NSImage(data: data)
      } catch {
        guard !Task.isCancelled, generation == ticket else { return }
        self.error = "This image couldn’t be loaded. Choose another JPEG, PNG, HEIC, TIFF or WebP image."
      }
      loading = false
    }
  }

  func removeImage() {
    guard !loading else { return }
    do {
      if baseline == nil && FileManager.default.fileExists(atPath: imageURL.path) {
        try FileManager.default.removeItem(at: imageURL)
      }
      image = nil
      imageData = nil
      error = nil
    } catch {
      self.error = "The saved image couldn’t be removed. Please try again."
    }
  }
}

struct WallpaperBackground: View {
  let image: NSImage?
  let opacity: Double
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black
        if let image {
          Image(nsImage: image).resizable().scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped().opacity(min(1, max(0, opacity)))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

// Purely visual: selection never affects lyric timestamps or node positions.
enum LyricMarker: String, CaseIterable, Identifiable {
  case diamond = "Diamond", dot = "Dot", triangle = "Triangle", rectangle = "Rectangle"
  case star = "Star", octagon = "Octagon", emoji = "Emoji"
  var id: String { rawValue }
}

struct MarkerSymbol: View {
  let marker: LyricMarker
  let emoji: String
  let tint: Color
  var body: some View {
    Group {
      if marker == .emoji {
        Text(emoji.isEmpty ? "✨" : String(emoji.prefix(1)))
          .font(.system(size: 16)).frame(width: 20, height: 20)
      } else {
        MarkerShape(marker: marker).fill(tint).frame(width: 7, height: 7)
      }
    }
    .accessibilityHidden(true)
  }
}

struct MarkerShape: Shape {
  let marker: LyricMarker
  func path(in rect: CGRect) -> Path {
    switch marker {
    case .dot: return Path(ellipseIn: rect)
    case .rectangle: return Path(CGRect(x: rect.minX, y: rect.midY - rect.height * 0.35,
                                       width: rect.width, height: rect.height * 0.7))
    case .diamond: return Diamond().path(in: rect)
    default:
      let vertices: Int = marker == .triangle ? 3 : marker == .star ? 10 : 8
      var path = Path()
      for i in 0..<vertices {
        let angle: Double = Double(i) * 2 * Double.pi / Double(vertices) - Double.pi / 2
        let scale: CGFloat = marker == .star && i % 2 == 1 ? 0.44 : 1
        let radius: CGFloat = min(rect.width, rect.height) / 2 * scale
        let x: CGFloat = rect.midX + CGFloat(cos(angle)) * radius
        let y: CGFloat = rect.midY + CGFloat(sin(angle)) * radius
        let point = CGPoint(x: x, y: y)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
      return path
    }
  }
}

/// Static, seeded pinpoints keep the appearance sheet quiet and inexpensive.
struct AppearanceNightSky: View {
  let tint: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("afterglow.motion") private var motion = true
  var body: some View {
    LinearGradient(colors: Theme.appearanceSkyColors(for: tint),
                   startPoint: .top, endPoint: .bottom)
      .overlay {
        Canvas { context, size in
          for i in 0..<65 {
            let x = (Double(i) * 137.47 + 23).truncatingRemainder(dividingBy: max(1, size.width))
            let y = (Double(i) * 83.29 + 19).truncatingRemainder(dividingBy: max(1, size.height))
            let diameter = i % 11 == 0 ? 1.4 : 0.75
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                         with: .color(.white.opacity(i % 11 == 0 ? 0.30 : 0.12)))
          }
        }
      }.animation(reduceMotion || !motion ? nil : .easeInOut(duration: 0.65), value: tint)
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}

struct WallpaperSettings: View {
  @Environment(\.renderBudget) private var budget
  @Environment(\.renderActive) private var active
  @AppStorage("afterglow.chorusMemory") private var chorusMemory = true
  @ObservedObject var collections: SongCollections = .shared
  @ObservedObject var appearance: WallpaperAppearance
  @ObservedObject var model: DisplayModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("afterglow.estimatedWords") private var estimatedWords = true
  @ObservedObject var beats: BeatCapture
  let source: PlayerSource?
  let albumImage: NSImage?
  let artworkStatus: String
  let tint: Color
  @Binding var presented: DisplayPanels.Panel?
  @State private var showClockSettings = false
  @AppStorage("afterglow.tint") private var tintName = Tint.album.rawValue
  @AppStorage("afterglow.clock") private var showClock = true
  @AppStorage("afterglow.motion") private var motion = true
  @AppStorage("afterglow.backgroundOpacity") private var opacity = 0.15
  @AppStorage("afterglow.marker") private var markerName = LyricMarker.diamond.rawValue
  @AppStorage("afterglow.markerEmoji") private var emoji = "✨"
  private var colorSelection: Binding<String> {
    collections.colorSelection(for: model.track, fallback: $tintName)
  }
  private var albumColor: Color {
    model.albumColor.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Tint.rose.color
  }
  private var marker: LyricMarker { LyricMarker(rawValue: markerName) ?? .diamond }
  private var beatEnabled: Binding<Bool> {
    Binding(get: { beats.running || beats.starting }, set: { enabled in
      if enabled, let source { Task { await beats.start(source: source) } }
      else { beats.stop() }
    })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Make it yours").font(.system(size: 24, weight: .semibold))
          Text("A little color. A little atmosphere.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        Text("afterglow").font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
      }
      ScrollView {
        HStack(alignment: .top, spacing: 24) {
          wallpaperColumn.frame(width: 256)
          controlsColumn.frame(maxWidth: .infinity)
        }.padding(.bottom, 4)
      }
      Divider().overlay(.white.opacity(0.08))
      HStack(spacing: 12) {
        Spacer()
        Button("Reset") {
          colorSelection.wrappedValue = Tint.album.rawValue; showClock = true; motion = true
          opacity = 0.15; markerName = LyricMarker.diamond.rawValue; emoji = "✨"
          ClockPreferences.write(ClockAppearance())
        }.help("Reset color, clock, animation, opacity and lyric markers. Keeps your wallpaper and saved colors.")
        Button("Done") { presented = nil }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Color.accentColor)
      }
    }
    .font(.system(size: 13)).padding(24).frame(width: 800, height: 700)
    .background(AppearanceNightSky(tint: tint)).preferredColorScheme(.dark)
    .buttonStyle(.bordered).tint(.white)
    .onExitCommand { presented = nil }
  }
  private var wallpaperColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      preview
      HStack {
        Text("Wallpaper").fontWeight(.semibold)
        Spacer()
        Text(appearance.image == nil ? "Black sky" : "Your image").font(.system(size: 11)).foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Button(appearance.image == nil ? "Choose image…" : "Replace…") { appearance.chooseImage() }
        Button("Remove") { appearance.removeImage() }.disabled(appearance.image == nil)
      }.disabled(appearance.loading)
      if appearance.loading { ProgressView("Preparing image…").controlSize(.small) }
      VStack(spacing: 8) {
        HStack {
          Text("Opacity")
          Spacer()
          Text("\(Int(opacity * 100))%").monospacedDigit()
        }.font(.system(size: 12)).foregroundStyle(.secondary)
        Slider(value: $opacity, in: 0...1, step: 0.01) { Text("Image opacity") }
          .labelsHidden().disabled(appearance.image == nil)
      }
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        Text("Keep this song’s mood").fontWeight(.medium)
        Text(appearance.sceneTrack.map { "Save these visuals for \($0.title)." } ?? "Play a song to save its scene.")
          .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Button(appearance.hasScene ? "Update song scene" : "Save song scene") { appearance.saveScene() }
            .disabled(appearance.sceneTrack == nil || appearance.loading)
          if appearance.hasScene { Button("Remove scene") { appearance.removeScene() } }
        }
        if let message = appearance.sceneMessage {
          Text(message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      if let error = appearance.error { Text(error).foregroundStyle(Theme.amber).font(.caption) }
    }
  }
  private var controlsColumn: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let track = model.track, let collection = collections.library.colorCollection(for: track),
        collection.lyricColor != nil {
        VStack(alignment: .leading, spacing: 6) {
          Text("Editing \(collection.name)’s lyric color. Applies to all songs using this collection.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Edit collection color…") { presented = .collections }
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text(appearance.hasScene ? "Editing this song’s scene color." : "Editing your default lyric color.")
            .font(.caption).foregroundStyle(.secondary)
          if let track = model.track, !collections.library.collections.contains(where: { $0.contains(track) }) {
            Button("Save this song to a collection…") { presented = .collections }
          }
        }
      }
      GlowColorSelector(selection: colorSelection, albumColor: albumColor, albumImage: albumImage, artworkStatus: artworkStatus)
      if let error = collections.error {
        Text(error).font(.caption).foregroundStyle(Theme.amber)
      }
      Divider()
      Text("On your screen").fontWeight(.semibold)
      VStack(spacing: 12) {
        HStack {
          Text("Clock")
          Button("Customize…") { showClockSettings = true }
            .popover(isPresented: $showClockSettings) { ClockSettings(lyricColor: tint) }
          Spacer()
          Toggle("Show clock", isOn: $showClock).labelsHidden().tint(Color.accentColor)
        }
        appearanceToggle("Animate word changes", isOn: $motion)
        appearanceToggle("Beat sync", isOn: beatEnabled)
          .disabled(source == nil).help(source == nil ? "Connect a player to enable beat sync." : beats.state)
        if beats.starting { ProgressView("Connecting audio…").controlSize(.small) }
        if beats.permissionRequired {
          Button("Allow audio in System Settings…") { beats.openPermissionSettings() }
        }
        if !beats.running && !beats.starting && beats.state != "Ambient motion" {
          Text(beats.state).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
          Text("Lyric marker")
          Spacer()
          Picker("Lyric marker", selection: $markerName) {
            ForEach(LyricMarker.allCases) { Text($0.rawValue).tag($0.rawValue) }
          }.labelsHidden().fixedSize()
        }
        if marker == .emoji {
          TextField("Custom emoji", text: $emoji).textFieldStyle(.roundedBorder)
            .onChange(of: emoji) { _, value in
              let first = String(value.prefix(1)); if emoji != first { emoji = first }
            }
        }
      }.toggleStyle(.switch).controlSize(.small)
    }
  }
  private func appearanceToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    HStack {
      Text(title)
      Spacer()
      Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Color.accentColor)
    }
  }
  private var preview: some View {
    TimelineView(.animation(minimumInterval: budget.previewInterval, paused: !model.playing || !active)) { timeline in
      ZStack {
        WallpaperBackground(image: appearance.image, opacity: opacity)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(model.playing ? "LIVE PREVIEW" : model.track == nil ? "PREVIEW" : "PAUSED PREVIEW")
              .font(.system(size: 8, weight: .medium)).tracking(1.5)
            Spacer()
            Text("afterglow").font(.system(size: 8)).tracking(1)
          }.foregroundStyle(.white.opacity(0.65))
          GeometryReader { geometry in
            let scale = geometry.size.width / 640
            Group {
              if !model.lines.isEmpty {
                Constellation(lines: model.lines, position: model.position() - model.timingDelay,
                  duration: model.track?.duration ?? 0, tint: tint,
                  reduceMotion: reduceMotion || !motion, estimatedWords: estimatedWords,
                  beatFrame: beats.frame, liveBeats: beats.running, playing: model.playing,
                  marker: marker, markerEmoji: emoji, chorusMemory: chorusMemory ? model.chorusMemory : nil)
              } else {
                InstrumentalView(frame: beats.frame, live: beats.running, playing: model.playing,
                  tint: tint, reduceMotion: reduceMotion || !motion)
              }
            }
            .frame(width: 640, height: geometry.size.height / scale)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
          }
          HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
              Text(model.track?.title ?? "Connect a player to preview")
                .font(.system(size: 10, weight: .medium)).lineLimit(1)
              Text(model.loading ? "Finding lyrics…" : model.track?.artist ?? "Your music, live.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if showClock {
              LiveClockDisplay(lyricColor: tint, previewScale: 0.32)
            }
          }
        }.padding(16)
      }
      .environment(\.parentRenderTick, timeline.date)
    }.frame(height: 232).clipShape(RoundedRectangle(cornerRadius: 16))
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Live preview of current song")
  }
}

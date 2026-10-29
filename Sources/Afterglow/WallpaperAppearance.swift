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

  private static var imageURL: URL {
    URL.applicationSupportDirectory.appending(path: "Afterglow/Wallpaper/background.png")
  }

  init() {
    let url = Self.imageURL
    if FileManager.default.fileExists(atPath: url.path) { load(url, importing: false) }
  }

  func chooseImage() {
    let panel = NSOpenPanel()
    panel.title = "Choose a wallpaper image"
    panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .webP]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.load(url, importing: true)
    }
  }

  private func load(_ url: URL, importing: Bool) {
    guard !loading else { return }
    loading = true
    error = nil
    let destination = Self.imageURL
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
          if importing {
            try FileManager.default.createDirectory(
              at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
          }
          return data
        }.value
        image = NSImage(data: data)
      } catch {
        self.error = "This image couldn’t be loaded. Choose another JPEG, PNG, HEIC, TIFF or WebP image."
      }
      loading = false
    }
  }

  func removeImage() {
    guard !loading else { return }
    do {
      if FileManager.default.fileExists(atPath: Self.imageURL.path) {
        try FileManager.default.removeItem(at: Self.imageURL)
      }
      image = nil
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
      let vertices = marker == .triangle ? 3 : marker == .star ? 10 : 8
      return Path { path in
        for i in 0..<vertices {
          let angle = Double(i) * 2 * .pi / Double(vertices) - .pi / 2
          let radius = min(rect.width, rect.height) / 2 * (marker == .star && i % 2 == 1 ? 0.44 : 1)
          let point = CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
          if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
      }
    }
  }
}

struct WallpaperSettings: View {
  @ObservedObject var appearance: WallpaperAppearance
  let tint: Color
  @Binding var presented: DisplayPanels.Panel?
  @AppStorage("afterglow.tint") private var tintName = Tint.album.rawValue
  @AppStorage("afterglow.clock") private var showClock = true
  @AppStorage("afterglow.motion") private var motion = true
  @AppStorage("afterglow.backgroundOpacity") private var opacity = 0.15
  @AppStorage("afterglow.marker") private var markerName = LyricMarker.diamond.rawValue
  @AppStorage("afterglow.markerEmoji") private var emoji = "✨"
  private var marker: LyricMarker { LyricMarker(rawValue: markerName) ?? .diamond }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Appearance & Wallpaper").font(.title2)
        Spacer()
        Button("Done") { presented = nil }.keyboardShortcut(.defaultAction)
      }
      HStack {
        Picker("Glow color", selection: $tintName) {
          ForEach(Tint.allCases) { Text($0.rawValue).tag($0.rawValue) }
        }
        Toggle("Show clock", isOn: $showClock)
      }
      Toggle("Animate word changes", isOn: $motion)
      ZStack {
        WallpaperBackground(image: appearance.image, opacity: opacity)
        VStack(spacing: 14) {
          Text("Your music. Your backdrop.").font(.title3).foregroundStyle(tint)
          HStack(spacing: 0) {
            ForEach(0..<5) { _ in
              MarkerSymbol(marker: marker, emoji: emoji, tint: tint)
              Rectangle().fill(tint.opacity(0.4)).frame(width: 32, height: 1)
            }
            MarkerSymbol(marker: marker, emoji: emoji, tint: tint)
          }
        }
      }
      .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 12))
      .accessibilityLabel("Wallpaper and lyric marker preview")
      HStack {
        Button(appearance.image == nil ? "Choose Image…" : "Replace Image…") { appearance.chooseImage() }
        Button("Remove Image") { appearance.removeImage() }.disabled(appearance.image == nil)
        if appearance.loading { ProgressView().controlSize(.small); Text("Preparing image…") }
      }.disabled(appearance.loading)
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Image opacity")
          Spacer()
          Text("\(Int(opacity * 100))%").monospacedDigit()
        }
        Slider(value: $opacity, in: 0...1, step: 0.01) { Text("Image opacity") }
          .labelsHidden()
          .disabled(appearance.image == nil)
        Text("Start low for a subtle backdrop. 0% is black; 100% shows the full image.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      Picker("Lyric marker", selection: $markerName) {
        ForEach(LyricMarker.allCases) { Text($0.rawValue).tag($0.rawValue) }
      }
      if marker == .emoji {
        HStack {
          TextField("Custom emoji", text: $emoji).frame(width: 150)
            .onChange(of: emoji) { _, value in
              let first = String(value.prefix(1))
              if emoji != first { emoji = first }
            }
          Menu("Suggestions") {
            ForEach(["✨", "⭐️", "❤️", "🔥", "🏎️", "🌙"], id: \.self) { value in
              Button(value) { emoji = value }
            }
          }
          Text("One character or emoji").font(.caption).foregroundStyle(.secondary)
        }
      }
      if let error = appearance.error { Text(error).foregroundStyle(Theme.amber).font(.callout) }
      Text("Images stay on this Mac. These controls change the visuals; lyric timing uses your existing settings.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(26).frame(width: 540).preferredColorScheme(.dark)
    .onExitCommand { presented = nil }
  }
}

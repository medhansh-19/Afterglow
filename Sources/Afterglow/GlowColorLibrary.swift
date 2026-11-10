import AfterglowCore
import AppKit
import SwiftUI

@MainActor
final class GlowColorLibrary: ObservableObject {
  static let shared = GlowColorLibrary()
  @Published private(set) var colors: [SavedGlowColor]
  private let defaults: UserDefaults
  private static let key = "afterglow.savedGlowColors"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    var seen = Set<String>()
    colors = (defaults.array(forKey: Self.key) as? [[String: String]] ?? []).compactMap { row in
      guard let hex = row["hex"], let color = SavedGlowColor(hex: hex, name: row["name"] ?? ""),
        seen.insert(color.hex).inserted else { return nil }
      return color
    }
  }
  @discardableResult func save(hex: String, name: String) -> SavedGlowColor? {
    guard let color = SavedGlowColor(hex: hex, name: name) else { return nil }
    if let existing = colors.first(where: { $0.hex == color.hex }) { return existing }
    colors.append(color)
    persist()
    return color
  }
  func remove(_ color: SavedGlowColor) {
    colors.removeAll { $0.hex == color.hex }
    persist()
  }
  private func persist() {
    defaults.set(colors.map { ["hex": $0.hex, "name": $0.name] }, forKey: Self.key)
  }
  static func hex(from color: Color) -> String? {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
      .map { Int((min(1, max(0, $0)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
  }
}

/// One native picker owner for quick menus, including custom colors saved in Appearance.
struct GlowColorMenuPicker: View {
  @Binding var selection: String
  @ObservedObject private var library = GlowColorLibrary.shared
  var body: some View {
    Picker("Glow color", selection: $selection) {
      ForEach(Tint.allCases) { Text($0.rawValue).tag($0.rawValue) }
      if !library.colors.isEmpty { Divider() }
      ForEach(library.colors) { Text($0.name).tag($0.hex) }
      if SavedGlowColor(hex: selection) != nil, !library.colors.contains(where: { $0.hex == selection }) {
        Text("Custom \(selection)").tag(selection)
      }
    }
  }
}

struct GlowColorSelector: View {
  enum Layout { case appearance, collection }
  let layout: Layout
  @Binding var selection: String
  let albumColor: Color
  var albumImage: NSImage?
  var artworkStatus: String
  @ObservedObject private var library: GlowColorLibrary
  @State private var name = ""
  @State private var savedMessage = ""
  @State private var showCustom = false
  @State private var manualSelection = Tint.blue.rawValue
  @State private var hexDraft = ""
  @State private var hexError: String?
  init(selection: Binding<String>, albumColor: Color, albumImage: NSImage? = nil,
       artworkStatus: String = "Album artwork is unavailable.", library: GlowColorLibrary = .shared,
       layout: Layout = .appearance) {
    self.layout = layout
    self._selection = selection
    self.albumColor = albumColor
    self.albumImage = albumImage
    self.artworkStatus = artworkStatus
    self.library = library
  }
  private var isAlbum: Bool { selection == Tint.album.rawValue }
  private var activeColor: Color { Tint.resolve(selection, albumColor: albumColor) }
  private var activeHex: String { GlowColorLibrary.hex(from: activeColor) ?? "#F066AB" }
  private var isSaved: Bool { library.colors.contains { $0.hex == activeHex } }
  private var customColor: Binding<Color> {
    Binding(get: { activeColor }, set: { color in
      if let hex = GlowColorLibrary.hex(from: color) { savedMessage = ""; selection = hex }
    })
  }
  private var mode: Binding<Bool> {
    Binding(get: { isAlbum }, set: { album in
      if album { manualSelection = selection; selection = Tint.album.rawValue }
      else { selection = manualSelection }
    })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if layout == .appearance {
        HStack {
          Text("Lyric color").font(.system(size: 15, weight: .semibold))
          Spacer()
          Text(activeHex).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
      }
      Picker("Color source", selection: mode) {
        Text("Album cover").tag(true)
        Text("Choose color").tag(false)
      }.pickerStyle(.segmented).labelsHidden().tint(.white)
      Group {
        if isAlbum {
          VStack(alignment: .leading, spacing: 10) {
            if let albumImage {
              Image(nsImage: albumImage).resizable().scaledToFit()
                .frame(width: 184, height: 184).clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Current album cover")
            } else {
              ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
                Image(systemName: "opticaldisc").font(.system(size: 40, weight: .ultraLight))
                  .foregroundStyle(albumColor)
              }.frame(width: 184, height: 184).accessibilityLabel("Album cover unavailable")
            }
            Text(artworkStatus).font(.system(size: 11)).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        } else {
          VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 6) {
              ForEach(Tint.allCases.filter { $0 != .album }) { preset in
                swatch(color: preset.color, label: preset.rawValue, value: preset.rawValue)
              }
            }
            HStack(spacing: 12) {
              Button("Custom color…") { showCustom = true }
                .popover(isPresented: $showCustom) { customEditor }
              Text("Open the color wheel").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
              Text("Your colors").font(.system(size: 12, weight: .medium))
              Spacer()
              Text("Saved on this Mac").font(.system(size: 10))
            }.foregroundStyle(.secondary)
            if library.colors.isEmpty {
              Text("Save a custom shade to keep it here.").font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(height: 28)
            } else {
              ScrollView(.horizontal) {
                HStack(spacing: 8) {
                  ForEach(library.colors) { saved in
                    Button { selection = saved.hex } label: {
                      HStack(spacing: 6) {
                        Circle().fill(Tint.resolve(saved.hex)).frame(width: 10, height: 10)
                        Text(saved.name).lineLimit(1)
                        if selection == saved.hex { Image(systemName: "checkmark").font(.system(size: 9)) }
                      }.font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 7)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help(saved.hex)
                      .contextMenu { Button("Remove saved color", role: .destructive) { library.remove(saved) } }
                  }
                }
              }.frame(height: 34)
            }
          }
        }
      }.frame(maxWidth: .infinity, minHeight: layout == .appearance ? 218 : 0, alignment: .topLeading)
    }
    .onAppear {
      if !isAlbum { manualSelection = selection }

    }
  }
  private var customEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add a color").font(.title3.weight(.semibold))
      Text("Find a shade that feels like you.").font(.caption).foregroundStyle(.secondary)
      GlowColorWheel(color: customColor)
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8).fill(activeColor).frame(width: 36, height: 36)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2)))
          .accessibilityHidden(true)
        TextField("Hex color", text: $hexDraft).textFieldStyle(.roundedBorder)
          .font(.system(size: 13, design: .monospaced)).accessibilityLabel("Hex color")
          .onSubmit { applyHex() }
          .onChange(of: hexDraft) { _, value in
            if value.replacingOccurrences(of: "#", with: "").count == 6, SavedGlowColor(hex: value) != nil { applyHex() }
          }
      }
      if let hexError { Text(hexError).font(.caption).foregroundStyle(.orange) }
      TextField("Color name (optional)", text: $name).textFieldStyle(.roundedBorder)
        .accessibilityLabel("Name for saved color")
        .onChange(of: name) { _, value in if value.count > 32 { name = String(value.prefix(32)) } }
        .onSubmit { saveColor() }
      Text(savedMessage.isEmpty ? "Saved colors stay in Your colors for next time." : savedMessage)
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Done") { showCustom = false }
        Spacer()
        Button(isSaved ? "Saved" : "Save color") { saveColor() }.disabled(isSaved)
      }
    }.padding(22).frame(width: 300).background(AppearanceNightSky(tint: activeColor)).preferredColorScheme(.dark)
      .onAppear { hexDraft = activeHex }
      .onChange(of: activeHex) { _, value in if hexDraft.uppercased() != value { hexDraft = value }; hexError = nil }
  }
  private func applyHex() {
    guard let color = SavedGlowColor(hex: hexDraft) else {
      hexError = "Use a hex color such as #6BB0F7."; return
    }
    hexError = nil
    selection = color.hex

  }
  private func saveColor() {
    guard !isSaved, let saved = library.save(hex: activeHex, name: name) else { return }
    selection = saved.hex
    name = ""
    savedMessage = "Saved \(saved.name) to your colors."
  }
  private func swatch(color: Color, label: String, value: String) -> some View {
    Button { savedMessage = ""; selection = value } label: {
      ZStack {
        Circle().fill(color).frame(width: 26, height: 26)
        if selection == value {
          Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
        }
      }.frame(width: 36, height: 36)
        .overlay(Circle().strokeBorder(selection == value ? Color.white.opacity(0.85) : .clear, lineWidth: 1.5))
        .contentShape(Circle())
    }.buttonStyle(.plain).help(label).accessibilityLabel(label)
      .accessibilityValue(selection == value ? "Selected" : "")
  }
}

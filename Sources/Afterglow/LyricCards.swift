import AfterglowCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LyricCardLibrary: ObservableObject {
  @Published private(set) var excerpts: [SavedLyricExcerpt] = []
  @Published var message: String?
  private let store = SongKeepsakeStore(folder: URL.applicationSupportDirectory.appending(path: "Afterglow/LyricCards"))
  private var unreadableLibrary = false
  init() {
    if let saved = store.read([SavedLyricExcerpt].self, name: "excerpts") { excerpts = saved }
    else if store.exists(name: "excerpts") {
      unreadableLibrary = true
      message = "Your saved excerpt library couldn’t be read. Its file is preserved; you can still export a new card."
    }
  }
  @discardableResult func save(_ excerpt: SavedLyricExcerpt) -> Bool {
    guard !unreadableLibrary else { return false }
    do {
      let updated = [excerpt] + excerpts
      try store.write(updated, name: "excerpts")
      excerpts = updated
      message = "Excerpt saved on this Mac."
      return true
    } catch { message = "Couldn’t save your excerpt. Please try again."; return false }
  }
  func remove(_ excerpt: SavedLyricExcerpt) {
    do {
      let updated = excerpts.filter { $0.id != excerpt.id }
      try store.write(updated, name: "excerpts")
      excerpts = updated
    } catch { message = "Couldn’t remove your excerpt. Please try again." }
  }
}

@MainActor
struct LyricCardsView: View {
  @ObservedObject var model: DisplayModel
  @Binding var presented: DisplayPanels.Panel?
  @StateObject private var library = LyricCardLibrary()
  @State private var draftTrack: Track?
  @State private var draftColor = GlowColor.fallback
  @State private var lyricLines: [String] = []
  @State private var selection: Set<Int> = []
  @State private var active: SavedLyricExcerpt?
  private var text: String? { SavedLyricExcerpt.text(from: lyricLines, selected: selection) }
  private var draft: SavedLyricExcerpt? {
    guard let draftTrack, let text else { return nil }
    return SavedLyricExcerpt(track: draftTrack, text: text, color: draftColor)
  }
  private var preview: SavedLyricExcerpt? { active ?? draft }
  var body: some View {
    ScrollView {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Lyric cards").font(.title2)
        Spacer()
        Button("Done") { presented = nil }.keyboardShortcut(.defaultAction)
      }
      HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("\(draftTrack?.title ?? "No song selected")").font(.headline).lineLimit(2)
            Spacer()
            Button("Use Current Song") { capture() }.disabled(model.track == nil)
          }
          Text("Choose up to 6 lines and 280 characters. Save an excerpt to keep it for later.")
            .font(.caption).foregroundStyle(.secondary)
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              if lyricLines.isEmpty {
                Text("No lyrics available. Open the lyric library to import lyrics, then choose Use Current Song.")
                  .foregroundStyle(.secondary).font(.callout)
              }
              ForEach(lyricLines.indices, id: \.self) { index in
                Toggle(lyricLines[index], isOn: Binding(get: { selection.contains(index) }, set: { enabled in
                  active = nil
                  if enabled { selection.insert(index) } else { selection.remove(index) }
                })).toggleStyle(.checkbox).fixedSize(horizontal: false, vertical: true)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.frame(height: 175)
          Text("\(selection.count) / 6 lines · \(selection.sorted().map { lyricLines[$0] }.joined(separator: "\n").count) / 280 characters")
            .font(.caption).foregroundStyle(text == nil && !selection.isEmpty ? Theme.amber : Theme.secondary)
          Button("Save Excerpt") {
            guard let draft else { return }
            if library.save(draft) { active = draft }
          }.disabled(draft == nil || active != nil)
          Divider()
          Text("Saved excerpts").font(.headline)
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              if library.excerpts.isEmpty { Text("Your saved excerpts appear here.").foregroundStyle(.secondary).font(.caption) }
              ForEach(library.excerpts) { excerpt in
                HStack(alignment: .top) {
                  Button { active = excerpt } label: {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(excerpt.text).lineLimit(2)
                      Text("\(excerpt.track.title) · \(excerpt.track.artist)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                  }.buttonStyle(.plain)
                  Button { library.remove(excerpt); if active?.id == excerpt.id { active = nil } } label: {
                    Image(systemName: "trash")
                  }.accessibilityLabel("Remove excerpt from \(excerpt.track.title)")
                }.padding(6)
                .background(active?.id == excerpt.id ? Theme.panel : Color.clear, in: RoundedRectangle(cornerRadius: 6))
              }
            }
          }.frame(height: 100)
        }.frame(width: 330)
        VStack(spacing: 12) {
          if let preview {
            LyricCardArtwork(excerpt: preview).scaleEffect(0.55, anchor: .topLeading)
              .frame(width: 297, height: 371.25, alignment: .topLeading)
              .accessibilityLabel("Card preview for \(preview.track.title) by \(preview.track.artist): \(preview.text)")
          } else {
            Text("Select lyrics to preview your card.").font(.callout).foregroundStyle(.secondary)
              .frame(width: 297, height: 371.25).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
          }
          HStack {
            Button("Export PNG…") { export() }.disabled(preview == nil)
            Button("Copy Image") { copy() }.disabled(preview == nil)
          }
          Text("1080 × 1350 PNG · album colors\nSaved excerpts keep their original song and colors.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
      }
      if let message = library.message { Text(message).font(.caption).foregroundStyle(Theme.amber) }
    }.padding(26)
    }.frame(width: 705, height: 590).preferredColorScheme(.dark)
      .onAppear { capture() }
      .onExitCommand { presented = nil }
  }
  private func capture() {
    draftTrack = model.track
    draftColor = model.albumColor ?? .fallback
    lyricLines = (model.lyricDocument?.plainText?.components(separatedBy: .newlines) ?? model.lines.map(\.text))
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    selection = []; active = nil
  }
  private func png() -> Data? {
    guard let preview else { return nil }
    let renderer = ImageRenderer(content: LyricCardArtwork(excerpt: preview))
    renderer.scale = 2
    guard let image = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
  private func export() {
    guard let data = png(), let preview else { library.message = "Couldn’t render this card. Please try again."; return }
    let panel = NSSavePanel()
    panel.title = "Export Lyric Card"
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = preview.track.title.replacingOccurrences(of: "/", with: "-") + " — Afterglow.png"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do { try data.write(to: url, options: .atomic); library.message = "Card exported." }
      catch { library.message = "Couldn’t export to this location. Choose another folder." }
    }
  }
  private func copy() {
    guard let data = png() else { library.message = "Couldn’t render this card. Please try again."; return }
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.setData(data, forType: .png) { library.message = "Card copied. Paste it into another app." }
    else { library.message = "Couldn’t copy this card. Try exporting it instead." }
  }
}

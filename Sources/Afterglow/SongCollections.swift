import AfterglowCore
import SwiftUI

@MainActor
final class SongCollections: ObservableObject {
  static let shared = SongCollections()
  @Published private(set) var library: SongCollectionLibrary
  @Published private(set) var error: String?
  @Published private(set) var status = "Changes save on this Mac."
  private let store: SongKeepsakeStore
  private var readable = true

  init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "Afterglow/Collections")) {
    store = SongKeepsakeStore(folder: folder)
    if store.exists(name: "library"), let saved = store.read(SongCollectionLibrary.self, name: "library") {
      library = saved
    } else if store.exists(name: "library") {
      library = SongCollectionLibrary(collections: [])
      readable = false
      error = "Couldn’t read your collections. Your saved file has been kept. Reopen Afterglow after restoring it from a backup."
    } else { library = SongCollectionLibrary() }
  }

  @discardableResult
  func update(_ message: String, _ change: (inout SongCollectionLibrary) -> Void) -> Bool {
    guard readable else { return false }
    var next = library
    change(&next)
    guard next != library else { return true }
    do {
      try store.write(next, name: "library")
      library = next; error = nil; status = message
      return true
    } catch {
      self.error = "Couldn’t save collections. Your last saved changes are intact. Check available disk space and try again."
      return false
    }
  }
  @discardableResult func create(_ value: String) -> UUID? {
    guard let name = library.validName(value) else {
      error = "Use a unique collection name between 1 and 40 characters."; return nil
    }
    let collection = SongCollection(name: name)
    return update("Created \(name).", { $0.collections.append(collection) }) ? collection.id : nil
  }
  @discardableResult func rename(_ id: UUID, to value: String) -> Bool {
    guard let name = library.validName(value, excluding: id) else {
      error = "Use a unique collection name between 1 and 40 characters."; return false
    }
    return update("Renamed collection to \(name).") { library in
      guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
      library.collections[index].name = name
    }
  }
  func setMembership(_ included: Bool, track: Track, collection: SongCollection) {
    update(included ? "Saved \(track.title) to \(collection.name)." : "Removed \(track.title) from \(collection.name).") {
      $0.setMembership(included, track: track, collectionID: collection.id)
    }
  }
  /// Playback and color editors must resolve the same scope. Editing an active
  /// collection changes that collection; songs without one keep using their default/scene.
  func colorSelection(for track: Track?, fallback: Binding<String>) -> Binding<String> {
    Binding(get: { self.library.color(for: track) ?? fallback.wrappedValue }, set: { value in
      if let track, let collection = self.library.colorCollection(for: track), collection.lyricColor != nil {
        self.setColor(value, for: collection.id)
      } else {
        fallback.wrappedValue = value
      }
    })
  }
  func setColor(_ color: String?, for id: UUID) {
    update("Collection lyric color saved.") { library in
      guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
      library.collections[index].lyricColor = color
    }
  }
}

struct SongCollectionsView: View {
  @Environment(\.renderBudget) private var budget
  @Environment(\.renderActive) private var active
  @ObservedObject var model: DisplayModel
  @ObservedObject var collections: SongCollections = .shared
  @Binding var presented: DisplayPanels.Panel?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("afterglow.tint") private var tintName = Tint.album.rawValue
  @AppStorage("afterglow.motion") private var motion = true
  @AppStorage("afterglow.estimatedWords") private var estimatedWords = true
  @AppStorage("afterglow.chorusMemory") private var chorusMemory = true
  @State private var selectedID: UUID?
  @State private var deleting: SongCollection?
  @State private var hoveredID: UUID?
  @State private var showCreate = false
  @State private var showRename = false

  private var selected: SongCollection? {
    collections.library.collections.first { $0.id == selectedID }
  }
  private var albumColor: Color {
    model.albumColor.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Tint.rose.color
  }
  private var previewColor: Color {
    Tint.resolve(selected?.lyricColor ?? tintName, albumColor: albumColor)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Your collections").font(.system(size: 24, weight: .semibold))
          Text("The songs you keep. The colors they come home to.")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        Text("afterglow").font(.system(size: 20, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)
      }
      ScrollView {
        HStack(alignment: .top, spacing: 24) {
          sidebar.frame(width: 256)
          VStack(alignment: .leading, spacing: 18) {
            if let selected {
              collectionEditor(selected)
            } else {
              VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "square.stack").font(.system(size: 30, weight: .ultraLight))
                  .foregroundStyle(previewColor).accessibilityHidden(true)
                Text("Make room for your favorites").font(.system(size: 20, weight: .medium))
                Text("Create a collection, save a song, then choose a color that feels right.")
                  .font(.system(size: 12)).foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }.padding(.top, 18)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.bottom, 8)
      }
      Divider().overlay(.white.opacity(0.08))
      HStack(spacing: 12) {
        if let error = collections.error {
          Text(error).font(.system(size: 11)).foregroundStyle(Theme.amber)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Save error. \(error)")
        } else if collections.status != "Changes save on this Mac." {
          Text(collections.status).font(.system(size: 11)).foregroundStyle(.secondary)
            .lineLimit(2).accessibilityLabel("Save status. \(collections.status)")
        }
        Spacer(minLength: 12)
        Button("Done") { presented = nil }.keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent).tint(Color.accentColor)
      }.frame(minHeight: 28)
    }
    .font(.system(size: 13)).padding(24).frame(width: 800, height: 700)
    .background(AppearanceNightSky(tint: previewColor)).preferredColorScheme(.dark)
    .buttonStyle(.bordered).tint(.white)
    .onAppear {
      if selectedID == nil {
        selectedID = model.track.flatMap { collections.library.colorCollection(for: $0)?.id }
          ?? collections.library.collections.first(where: { !$0.songs.isEmpty })?.id
          ?? collections.library.collections.first?.id
      }
    }
    .onChange(of: selectedID) { _, _ in showRename = false }
    .onExitCommand { presented = nil }
    .confirmationDialog("Delete \(deleting?.name ?? "collection")?", isPresented: Binding(
      get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
        Button("Delete collection", role: .destructive) {
          guard let deleting else { return }
          if collections.update("Deleted \(deleting.name).", { $0.removeCollection(deleting.id) }) {
            selectedID = collections.library.collections.first?.id
          }
          self.deleting = nil
        }
        Button("Cancel", role: .cancel) { deleting = nil }
      } message: { Text("Its saved songs and color will be removed from this collection. Your music and other collections stay available.") }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 18) {
      colorPreview
      HStack {
        Text("Collections").fontWeight(.semibold)
        Spacer()
        Button { showCreate = true } label: { Image(systemName: "plus") }
          .accessibilityLabel("Create collection").help("Create collection")
          .popover(isPresented: $showCreate) {
            CollectionNameEditor(title: "New collection", initialName: "", tint: previewColor,
              validate: { collections.library.validName($0) != nil },
              commit: { name in
                guard let id = collections.create(name) else { return false }
                selectedID = id; return true
              }, close: { showCreate = false })
          }
      }
      if collections.library.collections.isEmpty {
        Text("No collections yet. Use + to create your first.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(spacing: 4) {
            ForEach(collections.library.collections) { collection in
              collectionRow(collection)
            }
          }
        }.frame(height: min(160, Double(collections.library.collections.count) * 42))
      }
      if let track = model.track, !collections.library.collections.isEmpty {
        Divider()
        Menu("Save song to…") {
          ForEach(collections.library.collections) { collection in
            Toggle(collection.name, isOn: Binding(get: { collection.contains(track) },
              set: { collections.setMembership($0, track: track, collection: collection) }))
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
        let memberships = collections.library.collections.filter { $0.contains(track) }
        if !memberships.isEmpty {
          Picker("Color from", selection: Binding(
            get: { collections.library.colorSources[RecordingIdentity.key(track)] },
            set: { id in collections.update("Song color preference saved.") {
              $0.colorSources[RecordingIdentity.key(track)] = id
            } })) {
              Text("Automatic").tag(nil as UUID?)
              ForEach(memberships) { Text($0.name).tag(Optional($0.id)) }
            }.pickerStyle(.menu)
            .help("Automatic uses the first collection with a lyric color.")
        }
      }
    }
  }

  private func collectionRow(_ collection: SongCollection) -> some View {
    Button { selectedID = collection.id } label: {
      HStack(spacing: 10) {
        Image(systemName: collection.id == selectedID ? "square.stack.fill" : "square.stack")
          .foregroundStyle(Tint.resolve(collection.lyricColor ?? tintName, albumColor: albumColor))
          .frame(width: 18)
        Text(collection.name).lineLimit(1)
        Spacer(minLength: 4)
        Text("\(collection.songs.count)").font(.system(size: 11)).foregroundStyle(.secondary)
        if collection.id == selectedID {
          Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
        }
      }.padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(.white.opacity(collection.id == selectedID ? 0.12 : hoveredID == collection.id ? 0.08 : 0.035),
          in: RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }.buttonStyle(.plain).help(collection.name)
      .onHover { hoveredID = $0 ? collection.id : nil }
      .accessibilityLabel("\(collection.name), \(collection.songs.count) songs")
      .accessibilityAddTraits(collection.id == selectedID ? [.isSelected] : [])
  }

  private var colorPreview: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("COLOR PREVIEW").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        Spacer()
        Image(systemName: "waveform").font(.system(size: 11))
      }.foregroundStyle(.white.opacity(0.65))
      if let track = model.track {
        TimelineView(.animation(minimumInterval: budget.previewInterval, paused: !model.playing || !active)) { timeline in
          Constellation(lines: model.lines, position: model.position() - model.timingDelay,
            duration: track.duration, tint: previewColor, reduceMotion: reduceMotion || !motion,
            estimatedWords: estimatedWords, beatFrame: .silent, liveBeats: false,
            playing: model.playing, chorusMemory: chorusMemory ? model.chorusMemory : nil)
            .frame(width: 640, height: 300)
            .scaleEffect(0.35, anchor: .topLeading)
            .frame(width: 224, height: 105, alignment: .topLeading)
            .environment(\.parentRenderTick, timeline.date)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
          Text("Current song · selected collection color")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "music.note").font(.system(size: 26, weight: .ultraLight))
            .foregroundStyle(previewColor).accessibilityHidden(true)
          Text("Play a song to preview its lyrics.")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
      }
    }.padding(16).frame(width: 256, alignment: .leading)
      .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
  }

  private func collectionEditor(_ collection: SongCollection) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(collection.name).font(.system(size: 20, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
          Text("\(collection.songs.count) \(collection.songs.count == 1 ? "song" : "songs") · Saved on this Mac")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Rename") { showRename = true }
          .popover(isPresented: $showRename) {
            CollectionNameEditor(title: "Rename collection", initialName: collection.name, tint: previewColor,
              validate: { collections.library.validName($0, excluding: collection.id) != nil },
              commit: { collections.rename(collection.id, to: $0) }, close: { showRename = false })
          }
      }
      HStack {
        Text("Collection lyric color").fontWeight(.medium)
        Spacer()
        Toggle("Collection lyric color", isOn: Binding(get: { collection.lyricColor != nil },
          set: { collections.setColor($0 ? Tint.rose.rawValue : nil, for: collection.id) }))
          .labelsHidden().toggleStyle(.switch).tint(Color.accentColor)
      }
      if collection.lyricColor != nil {
        GlowColorSelector(selection: colorBinding(collection), albumColor: albumColor,
          albumImage: model.albumImage, artworkStatus: model.artworkStatus, layout: .collection)
      } else {
        Text("Songs use their saved scene or your default color. Turn this on to give this collection its own.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      HStack {
        Text("Saved songs").fontWeight(.semibold)
        Spacer()
        if let track = model.track {
          Button(collection.contains(track) ? "Remove current song" : "Save current song") {
            collections.setMembership(!collection.contains(track), track: track, collection: collection)
          }
        }
      }
      if collection.songs.isEmpty {
        Text(model.track == nil ? "Play a song, then save it here." : "Save the current song to start this collection.")
          .font(.system(size: 12)).foregroundStyle(.secondary)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(collection.songs, id: \.collectionKey) { track in
            HStack(spacing: 12) {
              Image(systemName: "music.note").foregroundStyle(previewColor).frame(width: 20)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                  .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
              }
              Spacer(minLength: 4)
              Button { collections.setMembership(false, track: track, collection: collection) } label: {
                Image(systemName: "minus.circle").frame(width: 24, height: 24)
              }.buttonStyle(.borderless)
                .accessibilityLabel("Remove \(track.title) from \(collection.name)").help("Remove song from collection")
            }.padding(.vertical, 12)
            Divider().opacity(0.5)
          }
        }
      }
      Button("Delete collection…", role: .destructive) { deleting = collection }
        .font(.system(size: 11)).padding(.top, 4)
    }
  }
  private func colorBinding(_ collection: SongCollection) -> Binding<String> {
    Binding(get: {
      collections.library.collections.first { $0.id == collection.id }?.lyricColor ?? Tint.rose.rawValue
    }, set: { collections.setColor($0, for: collection.id) })
  }
}

private struct CollectionNameEditor: View {
  let title: String
  let initialName: String
  let tint: Color
  let validate: (String) -> Bool
  let commit: (String) -> Bool
  let close: () -> Void
  @State private var name = ""
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(.system(size: 18, weight: .semibold))
      TextField("Collection name", text: $name).textFieldStyle(.roundedBorder)
        .accessibilityLabel("Collection name").focused($focused).onSubmit { save() }
      Text(!name.isEmpty && !validate(name) ? "Use a unique name between 1 and 40 characters." : "Choose a name for the songs you keep together.")
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true).frame(minHeight: 28, alignment: .top)
      HStack {
        Button("Cancel", action: close).keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!validate(name))
          .buttonStyle(.borderedProminent).tint(Color.accentColor)
      }
    }.padding(22).frame(width: 320)
      .background(AppearanceNightSky(tint: tint)).preferredColorScheme(.dark)
      .onAppear { name = initialName; focused = true }
  }
  private func save() { if validate(name), commit(name) { close() } }
}

private extension Track {
  var collectionKey: String { RecordingIdentity.key(self) }
}

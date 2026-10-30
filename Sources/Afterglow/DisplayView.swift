import AfterglowCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DisplayView: View {
  @ObservedObject var model: DisplayModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("afterglow.tint") private var tintName = Tint.album.rawValue
  @AppStorage("afterglow.clock") private var showClock = true
  @AppStorage("afterglow.motion") private var motion = true
  @AppStorage("afterglow.estimatedWords") private var estimatedWords = true
  @State private var showDock = false
  @State private var showTiming = false
  @State private var showBeats = false
  @State private var showImporter = false
  @State private var importTrack: Track?
  @AppStorage("afterglow.timedFallback") private var timedFallback = true
  @AppStorage("afterglow.plainFallback") private var plainFallback = true
  @ObservedObject var beats: BeatCapture
  @ObservedObject var desktop: DesktopMode
  @ObservedObject var panels: DisplayPanels
  @ObservedObject var appearance: WallpaperAppearance
  @AppStorage("afterglow.backgroundOpacity") private var backgroundOpacity = 0.15
  @AppStorage("afterglow.marker") private var markerName = LyricMarker.diamond.rawValue
  @AppStorage("afterglow.markerEmoji") private var markerEmoji = "✨"
  private var tint: Color {
    if tintName == Tint.album.rawValue, let color = model.albumColor {
      return Color(red: color.red, green: color.green, blue: color.blue)
    }
    return (Tint(rawValue: tintName) ?? .album).color
  }

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.periodic(from: .now, by: model.playing && desktop.isVisible ? 1.0 / 30 : 0.5)) {
        timeline in
        let position = model.position()
        ZStack {
          WallpaperBackground(image: appearance.image, opacity: backgroundOpacity).ignoresSafeArea()
          GlowFrame(
            tint: tint, active: model.playing && desktop.isVisible,
            energy: beats.running ? beats.frame.level : 0,
            pulse: beats.running ? beats.frame.pulse : 0,
            reduceMotion: reduceMotion || !motion)
          VStack(spacing: 0) {
            header(date: timeline.date)
            Spacer(minLength: 8)
            if model.connected {
              performance(position: position, size: geometry.size)
                .opacity(desktop.isQuiet && !model.playing ? 0.22 : 1)
                .overlay(alignment: .bottom) {
                  if model.lines.isEmpty, model.lyricDocument?.instrumental != true {
                    missingLyricStatus
                  }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: model.playing)
            } else if desktop.isQuiet {
              Text("Choose a music player from the Afterglow menu.")
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(Theme.secondary)
            } else {
              ScrollView {
                onboarding.frame(maxWidth: .infinity)
              }
              .scrollBounceBehavior(.basedOnSize)
            }
            Spacer(minLength: 8)
            footer(position: position, width: geometry.size.width)
          }
          .padding(.horizontal, max(32, geometry.size.width * 0.028))
          .padding(.top, desktop.isQuiet ? 54 : 26)
          .padding(.bottom, 35)
        }
      }
    }
    .foregroundStyle(Theme.text)
    .tint(tint)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: tint)
    .onAppear {
      if !UserDefaults.standard.bool(forKey: "afterglow.v2121.wordProgressionRestored") {
        estimatedWords = true
        UserDefaults.standard.set(true, forKey: "afterglow.v2121.wordProgressionRestored")
      }
      if !UserDefaults.standard.bool(forKey: "afterglow.v2.albumDefaultApplied") {
        tintName = Tint.album.rawValue
        UserDefaults.standard.set(true, forKey: "afterglow.v2.albumDefaultApplied")
      }
    }
    .onChange(of: desktop.isQuiet) { _, enabled in
      if enabled {
        showDock = false
        showTiming = false
        showBeats = false
        panels.presented = nil
      }
    }
    .onChange(of: model.source) { _, _ in
      beats.stop()
      showTiming = false
    }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
    ) { _ in beats.stop() }
    .onDisappear { beats.stop() }
    .sheet(item: $panels.presented) { panel in
      switch panel {
      case .library: libraryView
      case .timing: timingControls
      case .beats: beatControls
      case .wallpaper: WallpaperSettings(appearance: appearance, tint: tint, presented: $panels.presented)
      }
    }
    .onExitCommand {
      if desktop.isFocused { desktop.exitFocus() } else { DisplayWindow.exitFullScreen() }
    }
    .overlay(alignment: .topTrailing) {
      if desktop.isFocused {
        Button {
          desktop.exitFocus()
        } label: {
          Label("Exit Focus", systemImage: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.panel, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Return to your previous view (Escape)")
        .disabled(desktop.isTransitioning)
        .padding(.top, 28).padding(.trailing, 32)
      }
    }
  }

  private var missingLyricStatus: some View {
    Text(model.track == nil ? "Waiting for music…"
      : model.loading ? "Finding lyrics…" : "Lyrics not found")
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(Theme.secondary)
      .padding(.horizontal, 14).padding(.vertical, 8)
      .background(Theme.panel.opacity(0.9), in: Capsule())
      .padding(.horizontal, 20)
      .help(model.message)
  }

  private func header(date: Date) -> some View {
    HStack(alignment: .top) {
      if !desktop.isQuiet {
        Text("afterglow").font(.system(size: 17, weight: .medium, design: .rounded)).tracking(1)
          .foregroundStyle(tint)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
      }
      VStack(spacing: 4) {
        if showClock {
          Text(date, format: .dateTime.hour().minute())
            .font(.system(size: 29, weight: .ultraLight, design: .rounded)).monospacedDigit()
          Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
            .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.secondary)
        }
      }.frame(height: 52)
      if !desktop.isQuiet {
        HStack(spacing: 10) {
          Button {
            desktop.toggleFocus()
          } label: {
            Image(systemName: "viewfinder").frame(width: 32, height: 32)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Focus Mode — Hide Widgets and Stage Manager")
          .help("Focus Mode: hide desktop widgets and Stage Manager (⇧⌘F, global by default)")
          if model.isDemo {
            Text("DEMO").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(tint)
          }
          Menu {
            Button("Wallpaper & lyric markers…") { panels.presented = .wallpaper }
            Picker("Glow color", selection: $tintName) {
              ForEach(Tint.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            if tintName == Tint.album.rawValue { Text(model.artworkStatus) }
            Button("Beat sync…") {
              showBeats = true
              showDock = true
            }
            Button("Focus Mode — Hide Widgets & Stage Manager", systemImage: "viewfinder") {
              desktop.toggleFocus()
            }
            Button("Lyric library…") { panels.presented = .library }
            Toggle("Show clock", isOn: $showClock)
            Toggle("Animate word changes", isOn: $motion)
            Toggle("Estimate words when timestamps are missing", isOn: $estimatedWords)
            Divider()
            Text("Real word timestamps are used when available.")
            Text("Word-by-word progression is enabled by default.")
            Text("Lyrics: LRCLIB; optional Karalyr and lyrics.ovh backups.")
          } label: {
            Image(systemName: "slider.horizontal.3").frame(width: 32, height: 32)
          }
          .menuStyle(.borderlessButton).fixedSize()
          .accessibilityLabel("Display settings").help("Display settings")
        }.frame(maxWidth: .infinity, alignment: .trailing)
      } else {
        Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
      }
    }
    .frame(height: 52)
  }

  private var onboarding: some View {
    VStack(spacing: 24) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.system(size: 50, weight: .ultraLight)).foregroundStyle(tint)
        .shadow(color: tint.opacity(0.5), radius: 25)
        .accessibilityHidden(true)
      VStack(spacing: 12) {
        Text("A constellation\nfor every song.")
          .font(.system(size: 48, weight: .light, design: .rounded))
          .multilineTextAlignment(.center)
        Text("Your music. A quiet screen. Words that find each other.")
          .font(.system(size: 14)).foregroundStyle(Theme.secondary)
      }
      HStack(spacing: 12) {
        Button("Connect Spotify") { model.connect(.spotify) }
        Button("Connect Apple Music") { model.connect(.music) }
      }
      .buttonStyle(GlowButtonStyle(tint: tint))
      Button("Try the demo", systemImage: "play.fill") { model.demo() }
        .buttonStyle(.plain).foregroundStyle(tint)
        .help("Preview with original sample words, without connecting a player")
      VStack(spacing: 5) {
        Text("macOS will ask to read your selected player.")
        Text("Track details go to LRCLIB and optionally Karalyr; lyrics.ovh can provide untimed text.")
      }
      .font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
      if let error = model.error {
        Text(error).font(.system(size: 12)).foregroundStyle(Theme.amber)
          .multilineTextAlignment(.center).frame(maxWidth: 520)
          .accessibilityLabel("Connection issue. \(error)")
      }
    }
    .padding(.vertical, 18)
  }

  private func performance(position: Double, size: CGSize) -> some View {
    VStack(spacing: 16) {
      if !model.lines.isEmpty {
        let lyricPosition = position - model.timingDelay
        Constellation(
          lines: model.lines, position: lyricPosition, duration: model.track?.duration ?? 0,
          tint: tint, reduceMotion: reduceMotion || !motion, estimatedWords: estimatedWords,
          beatFrame: beats.frame, liveBeats: beats.running,
          playing: model.playing && desktop.isVisible,
          waveWidth: size.width, marker: LyricMarker(rawValue: markerName) ?? .diamond,
          markerEmoji: markerEmoji
        )
        .frame(
          width: min(1000, size.width - max(64, size.width * 0.18)),
          height: max(180, min(440, size.height * 0.48)))
        // Preserve the constellation's position without a repeated lyric caption.
        Color.clear.frame(height: 38).accessibilityHidden(true)
      } else {
        // The same audio-reactive visualizer stays on screen while lyrics are
        // loading, unavailable, or genuinely instrumental, in every display mode.
        InstrumentalView(
          frame: beats.frame, live: beats.running, playing: model.playing && desktop.isVisible,
          tint: tint, reduceMotion: reduceMotion || !motion
        )
        .frame(width: size.width, height: max(180, min(440, size.height * 0.48)) + 54)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func footer(position: Double, width: Double) -> some View {
    VStack(spacing: 18) {
      if let track = model.track {
        VStack(spacing: 7) {
          Text(track.title).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
            .lineLimit(1)
          Text(track.artist).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
          HStack(spacing: 10) {
            Text(time(position)).frame(width: 36, alignment: .trailing)
            GeometryReader { g in
              ZStack(alignment: .leading) {
                Capsule().fill(Theme.text.opacity(0.08))
                Capsule().fill(tint.opacity(0.7))
                  .frame(width: g.size.width * min(1, position / max(1, track.duration)))
              }
            }.frame(width: 180, height: 2).accessibilityHidden(true)
            Text(time(track.duration)).frame(width: 36, alignment: .leading)
          }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
        }
        .frame(height: 68)
        .accessibilityElement(children: .combine)
      }
      if !desktop.isQuiet {
        HStack {
          Button {
            showDock.toggle()
          } label: {
            Image(systemName: "slider.horizontal.3")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(tint)
              .frame(width: 38, height: 38)
              .background(Theme.panel.opacity(0.8), in: Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Show playback controls")
          .help("Show playback controls (⌘K)")
          .keyboardShortcut("k", modifiers: .command)
          .popover(isPresented: $showDock, arrowEdge: .bottom) {
            Group {
              if showBeats {
                beatControls
              } else if showTiming {
                timingControls
              } else {
                ScrollView(.horizontal) { playbackDock(width: width) }
                  .scrollIndicators(.visible)
                  .frame(
                    width: min(width - 64, width > 1000 ? 780 : 670),
                    height: Theme.controlHeight + 4
                  )
                  .padding(8)
              }
            }
            .tint(tint)
          }
          Spacer(minLength: 0)
        }
        .frame(height: Theme.controlHeight)
      }
      if !desktop.isQuiet {
        if let error = model.controlError {
          Text(error).font(.system(size: 11)).foregroundStyle(Theme.amber)
            .multilineTextAlignment(.center).frame(maxWidth: 600)
            .accessibilityLabel("Playback control issue. \(error)")
        }
        Group {
          if model.isDemo {
            Text("Original sample words · no audio plays in demo")
          } else if !model.connected {
            Text("Made for your Mac · no account · no downloaded helpers")
          } else {
            Color.clear.frame(height: 12).accessibilityHidden(true)
          }
        }
        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
      }
    }
    .opacity(desktop.isQuiet && !model.playing ? 0.35 : 1)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: model.playing)
    .onChange(of: showDock) { _, visible in
      if !visible {
        showTiming = false
        showBeats = false
      }
    }
  }

  private func playbackDock(width: Double) -> some View {
    HStack(spacing: 12) {
      if model.connected {
        if model.isDemo {
          Button(
            model.playing ? "Pause demo" : "Resume demo",
            systemImage: model.playing ? "pause.fill" : "play.fill"
          ) { model.toggleDemo() }
        } else {
          Button {
            model.transport(.previous)
          } label: {
            Image(systemName: "backward.end.fill").frame(width: 24, height: 26)
          }.accessibilityLabel("Previous track").help("Previous track")
          Button {
            model.transport(.togglePlayPause)
          } label: {
            Image(systemName: model.playing ? "pause.fill" : "play.fill").frame(
              width: 24, height: 26)
          }.accessibilityLabel(model.playing ? "Pause" : "Play").help(
            model.playing ? "Pause" : "Play")
          Button {
            model.transport(.stop)
          } label: {
            Image(systemName: "stop.fill").frame(width: 24, height: 26)
          }.accessibilityLabel("Stop playback").help(
            "Stop playback (Spotify: pause and return to the beginning)")
          Button {
            model.transport(.next)
          } label: {
            Image(systemName: "forward.end.fill").frame(width: 24, height: 26)
          }.accessibilityLabel("Next track").help("Next track")
          Divider().frame(height: 14)
          if width > 1000 {
            Label(
              model.playing ? (model.source?.rawValue ?? "Playing") : "Paused",
              systemImage: model.playing ? "waveform" : "pause.fill"
            )
            .foregroundStyle(Theme.secondary)
          }
        }
        Button(model.isDemo ? "Leave demo" : "Disconnect", systemImage: "xmark") {
          model.disconnect()
        }
        if !model.isDemo, model.track != nil {
          Button("Timing", systemImage: "slider.horizontal.3") { showTiming.toggle() }
        }
        if !model.isDemo {
          Button {
            showDock = false
            panels.presented = .library
          } label: {
            Image(systemName: "text.book.closed").frame(width: 24, height: 26)
          }.accessibilityLabel("Lyric library").help("Lyric sources, reader and local imports")
          Button {
            showBeats = true
          } label: {
            Image(systemName: beats.running ? "waveform.circle.fill" : "waveform.circle").frame(
              width: 24, height: 26)
          }
          .accessibilityLabel("Beat sync").help(beats.state)
        }
        Divider().frame(height: 14)
      }
      Button {
        showDock = false
      } label: {
        Image(systemName: "chevron.down").frame(width: 24, height: 26)
      }.accessibilityLabel("Hide playback controls").help("Hide playback controls")
      Button("Focus Mode", systemImage: "viewfinder") {
        showDock = false
        desktop.toggleFocus()
      }
      .help("Hide widgets and Stage Manager in a clean full-screen view. Escape returns.")
      Button("Desktop Mode", systemImage: "desktopcomputer") {
        showDock = false
        desktop.toggle()
      }
      .help("Show Afterglow as your desktop wallpaper. Controls move to the menu bar.")
      Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") {
        DisplayWindow.toggleFullScreen()
      }
      .keyboardShortcut("f", modifiers: .command)
      .help("Enter or exit full screen (⌘F). Escape exits full screen.")
    }
    .font(.system(size: 11))
    .buttonStyle(.borderless)
    .padding(.horizontal, 18).frame(height: Theme.controlHeight)
    .background(Theme.panel.opacity(0.8), in: Capsule())
  }

  private var beatControls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Beat sync", systemImage: "waveform.path").font(.headline)
      Text(beats.state).font(.system(size: 12)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        "React to the selected music player's audio. Audio is analyzed on this Mac, never saved or uploaded. The microphone is never used."
      )
      .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
      Text(
        "macOS may ask for Screen & System Audio Recording permission. Afterglow requests only audio samples from your player, not screen frames."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Text(
        "Your lyric words and connecting graph stay unchanged. Album-colored curves appear only in timed instrumental gaps or tracks marked instrumental. With audio sync off they move at an ambient pace. Pausing freezes the visualizer."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if model.source == nil {
        Text("Connect Spotify or Apple Music before enabling beat sync.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if beats.permissionRequired {
        Button("Open System Settings…") { beats.openPermissionSettings() }
      }
      HStack {
        if beats.running || beats.starting {
          Button("Disable beat sync") { beats.stop() }
        } else {
          Button("Enable beat sync") {
            guard let source = model.source else { return }
            Task { await beats.start(source: source) }
          }.disabled(model.source == nil)
        }
        Spacer()
        Button("Done") { showBeats = false; panels.presented = nil }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(22).frame(width: 380)
  }

  private var libraryView: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Lyric library").font(.title2)
          Text(
            model.track.map {
              "\($0.title) · \(Int($0.duration) / 60):\(String(format: "%02d", Int($0.duration) % 60))"
            } ?? "Connect a player first"
          ).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done") { panels.presented = nil }.keyboardShortcut(.defaultAction)
      }
      if let document = model.lyricDocument {
        HStack {
          Text(
            "\(document.source.name) · \(document.timed ? model.timingDescription : "Untimed text")"
          )
          Spacer()
          if document.source == .lyricsOVH {
            Link("lyrics.ovh", destination: URL(string: "https://lyrics.ovh")!)
          }
          if document.source == .karalyr {
            Link("Karalyr", destination: URL(string: "https://karalyr.com")!)
          }
          if document.source == .lrclib {
            Link("LRCLIB", destination: URL(string: "https://lrclib.net")!)
          }
        }.font(.caption)
      }
      Toggle("Try Karalyr when LRCLIB has no synced lyrics", isOn: $timedFallback)
      Toggle("Try lyrics.ovh when no lyric text is found", isOn: $plainFallback)
      Text(
        "LRCLIB receives title, artist, album and duration. Karalyr receives title, artist and duration when synced lyrics are missing. lyrics.ovh receives only title and artist; its untimed text appears only in this reader."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Import LRC, Lyricsfile or text…") {
          importTrack = model.track
          showImporter = true
        }.disabled(model.track == nil || model.isDemo)
        if model.lyricDocument?.source == .local || model.lyricDocument?.manualMatch == true {
          Button("Use online lyrics") { model.useOnlineLyrics() }
        } else {
          Button("Retry online sources") { model.retryLyrics() }.disabled(
            model.track == nil || model.isDemo)
        }
      }
      Text(
        "Imports and chosen versions stay on this Mac. Successful lookups are cached across launches; retry refreshes them. Original files remain unchanged."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let error = model.libraryError { Text(error).foregroundStyle(Theme.amber).font(.caption) }
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let alternatives = model.lyricDocument?.alternatives, !alternatives.isEmpty,
            let target = model.track
          {
            Text("Other timed versions").font(.headline)
            Text(
              "These match the title and artist but may be a different recording. Compare the duration and preview before choosing. Timing may drift; it is never stretched automatically."
            )
            .font(.caption).foregroundStyle(.secondary)
            ForEach(alternatives) { alternative in
              DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                  Text(alternative.lines.prefix(3).map(\.text).joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.secondary)
                  Button("Use this timing for this song") {
                    model.selectAlternative(alternative, for: target)
                  }
                }.padding(.vertical, 8)
              } label: {
                Text(
                  "\(alternative.album) · \(Int(alternative.duration) / 60):\(String(format: "%02d", Int(alternative.duration) % 60)) · \(String(format: "%+.0f", alternative.duration - target.duration))s"
                )
                .font(.callout)
              }
            }
            Divider()
          }
          Text(
            model.lyricDocument?.plainText
              ?? (model.lines.isEmpty
                ? "No lyric text available yet. Try the sources again or import your own file."
                : model.lines.map(\.text).joined(separator: "\n"))
          )
          .font(.system(size: 16)).lineSpacing(7).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        }
      }
    }
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
      guard case .success(let url) = result, let target = importTrack else { return }
      model.importLyrics(from: url, for: target)
    }
    .padding(26).frame(
      minWidth: 540, idealWidth: 620, maxWidth: 680, minHeight: 460, idealHeight: 570
    )
    .tint(tint)
  }

  private var timingControls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Lyric timing").font(.headline)
      Text(model.timingDescription).font(.subheadline).foregroundStyle(.secondary)
      Text("Lyrics late? Move them earlier. This adjustment is saved for this recording.")
        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Earlier", systemImage: "backward.end") {
          model.setTimingDelay(model.timingDelay - 0.1)
        }
        .disabled(model.timingDelay <= -5)
        Spacer()
        Text(String(format: "%+.2f s", model.timingDelay)).monospacedDigit()
        Spacer()
        Button("Later", systemImage: "forward.end") {
          model.setTimingDelay(model.timingDelay + 0.1)
        }
        .disabled(model.timingDelay >= 5)
      }
      Slider(
        value: Binding(get: { model.timingDelay }, set: { model.setTimingDelay($0) }), in: -5...5,
        step: 0.05
      ) {
        Text("Lyric timing adjustment")
      }
      HStack {
        Text("Earlier")
        Spacer()
        Text("Later")
      }.font(.caption).foregroundStyle(.secondary)
      Divider()
      Toggle("Estimate missing word timings", isOn: $estimatedWords)
      Text(
        "Off: highlight the synced line. On: guess word emphasis; this may differ from the vocals."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Reset timing") { model.setTimingDelay(0) }
        Spacer()
        Button("Done") { showTiming = false; panels.presented = nil }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(22).frame(width: 380)
  }

  private func time(_ value: Double) -> String {
    let total = max(0, Int(value))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

private struct GlowButtonStyle: ButtonStyle {
  let tint: Color
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 18).frame(height: Theme.controlHeight)
      .background(
        tint.opacity(configuration.isPressed ? 0.25 : 0.10), in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.35), lineWidth: 0.7))
      .contentShape(RoundedRectangle(cornerRadius: 9))
  }
}

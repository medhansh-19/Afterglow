import SwiftUI

/// A quiet first-run sky. Player connection and demo behavior stay owned by DisplayModel.
struct WelcomeView: View {
  let error: String?
  let connect: (PlayerSource) -> Void
  let demo: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("afterglow.motion") private var motion = true
  @State private var appeared = false

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        WelcomeNightSky()
          .opacity(appeared ? 1 : 0)
          .animation(animateEntrance ? .easeOut(duration: 1.5) : nil, value: appeared)
        GlowFrame(appearance: .welcome, tint: Theme.rose,
          active: scenePhase == .active,
          reduceMotion: reduceMotion || !motion)
          .opacity(appeared ? 1 : 0)
          .animation(animateEntrance ? .easeInOut(duration: 1.8) : nil, value: appeared)
        ScrollView {
          VStack(spacing: 0) {
            Spacer(minLength: 60)
            VStack(spacing: 0) {
              Text("afterglow")
                .font(.system(size: 46, weight: .ultraLight, design: .rounded))
                .tracking(3)
                .accessibilityAddTraits(.isHeader)
              Text("Your music. Your words. Your space.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.welcomeSecondary)
                .padding(.top, 17)

              HStack(spacing: 12) {
                Button { connect(.spotify) } label: {
                  Text("Connect Spotify").frame(maxWidth: .infinity)
                }
                .buttonStyle(WelcomeButtonStyle(primary: true))
                Button { connect(.music) } label: {
                  Text("Apple Music").frame(maxWidth: .infinity)
                }
                .buttonStyle(WelcomeButtonStyle(primary: false))
                .accessibilityLabel("Connect Apple Music")
              }
              .padding(.top, 38)

              Button("Try the demo", action: demo)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.welcomeSecondary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
                .help("Try sample lyrics without connecting a player.")
                .padding(.top, 12)

              // Keep the actions in place when a connection fails.
              Text(error.map { "Connection issue: \($0)" } ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(Theme.amber)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .top)
                .padding(.top, 12)
                .accessibilityHidden(error == nil)
            }
            .frame(maxWidth: 340)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || !animateEntrance ? 0 : 7)
            .animation(animateEntrance ? .easeOut(duration: 1.0).delay(0.25) : nil,
              value: appeared)
            Spacer(minLength: 60)
            Text("macOS will ask for access to your player.\nTrack details are sent to enabled lyric services, including NetEase, to find lyrics.")
              .font(.system(size: 10))
              .lineSpacing(4)
              .multilineTextAlignment(.center)
              .foregroundStyle(Theme.welcomeSecondary)
              .frame(maxWidth: 380)
              .opacity(appeared ? 1 : 0)
              .animation(animateEntrance ? .easeOut(duration: 1.0).delay(0.45) : nil,
                value: appeared)
          }
          .padding(.horizontal, 32)
          .padding(.top, 44)
          .padding(.bottom, 28)
          .frame(minHeight: geometry.size.height)
          .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
    }
    .foregroundStyle(Theme.welcomeText)
    .onAppear { appeared = true }
  }

  private var animateEntrance: Bool { !reduceMotion && motion }
}

/// Stationary pinpoints with independent, slow changes in brightness. No connecting lines.
private struct WelcomeNightSky: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("afterglow.motion") private var motion = true

  private struct Star {
    let x: Double
    let y: Double
    let diameter: Double
    let brightness: Double
    let phase: Double
    let period: Double
  }

  // Seeded once, so redraws and window resizing never shuffle the sky.
  private static let stars: [Star] = {
    var seed: UInt64 = 0xAF7E_6100
    func random() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
    return (0..<250).map { _ in
      Star(x: random(), y: random(), diameter: 0.85 + pow(random(), 3) * 1.25,
        brightness: 0.42 + random() * 0.52, phase: random() * .pi * 2,
        period: 4.5 + random() * 7)
    }
  }()

  var body: some View {
    let animate = !reduceMotion && motion && scenePhase == .active
    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animate)) { timeline in
      let time = animate ? timeline.date.timeIntervalSinceReferenceDate : 0
      Canvas { context, size in
        for star in Self.stars {
          let x = star.x * size.width
          let y = star.y * size.height
          // Let the words sit in a quieter patch of sky, without a visible panel.
          let dx = (x - size.width / 2) / 235
          let dy = (y - size.height / 2) / 185
          let quietCenter = 1 - 0.65 * exp(-(dx * dx + dy * dy) * 1.6)
          let shimmer = 0.74 + 0.26 * sin(time * .pi * 2 / star.period + star.phase)
          let opacity = star.brightness * shimmer * quietCenter
          let rect = CGRect(x: x, y: y, width: star.diameter, height: star.diameter)
          if star.diameter > 1.5 {
            // Only the few brightest stars have a barely visible soft halo.
            context.fill(Path(ellipseIn: rect.insetBy(dx: -1.4, dy: -1.4)),
              with: .color(.white.opacity(opacity * 0.07)))
          }
          context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
        }
      }
    }
    .background(Theme.welcomeBackground)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct WelcomeButtonStyle: ButtonStyle {
  let primary: Bool
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 14)
      .frame(height: 44)
      .foregroundStyle(primary ? Theme.welcomeBackground : Theme.welcomeText)
      .background {
        RoundedRectangle(cornerRadius: 9)
          .fill(primary ? Theme.welcomeText : Theme.welcomeText.opacity(hovered ? 0.10 : 0.045))
      }
      .overlay {
        if !primary {
          RoundedRectangle(cornerRadius: 9)
            .stroke(Theme.welcomeText.opacity(hovered ? 0.36 : 0.22), lineWidth: 1)
        }
      }
      .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
      .brightness(hovered && primary ? -0.1 : 0)
      .contentShape(RoundedRectangle(cornerRadius: 9))
      .onHover { hovered = enabled && $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
  }
}

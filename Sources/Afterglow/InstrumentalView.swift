import AfterglowCore
import SwiftUI

/// Instrumental-only flowing curves in tonal shades of the album accent.
struct InstrumentalView: View {
  let frame: BeatFrame
  let live: Bool
  let playing: Bool
  let tint: Color
  let reduceMotion: Bool
  var visible = true
  @State private var clock = WaveRenderClock()

  var body: some View {
    TimelineView(
      .animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion || !visible)
    ) { timeline in
      let snapshot = clock.snapshot(
        frame: frame, live: live, playing: playing && visible, reducedMotion: reduceMotion)
      Canvas(rendersAsynchronously: true) { context, size in
          guard visible else { return }
        let phase = reduceMotion ? 0 : snapshot.phase
        // Opacity changes produce dark/light tones of the same hue on the black canvas.
        let gradient = Gradient(stops: [
          .init(color: tint.opacity(0.65), location: 0),
          .init(color: tint.opacity(0.82), location: 0.22),
          .init(color: tint, location: 0.5),
          .init(color: tint.opacity(0.7), location: 0.78),
          .init(color: tint.opacity(0.65), location: 1),
        ])
        let color = GraphicsContext.Shading.linearGradient(
          gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        let mesh = RibbonMesh.make(
          width: size.width, height: size.height, phase: phase,
          bands: snapshot.bands, energy: snapshot.energy, pulse: snapshot.pulse,
          live: live, reducedMotion: reduceMotion)
        for ribbon in 0..<17 {
          var path = Path()
          for (index, point) in mesh.ribbons[ribbon].enumerated() {
            let point = CGPoint(x: point.x, y: point.y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
          }
          var line = context
          line.opacity = ribbon == 8 ? 0.9 : 0.16 + Double(ribbon % 5) * 0.1
          if ribbon == 8 { line.addFilter(.shadow(color: tint.opacity(0.6), radius: 6)) }
          line.stroke(path, with: color, lineWidth: ribbon == 8 ? 1.7 : 0.8)
        }
        // Traveling highlights follow the ribbons, with tails instead of disconnected flashes.
        if !reduceMotion {
          let activity = live ? min(1, (snapshot.bands.max() ?? 0) * 1.5) : 1
          for light in 0..<5 {
            let x = (phase / (2 * .pi) + Double(light) * 0.2).truncatingRemainder(dividingBy: 1)
            let ribbon = 2 + light * 3
            for tail in stride(from: 9, through: 0, by: -1) {
              let t = x - Double(tail) * 0.0045
              guard t >= 0 else { continue }
              let point = mesh.point(at: t, ribbon: ribbon)
              let radius = tail == 0 ? 2.3 + snapshot.pulse : 1.4
              var glow = context
              glow.opacity =
                activity * pow(1 - Double(tail) / 11, 2) * min(1, min(x, 1 - x) / 0.06) * 0.8
              if tail == 0 { glow.addFilter(.shadow(color: tint, radius: 9)) }
              glow.fill(
                Path(
                  ellipseIn: CGRect(
                    x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                ), with: tail == 0 ? .color(tint) : color)
            }
          }
        }
      }
      .onChange(of: playing) { _, _ in clock.reanchor() }
      .onChange(of: visible) { _, _ in clock.reanchor() }
    }
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(live ? "Live audio tonal curves" : "Ambient tonal curves")
  }
}

/// Reference storage avoids scheduling a second SwiftUI render after each animation tick.
@MainActor
private final class WaveRenderClock {
  private var motion = WaveDynamics()
  func snapshot(frame: BeatFrame, live: Bool, playing: Bool, reducedMotion: Bool) -> WaveDynamics {
    motion.advance(
      at: ProcessInfo.processInfo.systemUptime, frame: frame, live: live,
      playing: playing, reducedMotion: reducedMotion)
    return motion
  }
  func reanchor() {
    motion.advance(
      at: ProcessInfo.processInfo.systemUptime, frame: .silent, live: false,
      playing: false, reducedMotion: false)
  }
}

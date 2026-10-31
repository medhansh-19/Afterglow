import AfterglowCore
import SwiftUI

struct GlowFrame: View {
  enum Appearance { case playback, welcome }
  var appearance: Appearance = .playback
  let tint: Color
  let active: Bool
  var energy: Double = 0
  var pulse: Double = 0
  var reduceMotion = false
  @State private var clock = BorderRenderClock()

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active || reduceMotion)) {
      timeline in
      let snapshot = clock.snapshot(
        energy: energy, pulse: pulse, active: active, reducedMotion: reduceMotion)
      GeometryReader { geometry in
        let rect = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 16, dy: 16)
        let radius = min(Theme.radius, min(rect.width, rect.height) / 2)
        let path = RoundedRectangle(cornerRadius: radius).path(in: rect)
        let perimeter = max(1, 2 * (rect.width + rect.height - 4 * radius) + 2 * .pi * radius)
        let glow = reduceMotion ? 0 : snapshot.glow
        Canvas { context, _ in
          var base = context
          base.addFilter(.shadow(color: tint.opacity(0.14 + glow * 0.12), radius: 12))
          base.stroke(
            path, with: .color(tint.opacity(active ? (appearance == .welcome ? 0.18 : 0.32) + glow * 0.16 : 0.18)), lineWidth: 1.25)
          if !reduceMotion {
            // Dashed strokes follow the rounded perimeter through corners and wrap cleanly.
            for (length, opacity, thickness) in [
              (perimeter * 0.15, 0.16, 2.6), (perimeter * 0.075, 0.30, 2.0),
              (perimeter * 0.012, 0.78, 1.7),
            ] {
              let segment = min(length, perimeter * 0.18)
              var light = context
              light.addFilter(.shadow(color: tint.opacity(0.25), radius: 6))
              light.stroke(
                path, with: .color(tint.opacity(opacity + glow * 0.06)),
                style: StrokeStyle(
                  lineWidth: thickness, lineCap: .round,
                  dash: [segment, perimeter - segment], dashPhase: -snapshot.progress * perimeter))
            }
          }
        }
      }
      .onChange(of: active) { _, _ in clock.reanchor() }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

@MainActor
private final class BorderRenderClock {
  private var motion = BorderMotion()
  func snapshot(energy: Double, pulse: Double, active: Bool, reducedMotion: Bool) -> BorderMotion {
    motion.advance(
      at: ProcessInfo.processInfo.systemUptime, energy: energy, pulse: pulse,
      playing: active, reducedMotion: reducedMotion)
    return motion
  }
  func reanchor() {
    motion.advance(
      at: ProcessInfo.processInfo.systemUptime, energy: 0, pulse: 0,
      playing: false, reducedMotion: false)
  }
}

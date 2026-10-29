import Foundation

/// Shared horizontal samples avoid repeating spectral interpolation for every ribbon.
public struct RibbonMesh: Sendable {
  public let ribbons: [[TracePoint]]

  public func point(at x: Double, ribbon: Int) -> TracePoint {
    let points = ribbons[min(ribbons.count - 1, max(0, ribbon))]
    let offset = min(1, max(0, x.isFinite ? x : 0)) * Double(points.count - 1)
    let left = Int(offset)
    let right = min(points.count - 1, left + 1)
    let fraction = offset - Double(left)
    return .init(
      x: points[left].x + (points[right].x - points[left].x) * fraction,
      y: points[left].y + (points[right].y - points[left].y) * fraction)
  }

  public static func make(
    width: Double, height: Double, phase: Double, bands: [Double],
    energy: Double, pulse: Double, live: Bool, reducedMotion: Bool
  ) -> RibbonMesh {
    let width = width.isFinite ? max(0, width) : 0
    let height = height.isFinite ? max(0, height) : 0
    let phase = phase.isFinite ? phase : 0
    let energy = energy.isFinite ? min(1, max(0, energy)) : 0
    let pulse = pulse.isFinite ? min(1, max(0, pulse)) : 0
    let steps = max(64, min(144, Int(width / 10)))
    func amplitude(_ x: Double) -> Double {
      guard !bands.isEmpty else { return 0 }
      let p = min(1, max(0, x)) * Double(bands.count - 1)
      let left = Int(p)
      let right = min(bands.count - 1, left + 1)
      func safe(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
      return safe(bands[left]) * (1 - p + Double(left)) + safe(bands[right]) * (p - Double(left))
    }
    let samples = (0...steps).map { step -> (Double, Double, Double) in
      let x = Double(step) / Double(steps)
      let local = live ? (amplitude(x - 0.035) + amplitude(x) + amplitude(x + 0.035)) / 3 : 0
      let activity = live ? min(1, local * 0.85 + energy * 0.4 + pulse * 0.15) : 0.85
      let fan = sin(x * .pi) * (0.05 + 0.055 * sin(x * 2 * .pi + phase * 0.55))
      return (x, activity, fan)
    }
    let ribbons = (0..<17).map { ribbon in
      let layer = Double(ribbon - 8)
      return samples.map { x, activity, fan -> TracePoint in
        let y: Double
        if reducedMotion {
          y = height * 0.5 + sin(x * 3 * .pi + layer * 0.06) * 15 + layer * 1.5
        } else {
          let wave =
            sin(x * 3.2 * .pi - phase + layer * 0.13)
            + 0.38 * sin(x * 6.4 * .pi + phase * 0.8 + layer * 0.09)
          y = height * 0.5 + tanh((wave * 1.05 + fan * layer) * activity) * height * 0.46
        }
        return .init(x: x * width, y: y)
      }
    }
    return .init(ribbons: ribbons)
  }
}

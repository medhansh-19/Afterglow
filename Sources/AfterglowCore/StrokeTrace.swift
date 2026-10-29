import Foundation

public struct TracePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct TraceSnapshot: Sendable {
    public let route: [TracePoint]
    public let progress: Double
    public let opacity: Double
    public var completedEdges: Int { min(route.count - 1, Int(progress)) }
    public var tip: TracePoint {
        let edge = min(route.count - 2, completedEdges)
        let fraction = min(1, max(0, progress - Double(edge)))
        return .init(x: route[edge].x + (route[edge + 1].x - route[edge].x) * fraction,
                     y: route[edge].y + (route[edge + 1].y - route[edge].y) * fraction)
    }
}

/// A continuous edge-by-edge pen. Beat counts grant drawing distance, never replace geometry.
public struct StrokeTrace {
    private var plan = 0
    private var progress = 0.0, target = 0.0, phaseTime = 0.0
    private var phase = 0
    private var lastTime: Double?
    private var lastBeat: Int?
    private var wasLive = false
    public init() {}

    public var snapshot: TraceSnapshot {
        .init(route: Self.route(plan), progress: progress,
              opacity: phase == 2 ? max(0, 1 - phaseTime / 0.65) : 1)
    }

    public mutating func advance(at time: Double, beatCount: Int, live: Bool, playing: Bool, reducedMotion: Bool = false) {
        guard time.isFinite else { return }
        let dt = min(0.1, max(0, time - (lastTime ?? time)))
        lastTime = time
        let beats = max(0, beatCount - (lastBeat ?? beatCount))
        lastBeat = beatCount
        if live != wasLive { target = progress; wasLive = live }
        guard playing, !reducedMotion else { return }
        let edges = Double(Self.route(plan).count - 1)
        if phase == 0 {
            target = live ? min(edges, target + Double(min(2, beats))) : min(edges, target + dt * 1.15)
            progress = min(target, progress + dt * 2.6)
            if progress >= edges { progress = edges; phase = 1; phaseTime = 0 }
        } else {
            phaseTime += dt
            if phase == 1 && phaseTime >= 0.5 { phase = 2; phaseTime = 0 }
            else if phase == 2 && phaseTime >= 0.65 {
                plan = (plan + 1) % 5
                progress = 0; target = 0; phaseTime = 0; phase = 0
            }
        }
    }

    public static func staticSnapshot() -> TraceSnapshot {
        let path = route(1)
        return .init(route: path, progress: Double(path.count - 1), opacity: 1)
    }

    private static func route(_ plan: Int) -> [TracePoint] {
        let order: [Int]
        let count: Int
        switch plan {
        case 0: count = 3; order = [0, 1, 2, 0]
        case 1: count = 5; order = [0, 1, 2, 3, 4, 0]
        case 2: count = 5; order = [0, 2, 4, 1, 3, 0]
        case 3: count = 6; order = [0, 1, 2, 3, 4, 5, 0]
        default: count = 7; order = [0, 3, 6, 2, 5, 1, 4, 0]
        }
        return order.map { i in
            let angle = Double(i) * 2 * .pi / Double(count) - .pi / 2
            return .init(x: cos(angle), y: sin(angle))
        }
    }
}

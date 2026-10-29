import Foundation
import AfterglowCore

@inline(never) func legacy(_ phase: Double, live: Bool, bands: [Double]) -> Double {
    func amplitude(_ x: Double) -> Double {
        if live {
            let p = min(1, max(0, x)) * Double(bands.count - 1)
            let left = min(bands.count - 1, Int(p)), right = min(bands.count - 1, left + 1)
            return bands[left] * (1 - p + Double(left)) + bands[right] * (p - Double(left))
        }
        return 0.08 + pow(0.5 + 0.5 * sin(x * 5 * .pi - phase * 1.6), 1.5) * (0.34 + (0.5 + 0.5 * sin(x * 19 + phase * 2.1)) * 0.45)
    }
    var checksum = 0.0
    for ribbon in 0..<17 {
        let layer = Double(ribbon - 8)
        for step in 0...160 {
            let x = Double(step) / 160
            let local = (amplitude(max(0, x - 0.035)) + amplitude(x) + amplitude(min(1, x + 0.035))) / 3
            let activity = live ? min(1, local * 0.85 + 0.4 * 0.4 + 0.2 * 0.15) : 0.85
            let wave = sin(x * 3.2 * .pi - phase + layer * 0.13) + 0.38 * sin(x * 6.4 * .pi + phase * 0.8 + layer * 0.09)
            let fan = sin(x * .pi) * layer * (0.05 + 0.055 * sin(x * 2 * .pi + phase * 0.55))
            checksum += 220 + tanh((wave * 1.05 + fan) * activity) * 440 * 0.46
        }
    }
    return checksum
}

let bands = (0..<32).map { Double($0) / 31 }
var checksum = 0.0
for live in [false, true] {
    let start = ProcessInfo.processInfo.systemUptime
    for i in 0..<1200 { checksum += legacy(Double(i) / 30, live: live, bands: bands) }
    let legacyTime = ProcessInfo.processInfo.systemUptime - start
    let next = ProcessInfo.processInfo.systemUptime
    for i in 0..<1200 {
        let mesh = RibbonMesh.make(width: 1440, height: 440, phase: Double(i) / 30, bands: bands, energy: 0.4, pulse: 0.2, live: live, reducedMotion: false)
        checksum += mesh.ribbons.reduce(0) { $0 + $1.reduce(0) { $0 + $1.y } }
    }
    let optimizedTime = ProcessInfo.processInfo.systemUptime - next
    print(String(format: "%@ geometry: legacy %.1f ms, optimized %.1f ms, ratio %.2fx", live ? "Live" : "Ambient", legacyTime * 1000, optimizedTime * 1000, legacyTime / optimizedTime))
}
print("Checksum: \(Int(checksum))")

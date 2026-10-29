import Foundation

public struct GlowColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red)); self.green = min(1, max(0, green)); self.blue = min(1, max(0, blue))
    }
    public static let fallback = GlowColor(red: 0.94, green: 0.40, blue: 0.67)
    public var brightness: Double { max(red, green, blue) }
    public var saturation: Double { brightness == 0 ? 0 : (brightness - min(red, green, blue)) / brightness }
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

public enum AlbumPalette {
    /// Quantized population selects a real cover color, rather than averaging complementary hues.
    /// Mostly monochrome covers stay neutral; colorful covers retain their dominant saturated hue.
    public static func extract(rgba: [UInt8]) -> GlowColor? {
        guard rgba.count >= 4, rgba.count.isMultiple(of: 4) else { return nil }
        var bins: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var visible = 0, colorful = 0, opaque = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            guard rgba[i + 3] > 180 else { continue }
            opaque += 1
            let r = Double(rgba[i]) / 255, g = Double(rgba[i + 1]) / 255, b = Double(rgba[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            guard high >= 0.12 else { continue }
            visible += 1
            if high - low > 0.16 { colorful += 1 }
            let key = (Int(r * 7) << 6) | (Int(g * 7) << 3) | Int(b * 7)
            var bin = bins[key] ?? (0, 0, 0, 0)
            bin.count += 1; bin.r += r; bin.g += g; bin.b += b
            bins[key] = bin
        }
        guard visible > 0 else { return opaque == 0 ? nil : GlowColor(red: 0.88, green: 0.90, blue: 0.94) }
        let neutral = Double(colorful) / Double(visible) < 0.15
        let ranked = bins.values.map { bin -> (GlowColor, Double) in
            let n = Double(bin.count)
            let color = GlowColor(red: bin.r / n, green: bin.g / n, blue: bin.b / n)
            let score = n * (neutral ? (color.saturation < 0.18 ? 1.4 : 0.25) : 0.65 + color.saturation)
            return (color, score)
        }.sorted { $0.1 > $1.1 }
        guard let chosen = ranked.first?.0 else { return nil }
        let boost = max(1, 0.94 / max(0.12, chosen.brightness))
        var accent = GlowColor(red: chosen.red * boost, green: chosen.green * boost, blue: chosen.blue * boost)
        // Lift dark hues while preserving their direction so active lyrics remain readable on black.
        for _ in 0..<16 where accent.luminance < 0.18 {
            accent = GlowColor(red: accent.red + (1 - accent.red) * 0.08,
                               green: accent.green + (1 - accent.green) * 0.08,
                               blue: accent.blue + (1 - accent.blue) * 0.08)
        }
        return accent
    }
}

import AppKit
import AfterglowCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.018, green: 0.016, blue: 0.025) // #050406
    static let text = Color(red: 0.98, green: 0.95, blue: 0.97) // #FAF2F7
    static let secondary = Color(red: 0.67, green: 0.62, blue: 0.67) // #AB9EAB
    static let rose = Color(red: 0.94, green: 0.40, blue: 0.67) // #F066AB
    static let blue = Color(red: 0.42, green: 0.69, blue: 0.97) // #6BB0F7
    static let amber = Color(red: 0.97, green: 0.71, blue: 0.40) // #F7B566
    static let panel = Color(red: 0.09, green: 0.08, blue: 0.10) // #17141A
    static let radius = 18.0
    static let controlHeight = 38.0
    static let appearanceSkyTop = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let appearanceSkyMiddle = Color(red: 0.23, green: 0.24, blue: 0.28)
    static let appearanceSkyBottom = Color(red: 0.45, green: 0.46, blue: 0.52)
    /// Keep the existing dark-to-slate depth while borrowing the lyric hue.
    static func appearanceSkyColors(for tint: Color) -> [Color] {
        guard let rgb = NSColor(tint).usingColorSpace(.sRGB) else {
            return [appearanceSkyTop, appearanceSkyMiddle, appearanceSkyBottom]
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let skySaturation = min(0.40, saturation * 0.65)
        return [(0.16, 0.55), (0.28, 0.80), (0.52, 1.0)].map { level, strength in
            Color(nsColor: NSColor(calibratedHue: hue, saturation: skySaturation * strength,
                                   brightness: level, alpha: 1))
        }
    }


    // Welcome stays monochrome: a black sky and quiet, readable controls.
    static let welcomeBackground = Color.black // #000000
    static let welcomeText = Color(white: 0.92) // #EBEBEB
    static let welcomeSecondary = Color(white: 0.56) // #8F8F8F
}

enum Tint: String, CaseIterable, Identifiable {
    case album = "Album cover", rose = "Rose", blue = "Blue", amber = "Amber", mint = "Mint", violet = "Violet", white = "Off-white", scarlet = "Scarlet", coral = "Coral", orange = "Orange", gold = "Gold", lime = "Lime", teal = "Teal", cyan = "Cyan", indigo = "Indigo"
    var id: String { rawValue }
    static func resolve(_ value: String, albumColor: Color? = nil) -> Color {
        if value == Self.album.rawValue, let albumColor { return albumColor }
        if let saved = SavedGlowColor(hex: value) {
            return Color(red: saved.red, green: saved.green, blue: saved.blue)
        }
        return (Self(rawValue: value) ?? .album).color
    }
    var color: Color {
        switch self {
        case .album, .rose: Theme.rose
        case .blue: Theme.blue
        case .amber: Theme.amber
        case .mint: Color(red: 0.30, green: 0.96, blue: 0.75)
        case .violet: Color(red: 0.72, green: 0.48, blue: 1)
        case .white: Color(red: 0.95, green: 0.94, blue: 0.88)
        case .scarlet: Color(red: 0.98, green: 0.32, blue: 0.36)
        case .coral: Color(red: 1.0, green: 0.49, blue: 0.43)
        case .orange: Color(red: 1.0, green: 0.61, blue: 0.27)
        case .gold: Color(red: 1.0, green: 0.84, blue: 0.34)
        case .lime: Color(red: 0.73, green: 0.92, blue: 0.36)
        case .teal: Color(red: 0.25, green: 0.82, blue: 0.73)
        case .cyan: Color(red: 0.29, green: 0.85, blue: 0.97)
        case .indigo: Color(red: 0.48, green: 0.54, blue: 1.0)
        }
    }
}

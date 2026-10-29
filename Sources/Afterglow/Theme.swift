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
}

enum Tint: String, CaseIterable, Identifiable {
    case album = "Album cover", rose = "Rose", blue = "Blue", amber = "Amber", mint = "Mint", violet = "Violet", white = "Off-white"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .album, .rose: Theme.rose
        case .blue: Theme.blue
        case .amber: Theme.amber
        case .mint: Color(red: 0.30, green: 0.96, blue: 0.75)
        case .violet: Color(red: 0.72, green: 0.48, blue: 1)
        case .white: Color(red: 0.95, green: 0.94, blue: 0.88)
        }
    }
}

import Foundation

/// A stable RGB value can be used by preferences, saved swatches and song scenes alike.
public struct SavedGlowColor: Codable, Equatable, Identifiable, Sendable {
    public let hex: String
    public let name: String
    public var id: String { hex }
    public var red: Double { Double((rgb >> 16) & 255) / 255 }
    public var green: Double { Double((rgb >> 8) & 255) / 255 }
    public var blue: Double { Double(rgb & 255) / 255 }
    private var rgb: UInt32 { UInt32(hex.dropFirst(), radix: 16)! }

    public init?(hex: String, name: String = "") {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { String(repeating: String($0), count: 2) }.joined() }
        guard value.count == 6, value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        self.hex = "#" + value.uppercased()
        let label = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        self.name = label.isEmpty ? self.hex : label
    }
    private enum CodingKeys: String, CodingKey { case hex, name }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try container.decode(String.self, forKey: .hex)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        guard let value = Self(hex: hex, name: name) else {
            throw DecodingError.dataCorruptedError(forKey: .hex, in: container, debugDescription: "Expected an RGB hex color")
        }
        self = value
    }
}

import Foundation

public struct ClockAppearance: Codable, Equatable, Sendable {
  public var style: String
  public var color: String
  public var followsLyrics: Bool
  public var format: String
  public var showsSeconds: Bool
  public var showsDate: Bool
  public var scale: Double
  public init(style: String = "Minimal", color: String = "Off-white", followsLyrics: Bool = false,
              format: String = "System", showsSeconds: Bool = false, showsDate: Bool = true,
              scale: Double = 1) {
    self.style = style; self.color = color; self.followsLyrics = followsLyrics
    self.format = format; self.showsSeconds = showsSeconds; self.showsDate = showsDate
    self.scale = scale.isFinite ? min(1.4, max(0.7, scale)) : 1
  }
}

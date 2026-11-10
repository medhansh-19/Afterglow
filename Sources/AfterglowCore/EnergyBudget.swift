import Foundation

/// One resource budget for playback, previews, ambient motion and player sampling.
/// Media time remains independent of rendering and polling frequency.
public struct EnergyBudget: Equatable, Sendable {
    public enum ThermalPressure: Sendable { case nominal, fair, serious, critical }
    public var lowPower: Bool
    public var onBattery: Bool
    public var thermalPressure: ThermalPressure

    public init(lowPower: Bool = false, onBattery: Bool = false, thermalPressure: ThermalPressure = .nominal) {
        self.lowPower = lowPower
        self.onBattery = onBattery
        self.thermalPressure = thermalPressure
    }

    public var framesPerSecond: Double {
        switch thermalPressure {
        case .critical: return 10
        case .serious: return 15
        case .fair: return 20
        case .nominal: return lowPower || onBattery ? 20 : 30
        }
    }
    public var frameInterval: Double { 1 / framesPerSecond }
    public var previewInterval: Double { 1 / min(15, framesPerSecond) }
    public var ambientInterval: Double { 1 / min(lowPower || onBattery ? 10 : 20, framesPerSecond) }
    public func pollInterval(visible: Bool, playing: Bool) -> Double {
        if !visible { return 5 }
        if !playing { return 2 }
        return lowPower || onBattery || thermalPressure != .nominal ? 1.5 : 1
    }
}

import Foundation

public enum PowerSource: String, Codable, Sendable {
    case ac
    case battery
    case unknown
}

public struct BatteryState: Equatable, Sendable {
    public let powerSource: PowerSource
    public let percentage: Int?
    public let hasInternalBattery: Bool

    public init(
        powerSource: PowerSource,
        percentage: Int?,
        hasInternalBattery: Bool
    ) {
        self.powerSource = powerSource
        self.percentage = percentage
        self.hasInternalBattery = hasInternalBattery
    }

    public static let acDesktop = BatteryState(
        powerSource: .ac,
        percentage: nil,
        hasInternalBattery: false
    )
}

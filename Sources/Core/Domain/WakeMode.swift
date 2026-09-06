import Foundation

public enum WakeMode: String, CaseIterable, Codable, Sendable {
    case off
    case system
    case display
}

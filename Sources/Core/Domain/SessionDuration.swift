import Foundation

public enum SessionDuration: String, CaseIterable, Codable, Sendable {
    case minutes30
    case hours1
    case hours2
    case hours4
    case hours8
    case indefinite

    public var interval: TimeInterval? {
        switch self {
        case .minutes30: 30 * 60
        case .hours1: 60 * 60
        case .hours2: 2 * 60 * 60
        case .hours4: 4 * 60 * 60
        case .hours8: 8 * 60 * 60
        case .indefinite: nil
        }
    }
}

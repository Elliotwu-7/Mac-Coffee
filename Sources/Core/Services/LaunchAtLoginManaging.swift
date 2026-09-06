import Foundation

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

@MainActor
public protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

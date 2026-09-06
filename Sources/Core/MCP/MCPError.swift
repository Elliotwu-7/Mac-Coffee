import Foundation

public enum MCPErrorCode: String, CaseIterable, Codable, Sendable {
    case appNotRunning = "APP_NOT_RUNNING"
    case clientUnpaired = "CLIENT_UNPAIRED"
    case clientRevoked = "CLIENT_REVOKED"
    case mcpDisabled = "MCP_DISABLED"
    case batteryBlocked = "BATTERY_BLOCKED"
    case invalidArgument = "INVALID_ARGUMENT"
    case appBusy = "APP_BUSY"
    case assertionFailed = "ASSERTION_FAILED"
    case versionMismatch = "VERSION_MISMATCH"
    case internalError = "INTERNAL_ERROR"

    public var isRetryable: Bool {
        switch self {
        case .appNotRunning, .batteryBlocked, .appBusy, .assertionFailed:
            true
        case .clientUnpaired, .clientRevoked, .mcpDisabled, .invalidArgument,
             .versionMismatch, .internalError:
            false
        }
    }
}

public struct MCPServiceError: Error, Equatable, Sendable {
    public let code: MCPErrorCode
    public let field: String?

    public init(code: MCPErrorCode, field: String? = nil) {
        self.code = code
        self.field = field
    }

    public static func invalidArgument(field: String? = nil) -> MCPServiceError {
        MCPServiceError(code: .invalidArgument, field: field)
    }
}

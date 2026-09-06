import Combine
import Foundation

public struct MCPClientContext: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let displayName: String

    public init(identifier: String, displayName: String) {
        self.identifier = Self.sanitized(identifier, fallback: "unknown-client", limit: 256)
        self.displayName = Self.sanitized(displayName, fallback: "Unknown client", limit: 128)
    }

    public static let unattributed = MCPClientContext(
        identifier: "unattributed-client",
        displayName: "Unattributed client"
    )

    private static func sanitized(_ value: String, fallback: String, limit: Int) -> String {
        let withoutControls = value
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded = String(withoutControls.prefix(limit))
        return bounded.isEmpty ? fallback : bounded
    }
}

public enum MCPActivityAction: String, Codable, CaseIterable, Sendable {
    case getStatus = "maccoffee_get_status"
    case setSession = "maccoffee_set_session"
    case stopSession = "maccoffee_stop_session"
    case setBatteryThreshold = "maccoffee_set_battery_threshold"
    case setLaunchAtLogin = "maccoffee_set_launch_at_login"
    case setLanguage = "maccoffee_set_language"
    case readStatus = "read:maccoffee://status"
    case readCapabilities = "read:maccoffee://capabilities"
    case readActivity = "read:maccoffee://activity"
    case subscribeStatus = "subscribe:maccoffee://status"
    case unsubscribeStatus = "unsubscribe:maccoffee://status"
}

public struct MCPActivityInputSummary: Codable, Equatable, Sendable {
    public let mode: WakeMode?
    public let duration: SessionDuration?
    public let percent: Int?
    public let enabled: Bool?
    public let language: SupportedLanguage?

    public init(
        mode: WakeMode? = nil,
        duration: SessionDuration? = nil,
        percent: Int? = nil,
        enabled: Bool? = nil,
        language: SupportedLanguage? = nil
    ) {
        self.mode = mode
        self.duration = duration
        self.percent = percent
        self.enabled = enabled
        self.language = language
    }

    public static let empty = MCPActivityInputSummary()
}

public struct MCPActivityOutcome: Codable, Equatable, Sendable {
    public let succeeded: Bool
    public let errorCode: MCPErrorCode?

    public static let success = MCPActivityOutcome(succeeded: true, errorCode: nil)

    public static func failure(_ code: MCPErrorCode) -> MCPActivityOutcome {
        MCPActivityOutcome(succeeded: false, errorCode: code)
    }
}

public struct MCPActivityEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UInt64 { sequence }

    public let sequence: UInt64
    public let timestamp: String
    public let client: MCPClientContext
    public let action: MCPActivityAction
    public let input: MCPActivityInputSummary
    public let requestID: String?
    public let outcome: MCPActivityOutcome
    public let replayed: Bool
}

@MainActor
public final class MCPActivityStore: ObservableObject {
    @Published public private(set) var entries: [MCPActivityEvent] = []

    private let capacity: Int
    private let now: () -> Date
    private let dateFormatter: ISO8601DateFormatter
    private var sequence: UInt64 = 0

    public init(
        capacity: Int = 200,
        now: @escaping () -> Date = Date.init
    ) {
        self.capacity = max(1, capacity)
        self.now = now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter = formatter
    }

    public func record(
        client: MCPClientContext,
        command: MCPCommand,
        outcome: MCPActivityOutcome,
        replayed: Bool
    ) {
        record(
            client: client,
            action: command.activityAction,
            input: command.activityInput,
            requestID: command.requestID,
            outcome: outcome,
            replayed: replayed
        )
    }

    public func record(
        client: MCPClientContext,
        action: MCPActivityAction,
        input: MCPActivityInputSummary = .empty,
        requestID: String? = nil,
        outcome: MCPActivityOutcome,
        replayed: Bool
    ) {
        sequence = sequence == .max ? 1 : sequence + 1
        entries.append(MCPActivityEvent(
            sequence: sequence,
            timestamp: dateFormatter.string(from: now()),
            client: client,
            action: action,
            input: input,
            requestID: requestID,
            outcome: outcome,
            replayed: replayed
        ))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}

private extension MCPCommand {
    var activityAction: MCPActivityAction {
        switch self {
        case .getStatus: .getStatus
        case .setSession: .setSession
        case .stopSession: .stopSession
        case .setBatteryThreshold: .setBatteryThreshold
        case .setLaunchAtLogin: .setLaunchAtLogin
        case .setLanguage: .setLanguage
        }
    }

    var activityInput: MCPActivityInputSummary {
        switch self {
        case .getStatus, .stopSession:
            .empty
        case let .setSession(mode, duration, _):
            MCPActivityInputSummary(mode: mode, duration: duration)
        case let .setBatteryThreshold(percent, _):
            MCPActivityInputSummary(percent: percent)
        case let .setLaunchAtLogin(enabled, _):
            MCPActivityInputSummary(enabled: enabled)
        case let .setLanguage(language, _):
            MCPActivityInputSummary(language: language)
        }
    }
}

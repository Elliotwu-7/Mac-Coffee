import Foundation

public struct MCPEnvelope<Payload>: Codable, Equatable, Sendable
where Payload: Codable & Equatable & Sendable {
    public let schemaVersion: Int
    public let sequence: UInt64
    public let timestamp: String
    public let requestID: String?
    public let data: Payload
    public let displayText: String

    public init(
        schemaVersion: Int = MCPContract.schemaVersion,
        sequence: UInt64,
        timestamp: String,
        requestID: String?,
        data: Payload,
        displayText: String
    ) {
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.timestamp = timestamp
        self.requestID = requestID
        self.data = data
        self.displayText = displayText
    }
}

public struct MCPStatusSnapshot: Codable, Equatable, Sendable {
    public let mode: WakeMode
    public let session: MCPSessionSnapshot?
    public let selectedDuration: SessionDuration
    public let battery: MCPBatterySnapshot
    public let launchAtLogin: MCPLaunchAtLoginState
    public let language: MCPLanguageSnapshot
    public let busy: Bool
    public let notice: MCPNoticeSnapshot?

    public init(
        mode: WakeMode,
        session: MCPSessionSnapshot?,
        selectedDuration: SessionDuration,
        battery: MCPBatterySnapshot,
        launchAtLogin: MCPLaunchAtLoginState,
        language: MCPLanguageSnapshot,
        busy: Bool,
        notice: MCPNoticeSnapshot?
    ) {
        self.mode = mode
        self.session = session
        self.selectedDuration = selectedDuration
        self.battery = battery
        self.launchAtLogin = launchAtLogin
        self.language = language
        self.busy = busy
        self.notice = notice
    }

    private enum CodingKeys: String, CodingKey {
        case mode, session, selectedDuration, battery, launchAtLogin, language, busy, notice
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        if let session {
            try container.encode(session, forKey: .session)
        } else {
            try container.encodeNil(forKey: .session)
        }
        try container.encode(selectedDuration, forKey: .selectedDuration)
        try container.encode(battery, forKey: .battery)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(language, forKey: .language)
        try container.encode(busy, forKey: .busy)
        if let notice {
            try container.encode(notice, forKey: .notice)
        } else {
            try container.encodeNil(forKey: .notice)
        }
    }
}

public struct MCPActivitySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let entries: [MCPActivityEvent]

    public init(
        schemaVersion: Int = MCPContract.schemaVersion,
        entries: [MCPActivityEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

public struct MCPSessionSnapshot: Codable, Equatable, Sendable {
    public let mode: WakeMode
    public let duration: SessionDuration
    public let startedAt: String
    public let expiresAt: String?

    public init(
        mode: WakeMode,
        duration: SessionDuration,
        startedAt: String,
        expiresAt: String?
    ) {
        self.mode = mode
        self.duration = duration
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case mode, duration, startedAt, expiresAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(duration, forKey: .duration)
        try container.encode(startedAt, forKey: .startedAt)
        if let expiresAt {
            try container.encode(expiresAt, forKey: .expiresAt)
        } else {
            try container.encodeNil(forKey: .expiresAt)
        }
    }
}

public struct MCPBatterySnapshot: Codable, Equatable, Sendable {
    public let powerSource: PowerSource
    public let percentage: Int?
    public let hasInternalBattery: Bool
    public let threshold: Int
    public let blocked: Bool

    public init(
        powerSource: PowerSource,
        percentage: Int?,
        hasInternalBattery: Bool,
        threshold: Int,
        blocked: Bool
    ) {
        self.powerSource = powerSource
        self.percentage = percentage
        self.hasInternalBattery = hasInternalBattery
        self.threshold = threshold
        self.blocked = blocked
    }

    private enum CodingKeys: String, CodingKey {
        case powerSource, percentage, hasInternalBattery, threshold, blocked
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(powerSource, forKey: .powerSource)
        if let percentage {
            try container.encode(percentage, forKey: .percentage)
        } else {
            try container.encodeNil(forKey: .percentage)
        }
        try container.encode(hasInternalBattery, forKey: .hasInternalBattery)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(blocked, forKey: .blocked)
    }
}

public enum MCPLaunchAtLoginState: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

public struct MCPLanguageSnapshot: Codable, Equatable, Sendable {
    public let selected: String
    public let effective: String

    public init(selected: String, effective: String) {
        self.selected = selected
        self.effective = effective
    }
}

public enum MCPNoticeCode: String, Codable, Equatable, Sendable {
    case batteryBlocked = "BATTERY_BLOCKED"
    case timerCompleted = "TIMER_COMPLETED"
    case powerAssertionFailed = "POWER_ASSERTION_FAILED"
    case launchAtLoginFailed = "LAUNCH_AT_LOGIN_FAILED"
}

public struct MCPNoticeSnapshot: Codable, Equatable, Sendable {
    public let code: MCPNoticeCode
    public let displayText: String

    public init(code: MCPNoticeCode, displayText: String) {
        self.code = code
        self.displayText = displayText
    }
}

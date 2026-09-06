import Foundation

public enum MCPContract {
    public static let schemaVersion = 1
    public static let maximumRequestIDLength = 128
}

public enum MCPToolName: String, CaseIterable, Sendable {
    case getStatus = "maccoffee_get_status"
    case setSession = "maccoffee_set_session"
    case stopSession = "maccoffee_stop_session"
    case setBatteryThreshold = "maccoffee_set_battery_threshold"
    case setLaunchAtLogin = "maccoffee_set_launch_at_login"
    case setLanguage = "maccoffee_set_language"
}

public enum MCPResourceURI: String, CaseIterable, Sendable {
    case status = "maccoffee://status"
    case capabilities = "maccoffee://capabilities"
    case activity = "maccoffee://activity"
}

public enum MCPXPCAction: String, Sendable {
    case readStatus = "read:maccoffee://status"
    case readActivity = "read:maccoffee://activity"
}

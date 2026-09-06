import CoreFoundation
import Foundation

public enum MCPCommand: Equatable, Sendable {
    case getStatus
    case setSession(mode: WakeMode, duration: SessionDuration, requestID: String?)
    case stopSession(requestID: String?)
    case setBatteryThreshold(percent: Int, requestID: String?)
    case setLaunchAtLogin(enabled: Bool, requestID: String?)
    case setLanguage(language: SupportedLanguage, requestID: String?)

    public var requestID: String? {
        switch self {
        case .getStatus:
            nil
        case let .setSession(_, _, requestID),
             let .stopSession(requestID),
             let .setBatteryThreshold(_, requestID),
             let .setLaunchAtLogin(_, requestID),
             let .setLanguage(_, requestID):
            requestID
        }
    }

    public static func makeBatteryThreshold(
        percent: Int,
        requestID: String?
    ) throws -> MCPCommand {
        guard LowBatteryPolicy.thresholdRange.contains(percent) else {
            throw MCPServiceError.invalidArgument(field: "percent")
        }
        return .setBatteryThreshold(percent: percent, requestID: try validatedRequestID(requestID))
    }

    private static func validatedRequestID(_ requestID: String?) throws -> String? {
        guard let requestID else { return nil }
        guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              requestID.count <= MCPContract.maximumRequestIDLength else {
            throw MCPServiceError.invalidArgument(field: "requestId")
        }
        return requestID
    }

    static func validatedOptionalRequestID(_ requestID: String?) throws -> String? {
        try validatedRequestID(requestID)
    }
}

public enum MCPCommandParser {
    public static func parse(toolName: String, argumentsJSON: Data?) throws -> MCPCommand {
        guard let tool = MCPToolName(rawValue: toolName) else {
            throw MCPServiceError.invalidArgument(field: "tool")
        }
        let arguments = try decodeObject(argumentsJSON)

        switch tool {
        case .getStatus:
            try requireKeys(arguments, required: [], optional: [])
            return .getStatus

        case .setSession:
            try requireKeys(arguments, required: ["mode", "duration"], optional: ["requestId"])
            let modeRaw = try string(arguments, key: "mode")
            let durationRaw = try string(arguments, key: "duration")
            guard let mode = WakeMode(rawValue: modeRaw), mode != .off else {
                throw MCPServiceError.invalidArgument(field: "mode")
            }
            guard let duration = SessionDuration(rawValue: durationRaw) else {
                throw MCPServiceError.invalidArgument(field: "duration")
            }
            return .setSession(
                mode: mode,
                duration: duration,
                requestID: try requestID(arguments)
            )

        case .stopSession:
            try requireKeys(arguments, required: [], optional: ["requestId"])
            return .stopSession(requestID: try requestID(arguments))

        case .setBatteryThreshold:
            try requireKeys(arguments, required: ["percent"], optional: ["requestId"])
            return try MCPCommand.makeBatteryThreshold(
                percent: try integer(arguments, key: "percent"),
                requestID: try requestID(arguments)
            )

        case .setLaunchAtLogin:
            try requireKeys(arguments, required: ["enabled"], optional: ["requestId"])
            return .setLaunchAtLogin(
                enabled: try boolean(arguments, key: "enabled"),
                requestID: try requestID(arguments)
            )

        case .setLanguage:
            try requireKeys(arguments, required: ["language"], optional: ["requestId"])
            let languageRaw = try string(arguments, key: "language")
            guard let language = SupportedLanguage(rawValue: languageRaw) else {
                throw MCPServiceError.invalidArgument(field: "language")
            }
            return .setLanguage(
                language: language,
                requestID: try requestID(arguments)
            )
        }
    }

    private static func decodeObject(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPServiceError.invalidArgument(field: "arguments")
            }
            return object
        } catch let error as MCPServiceError {
            throw error
        } catch {
            throw MCPServiceError.invalidArgument(field: "arguments")
        }
    }

    private static func requireKeys(
        _ arguments: [String: Any],
        required: Set<String>,
        optional: Set<String>
    ) throws {
        let keys = Set(arguments.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
            throw MCPServiceError.invalidArgument(field: "arguments")
        }
    }

    private static func string(_ arguments: [String: Any], key: String) throws -> String {
        guard let value = arguments[key] as? String else {
            throw MCPServiceError.invalidArgument(field: key)
        }
        return value
    }

    private static func integer(_ arguments: [String: Any], key: String) throws -> Int {
        guard let value = arguments[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.rounded(.towardZero) == value.doubleValue,
              value.doubleValue >= Double(Int.min),
              value.doubleValue <= Double(Int.max) else {
            throw MCPServiceError.invalidArgument(field: key)
        }
        return value.intValue
    }

    private static func boolean(_ arguments: [String: Any], key: String) throws -> Bool {
        guard let value = arguments[key] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw MCPServiceError.invalidArgument(field: key)
        }
        return value.boolValue
    }

    private static func requestID(_ arguments: [String: Any]) throws -> String? {
        guard arguments.keys.contains("requestId") else { return nil }
        return try MCPCommand.validatedOptionalRequestID(try string(arguments, key: "requestId"))
    }
}

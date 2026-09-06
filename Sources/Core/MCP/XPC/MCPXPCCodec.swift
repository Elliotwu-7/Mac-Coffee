import Foundation

public enum MCPXPCCodecError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidField(String)
    case payloadTooLarge
    case malformedJSON
    case deadlineExpired
    case authenticationRequired
}

public struct MCPXPCDecodedRequest {
    public let clientIdentifier: String
    public let requestIdentifier: String
    public let action: String
    public let payload: [String: Any]
    public let deadline: Date
}

public struct MCPXPCDecodedSubscription: Equatable, Sendable {
    public let clientIdentifier: String
    public let subscriptionIdentifier: String
    public let resourceURI: String
    public let deadline: Date
}

public enum MCPXPCCodec {
    public static let maximumJSONPayloadBytes = 64 * 1_024
    public static let maximumBinaryPayloadBytes = 128 * 1_024
    public static let maximumIdentifierLength = 256
    public static let maximumMessageLength = 1_024

    public static func decodeAuthenticationHello(
        _ value: MCPXPCAuthenticationHello
    ) throws -> MCPAuthenticationPresentation {
        try validateSchema(value.schemaVersion)
        try validateIdentifier(value.connectionIdentifier, field: "connectionIdentifier")
        try validateJSONPayload(value.presentationJSON)
        do {
            return try JSONDecoder().decode(
                MCPAuthenticationPresentation.self,
                from: value.presentationJSON
            )
        } catch {
            throw MCPXPCCodecError.malformedJSON
        }
    }

    public static func validate(_ value: MCPXPCAuthenticationChallenge) throws {
        try validateSchema(value.schemaVersion)
        try validateIdentifier(value.challengeIdentifier, field: "challengeIdentifier")
        guard value.nonce.count == 32 else {
            throw MCPXPCCodecError.invalidField("nonce")
        }
        guard
            !value.transcript.isEmpty,
            value.transcript.count <= maximumBinaryPayloadBytes
        else {
            throw MCPXPCCodecError.payloadTooLarge
        }
    }

    public static func validate(_ value: MCPXPCAuthenticationProof) throws {
        try validateSchema(value.schemaVersion)
        try validateIdentifier(value.challengeIdentifier, field: "challengeIdentifier")
        guard !value.signature.isEmpty, value.signature.count <= 512 else {
            throw MCPXPCCodecError.invalidField("signature")
        }
    }

    public static func validate(_ value: MCPXPCAuthenticationResult) throws {
        try validateSchema(value.schemaVersion)
        switch value.state {
        case .authenticated:
            guard let clientJSON = value.clientJSON, value.pairingRequestJSON == nil else {
                throw MCPXPCCodecError.invalidField("authenticationResult")
            }
            try validateJSONPayload(clientJSON)
        case .approvalRequired:
            guard let requestJSON = value.pairingRequestJSON, value.clientJSON == nil else {
                throw MCPXPCCodecError.invalidField("authenticationResult")
            }
            try validateJSONPayload(requestJSON)
        }
    }

    public static func validate(_ value: MCPXPCError) throws {
        try validateText(value.code, field: "code", maximumLength: 128)
        try validateText(value.message, field: "message", maximumLength: maximumMessageLength)
    }

    public static func decodeRequest(
        _ value: MCPXPCRequest,
        authenticatedClientIdentifier: String?,
        now: Date
    ) throws -> MCPXPCDecodedRequest {
        try validateSchema(value.schemaVersion)
        let clientIdentifier = try requireAuthentication(authenticatedClientIdentifier)
        try validateIdentifier(value.requestIdentifier, field: "requestIdentifier")
        try validateText(value.action, field: "action", maximumLength: 256)
        guard value.deadline > now else {
            throw MCPXPCCodecError.deadlineExpired
        }
        let payload = try decodeJSONObject(value.payloadJSON)
        return MCPXPCDecodedRequest(
            clientIdentifier: clientIdentifier,
            requestIdentifier: value.requestIdentifier,
            action: value.action,
            payload: payload,
            deadline: value.deadline
        )
    }

    public static func validate(_ value: MCPXPCResponse) throws {
        try validateSchema(value.schemaVersion)
        try validateIdentifier(value.requestIdentifier, field: "requestIdentifier")
        guard (value.payloadJSON == nil) != (value.error == nil) else {
            throw MCPXPCCodecError.invalidField("responseResult")
        }
        if let payload = value.payloadJSON {
            try validateJSONPayload(payload)
        }
        if let error = value.error {
            try validate(error)
        }
    }

    public static func decodeSubscription(
        _ value: MCPXPCSubscription,
        authenticatedClientIdentifier: String?,
        now: Date
    ) throws -> MCPXPCDecodedSubscription {
        try validateSchema(value.schemaVersion)
        let clientIdentifier = try requireAuthentication(authenticatedClientIdentifier)
        try validateIdentifier(
            value.subscriptionIdentifier,
            field: "subscriptionIdentifier"
        )
        guard value.resourceURI == MCPResourceURI.status.rawValue else {
            throw MCPXPCCodecError.invalidField("resourceURI")
        }
        guard value.deadline > now else {
            throw MCPXPCCodecError.deadlineExpired
        }
        return MCPXPCDecodedSubscription(
            clientIdentifier: clientIdentifier,
            subscriptionIdentifier: value.subscriptionIdentifier,
            resourceURI: value.resourceURI,
            deadline: value.deadline
        )
    }

    public static func validate(_ value: MCPXPCEvent) throws {
        try validateSchema(value.schemaVersion)
        try validateIdentifier(
            value.subscriptionIdentifier,
            field: "subscriptionIdentifier"
        )
        guard value.sequence >= 0 else {
            throw MCPXPCCodecError.invalidField("sequence")
        }
        try validateJSONPayload(value.payloadJSON)
    }

    public static func validate(_ value: MCPXPCCancellation) throws {
        try validateSchema(value.schemaVersion)
        try validateIdentifier(value.requestIdentifier, field: "requestIdentifier")
    }

    public static func validate(_ value: MCPXPCClose) throws {
        try validateSchema(value.schemaVersion)
        if let message = value.message {
            try validateText(
                message,
                field: "message",
                maximumLength: maximumMessageLength
            )
        }
    }

    private static func validateSchema(_ version: Int) throws {
        guard version == MCPContract.schemaVersion else {
            throw MCPXPCCodecError.unsupportedSchemaVersion(version)
        }
    }

    private static func requireAuthentication(_ identifier: String?) throws -> String {
        guard let identifier else {
            throw MCPXPCCodecError.authenticationRequired
        }
        try validateIdentifier(identifier, field: "authenticatedClientIdentifier")
        return identifier
    }

    private static func validateIdentifier(_ value: String, field: String) throws {
        try validateText(value, field: field, maximumLength: maximumIdentifierLength)
    }

    private static func validateText(
        _ value: String,
        field: String,
        maximumLength: Int
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else {
            throw MCPXPCCodecError.invalidField(field)
        }
    }

    private static func validateJSONPayload(_ data: Data) throws {
        _ = try decodeJSONObject(data)
    }

    private static func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumJSONPayloadBytes else {
            throw MCPXPCCodecError.payloadTooLarge
        }
        guard !data.isEmpty else {
            throw MCPXPCCodecError.malformedJSON
        }
        do {
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw MCPXPCCodecError.malformedJSON
            }
            return object
        } catch let error as MCPXPCCodecError {
            throw error
        } catch {
            throw MCPXPCCodecError.malformedJSON
        }
    }
}

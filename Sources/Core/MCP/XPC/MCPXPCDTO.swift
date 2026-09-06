import Foundation

@objc(MCPXPCAuthenticationHello)
public final class MCPXPCAuthenticationHello: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let connectionIdentifier: String
    public let presentationJSON: Data

    public init(schemaVersion: Int, connectionIdentifier: String, presentationJSON: Data) {
        self.schemaVersion = schemaVersion
        self.connectionIdentifier = connectionIdentifier
        self.presentationJSON = presentationJSON
    }

    public required init?(coder: NSCoder) {
        guard
            let connectionIdentifier = coder.mcpRequiredString(forKey: "connectionIdentifier"),
            connectionIdentifier.count <= MCPXPCCodec.maximumIdentifierLength,
            let presentationJSON = coder.mcpRequiredData(forKey: "presentationJSON"),
            presentationJSON.count <= MCPXPCCodec.maximumJSONPayloadBytes
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.connectionIdentifier = connectionIdentifier
        self.presentationJSON = presentationJSON
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(connectionIdentifier as NSString, forKey: "connectionIdentifier")
        coder.encode(presentationJSON as NSData, forKey: "presentationJSON")
    }
}

@objc(MCPXPCAuthenticationChallenge)
public final class MCPXPCAuthenticationChallenge: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let challengeIdentifier: String
    public let nonce: Data
    public let transcript: Data

    public init(
        schemaVersion: Int,
        challengeIdentifier: String,
        nonce: Data,
        transcript: Data
    ) {
        self.schemaVersion = schemaVersion
        self.challengeIdentifier = challengeIdentifier
        self.nonce = nonce
        self.transcript = transcript
    }

    public required init?(coder: NSCoder) {
        guard
            let challengeIdentifier = coder.mcpRequiredString(forKey: "challengeIdentifier"),
            challengeIdentifier.count <= MCPXPCCodec.maximumIdentifierLength,
            let nonce = coder.mcpRequiredData(forKey: "nonce"),
            nonce.count == 32,
            let transcript = coder.mcpRequiredData(forKey: "transcript"),
            transcript.count <= MCPXPCCodec.maximumBinaryPayloadBytes
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.challengeIdentifier = challengeIdentifier
        self.nonce = nonce
        self.transcript = transcript
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(challengeIdentifier as NSString, forKey: "challengeIdentifier")
        coder.encode(nonce as NSData, forKey: "nonce")
        coder.encode(transcript as NSData, forKey: "transcript")
    }
}

@objc(MCPXPCAuthenticationProof)
public final class MCPXPCAuthenticationProof: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let challengeIdentifier: String
    public let signature: Data

    public init(schemaVersion: Int, challengeIdentifier: String, signature: Data) {
        self.schemaVersion = schemaVersion
        self.challengeIdentifier = challengeIdentifier
        self.signature = signature
    }

    public required init?(coder: NSCoder) {
        guard
            let challengeIdentifier = coder.mcpRequiredString(forKey: "challengeIdentifier"),
            challengeIdentifier.count <= MCPXPCCodec.maximumIdentifierLength,
            let signature = coder.mcpRequiredData(forKey: "signature"),
            signature.count <= 512
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.challengeIdentifier = challengeIdentifier
        self.signature = signature
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(challengeIdentifier as NSString, forKey: "challengeIdentifier")
        coder.encode(signature as NSData, forKey: "signature")
    }
}

public enum MCPXPCAuthenticationState: String, Sendable {
    case authenticated
    case approvalRequired
}

@objc(MCPXPCAuthenticationResult)
public final class MCPXPCAuthenticationResult: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let state: MCPXPCAuthenticationState
    public let clientJSON: Data?
    public let pairingRequestJSON: Data?

    public init(
        schemaVersion: Int,
        state: MCPXPCAuthenticationState,
        clientJSON: Data?,
        pairingRequestJSON: Data?
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.clientJSON = clientJSON
        self.pairingRequestJSON = pairingRequestJSON
    }

    public required init?(coder: NSCoder) {
        guard
            let rawState = coder.mcpRequiredString(forKey: "state"),
            let state = MCPXPCAuthenticationState(rawValue: rawState)
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.state = state
        let clientJSON = coder.mcpOptionalData(forKey: "clientJSON")
        let pairingRequestJSON = coder.mcpOptionalData(forKey: "pairingRequestJSON")
        guard
            (clientJSON?.count ?? 0) <= MCPXPCCodec.maximumJSONPayloadBytes,
            (pairingRequestJSON?.count ?? 0) <= MCPXPCCodec.maximumJSONPayloadBytes
        else { return nil }
        self.clientJSON = clientJSON
        self.pairingRequestJSON = pairingRequestJSON
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(state.rawValue as NSString, forKey: "state")
        coder.encode(clientJSON as NSData?, forKey: "clientJSON")
        coder.encode(pairingRequestJSON as NSData?, forKey: "pairingRequestJSON")
    }
}

@objc(MCPXPCError)
public final class MCPXPCError: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let code: String
    public let message: String
    public let retryable: Bool

    public init(code: String, message: String, retryable: Bool) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }

    public required init?(coder: NSCoder) {
        guard
            let code = coder.mcpRequiredString(forKey: "code"),
            code.count <= 128,
            let message = coder.mcpRequiredString(forKey: "message"),
            message.count <= MCPXPCCodec.maximumMessageLength
        else { return nil }
        self.code = code
        self.message = message
        retryable = coder.decodeBool(forKey: "retryable")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(code as NSString, forKey: "code")
        coder.encode(message as NSString, forKey: "message")
        coder.encode(retryable, forKey: "retryable")
    }
}

@objc(MCPXPCRequest)
public final class MCPXPCRequest: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let requestIdentifier: String
    public let action: String
    public let payloadJSON: Data
    public let deadline: Date

    public init(
        schemaVersion: Int,
        requestIdentifier: String,
        action: String,
        payloadJSON: Data,
        deadline: Date
    ) {
        self.schemaVersion = schemaVersion
        self.requestIdentifier = requestIdentifier
        self.action = action
        self.payloadJSON = payloadJSON
        self.deadline = deadline
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.mcpRequiredString(forKey: "requestIdentifier"),
            requestIdentifier.count <= MCPXPCCodec.maximumIdentifierLength,
            let action = coder.mcpRequiredString(forKey: "action"),
            action.count <= MCPXPCCodec.maximumIdentifierLength,
            let payloadJSON = coder.mcpRequiredData(forKey: "payloadJSON"),
            payloadJSON.count <= MCPXPCCodec.maximumJSONPayloadBytes,
            let deadline = coder.mcpRequiredDate(forKey: "deadline")
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.requestIdentifier = requestIdentifier
        self.action = action
        self.payloadJSON = payloadJSON
        self.deadline = deadline
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(action as NSString, forKey: "action")
        coder.encode(payloadJSON as NSData, forKey: "payloadJSON")
        coder.encode(deadline as NSDate, forKey: "deadline")
    }
}

@objc(MCPXPCResponse)
public final class MCPXPCResponse: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let requestIdentifier: String
    public let payloadJSON: Data?
    public let error: MCPXPCError?

    public init(
        schemaVersion: Int,
        requestIdentifier: String,
        payloadJSON: Data?,
        error: MCPXPCError?
    ) {
        self.schemaVersion = schemaVersion
        self.requestIdentifier = requestIdentifier
        self.payloadJSON = payloadJSON
        self.error = error
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.mcpRequiredString(forKey: "requestIdentifier"),
            requestIdentifier.count <= MCPXPCCodec.maximumIdentifierLength
        else {
            return nil
        }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.requestIdentifier = requestIdentifier
        let payloadJSON = coder.mcpOptionalData(forKey: "payloadJSON")
        guard (payloadJSON?.count ?? 0) <= MCPXPCCodec.maximumJSONPayloadBytes else {
            return nil
        }
        self.payloadJSON = payloadJSON
        error = coder.decodeObject(of: MCPXPCError.self, forKey: "error")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
        coder.encode(payloadJSON as NSData?, forKey: "payloadJSON")
        coder.encode(error, forKey: "error")
    }
}

@objc(MCPXPCSubscription)
public final class MCPXPCSubscription: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let subscriptionIdentifier: String
    public let resourceURI: String
    public let deadline: Date

    public init(
        schemaVersion: Int,
        subscriptionIdentifier: String,
        resourceURI: String,
        deadline: Date
    ) {
        self.schemaVersion = schemaVersion
        self.subscriptionIdentifier = subscriptionIdentifier
        self.resourceURI = resourceURI
        self.deadline = deadline
    }

    public required init?(coder: NSCoder) {
        guard
            let subscriptionIdentifier = coder.mcpRequiredString(forKey: "subscriptionIdentifier"),
            subscriptionIdentifier.count <= MCPXPCCodec.maximumIdentifierLength,
            let resourceURI = coder.mcpRequiredString(forKey: "resourceURI"),
            resourceURI.count <= MCPXPCCodec.maximumIdentifierLength,
            let deadline = coder.mcpRequiredDate(forKey: "deadline")
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.subscriptionIdentifier = subscriptionIdentifier
        self.resourceURI = resourceURI
        self.deadline = deadline
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(subscriptionIdentifier as NSString, forKey: "subscriptionIdentifier")
        coder.encode(resourceURI as NSString, forKey: "resourceURI")
        coder.encode(deadline as NSDate, forKey: "deadline")
    }
}

@objc(MCPXPCEvent)
public final class MCPXPCEvent: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let subscriptionIdentifier: String
    public let sequence: Int64
    public let payloadJSON: Data

    public init(
        schemaVersion: Int,
        subscriptionIdentifier: String,
        sequence: Int64,
        payloadJSON: Data
    ) {
        self.schemaVersion = schemaVersion
        self.subscriptionIdentifier = subscriptionIdentifier
        self.sequence = sequence
        self.payloadJSON = payloadJSON
    }

    public required init?(coder: NSCoder) {
        guard
            let subscriptionIdentifier = coder.mcpRequiredString(forKey: "subscriptionIdentifier"),
            subscriptionIdentifier.count <= MCPXPCCodec.maximumIdentifierLength,
            let payloadJSON = coder.mcpRequiredData(forKey: "payloadJSON"),
            payloadJSON.count <= MCPXPCCodec.maximumJSONPayloadBytes
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.subscriptionIdentifier = subscriptionIdentifier
        sequence = coder.decodeInt64(forKey: "sequence")
        self.payloadJSON = payloadJSON
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(subscriptionIdentifier as NSString, forKey: "subscriptionIdentifier")
        coder.encode(sequence, forKey: "sequence")
        coder.encode(payloadJSON as NSData, forKey: "payloadJSON")
    }
}

@objc(MCPXPCCancellation)
public final class MCPXPCCancellation: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let requestIdentifier: String

    public init(schemaVersion: Int, requestIdentifier: String) {
        self.schemaVersion = schemaVersion
        self.requestIdentifier = requestIdentifier
    }

    public required init?(coder: NSCoder) {
        guard
            let requestIdentifier = coder.mcpRequiredString(forKey: "requestIdentifier"),
            requestIdentifier.count <= MCPXPCCodec.maximumIdentifierLength
        else {
            return nil
        }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.requestIdentifier = requestIdentifier
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(requestIdentifier as NSString, forKey: "requestIdentifier")
    }
}

public enum MCPXPCCloseReason: String, Sendable {
    case clientRequest
    case integrationDisabled
    case clientRevoked
    case protocolError
    case appTermination
}

@objc(MCPXPCClose)
public final class MCPXPCClose: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int
    public let reason: MCPXPCCloseReason
    public let message: String?

    public init(schemaVersion: Int, reason: MCPXPCCloseReason, message: String?) {
        self.schemaVersion = schemaVersion
        self.reason = reason
        self.message = message
    }

    public required init?(coder: NSCoder) {
        guard
            let rawReason = coder.mcpRequiredString(forKey: "reason"),
            let reason = MCPXPCCloseReason(rawValue: rawReason)
        else { return nil }
        schemaVersion = coder.decodeInteger(forKey: "schemaVersion")
        self.reason = reason
        let message = coder.mcpOptionalString(forKey: "message")
        guard (message?.count ?? 0) <= MCPXPCCodec.maximumMessageLength else {
            return nil
        }
        self.message = message
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(reason.rawValue as NSString, forKey: "reason")
        coder.encode(message as NSString?, forKey: "message")
    }
}

private extension NSCoder {
    func mcpRequiredString(forKey key: String) -> String? {
        decodeObject(of: NSString.self, forKey: key) as String?
    }

    func mcpOptionalString(forKey key: String) -> String? {
        guard containsValue(forKey: key) else { return nil }
        return decodeObject(of: NSString.self, forKey: key) as String?
    }

    func mcpRequiredData(forKey key: String) -> Data? {
        decodeObject(of: NSData.self, forKey: key) as Data?
    }

    func mcpOptionalData(forKey key: String) -> Data? {
        guard containsValue(forKey: key) else { return nil }
        return decodeObject(of: NSData.self, forKey: key) as Data?
    }

    func mcpRequiredDate(forKey key: String) -> Date? {
        decodeObject(of: NSDate.self, forKey: key) as Date?
    }
}

import CryptoKit
import Foundation

public protocol MCPNonceGenerating: AnyObject {
    func nextNonce(byteCount: Int) throws -> Data
}

public protocol MCPSignatureVerifying {
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool
}

public protocol MCPExecutableIdentityVerifying: AnyObject {
    func identity(forExecutableAt path: String) throws -> MCPCodeIdentity
}

public struct MCPP256SignatureVerifier: MCPSignatureVerifying, Sendable {
    public init() {}

    public func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        guard
            let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
            let signature = try? P256.Signing.ECDSASignature(derRepresentation: signature)
        else {
            return false
        }
        return key.isValidSignature(signature, for: message)
    }
}

public struct MCPClientPublicIdentity: Codable, Equatable, Sendable {
    public let clientIdentifier: String
    public let displayName: String
    public let publicKey: Data

    public init(clientIdentifier: String, displayName: String, publicKey: Data) {
        self.clientIdentifier = clientIdentifier
        self.displayName = displayName
        self.publicKey = publicKey
    }
}

public struct MCPAuthenticationPresentation: Codable, Equatable, Sendable {
    public let clientIdentifier: String
    public let displayName: String
    public let publicKey: Data
    public let parentIdentity: MCPCodeIdentity

    public init(
        clientIdentifier: String,
        displayName: String,
        publicKey: Data,
        parentIdentity: MCPCodeIdentity
    ) {
        self.clientIdentifier = clientIdentifier
        self.displayName = displayName
        self.publicKey = publicKey
        self.parentIdentity = parentIdentity
    }
}

public struct MCPAuthenticationChallenge: Codable, Equatable, Identifiable, Sendable {
    public let identifier: String
    public let connectionIdentifier: String
    public let nonce: Data
    public let transcript: Data

    public var id: String { identifier }

    public init(
        identifier: String,
        connectionIdentifier: String,
        nonce: Data,
        transcript: Data
    ) {
        self.identifier = identifier
        self.connectionIdentifier = connectionIdentifier
        self.nonce = nonce
        self.transcript = transcript
    }
}

public struct MCPAuthenticationProof: Codable, Equatable, Sendable {
    public let challengeIdentifier: String
    public let signature: Data

    public init(challengeIdentifier: String, signature: Data) {
        self.challengeIdentifier = challengeIdentifier
        self.signature = signature
    }
}

public enum MCPPairingReason: String, Codable, Equatable, Sendable {
    case firstPairing
    case identityChanged
}

public struct MCPPairingRequest: Codable, Equatable, Identifiable, Sendable {
    public let identifier: String
    public let presentation: MCPAuthenticationPresentation
    public let reason: MCPPairingReason
    public let previousIdentity: MCPCodeIdentity?
    public let requestedAt: Date

    public var id: String { identifier }
    public var requiresUnverifiedApprovalWarning: Bool {
        !presentation.parentIdentity.isSigned
    }

    public init(
        identifier: String,
        presentation: MCPAuthenticationPresentation,
        reason: MCPPairingReason,
        previousIdentity: MCPCodeIdentity?,
        requestedAt: Date
    ) {
        self.identifier = identifier
        self.presentation = presentation
        self.reason = reason
        self.previousIdentity = previousIdentity
        self.requestedAt = requestedAt
    }
}

public enum MCPAuthenticationResult: Equatable, Sendable {
    case authenticated(MCPTrustedClient)
    case approvalRequired(MCPPairingRequest)
}

public enum MCPPairingCoordinatorError: Error, Equatable, Sendable {
    case invalidPresentation
    case invalidNonce
    case nonceReuseDetected
    case authenticationCapacityExceeded
    case unknownChallenge
    case replayedChallenge
    case challengeExpired
    case invalidSignature
    case clientRevoked
    case pendingRequestNotFound
    case pairingCapacityExceeded
}

public enum MCPAuthenticationTranscript {
    private struct Payload: Codable {
        let domain: String
        let schemaVersion: Int
        let challengeIdentifier: String
        let connectionIdentifier: String
        let nonce: Data
        let presentation: MCPAuthenticationPresentation
    }

    public static func make(
        challengeIdentifier: String,
        connectionIdentifier: String,
        nonce: Data,
        presentation: MCPAuthenticationPresentation
    ) throws -> Data {
        let payload = Payload(
            domain: "com.rekurt.maccoffee.mcp.authentication.v1",
            schemaVersion: MCPContract.schemaVersion,
            challengeIdentifier: challengeIdentifier,
            connectionIdentifier: connectionIdentifier,
            nonce: nonce,
            presentation: presentation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }
}

public extension MCPCodeIdentity {
    func isMateriallyEquivalent(to other: MCPCodeIdentity) -> Bool {
        guard isSigned == other.isSigned else { return false }
        if isSigned {
            guard
                let teamIdentifier,
                !teamIdentifier.isEmpty,
                let signingIdentifier,
                !signingIdentifier.isEmpty
            else {
                return false
            }
            return teamIdentifier == other.teamIdentifier
                && signingIdentifier == other.signingIdentifier
        }

        guard
            let codeDirectoryHash,
            !codeDirectoryHash.isEmpty,
            let otherHash = other.codeDirectoryHash,
            !otherHash.isEmpty
        else {
            return false
        }
        return URL(fileURLWithPath: executablePath).standardizedFileURL.path
            == URL(fileURLWithPath: other.executablePath).standardizedFileURL.path
            && codeDirectoryHash == otherHash
    }
}

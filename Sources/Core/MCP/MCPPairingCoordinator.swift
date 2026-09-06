import Combine
import Foundation

@MainActor
public final class MCPPairingCoordinator: ObservableObject {
    @Published public private(set) var pendingRequests: [MCPPairingRequest] = []

    private struct ChallengeContext {
        let challenge: MCPAuthenticationChallenge
        let presentation: MCPAuthenticationPresentation
        let createdAt: Date
    }

    private static let nonceByteCount = 32
    private let trustStore: MCPTrustStore
    private let nonceGenerator: MCPNonceGenerating
    private let signatureVerifier: MCPSignatureVerifying
    private let now: () -> Date
    private let authenticationCapacity: Int
    private let pendingRequestCapacity: Int
    private let challengeLifetime: TimeInterval
    private let replayCacheCapacity: Int
    private var challenges: [String: ChallengeContext] = [:]
    private var usedNonces: Set<Data> = []
    private var usedNonceOrder: [Data] = []
    private var consumedChallengeIdentifiers: Set<String> = []
    private var consumedChallengeOrder: [String] = []

    public init(
        trustStore: MCPTrustStore,
        nonceGenerator: MCPNonceGenerating,
        signatureVerifier: MCPSignatureVerifying,
        now: @escaping () -> Date = Date.init,
        authenticationCapacity: Int = 64,
        pendingRequestCapacity: Int = 32,
        challengeLifetime: TimeInterval = 120,
        replayCacheCapacity: Int = 1_024
    ) {
        self.trustStore = trustStore
        self.nonceGenerator = nonceGenerator
        self.signatureVerifier = signatureVerifier
        self.now = now
        self.authenticationCapacity = max(1, authenticationCapacity)
        self.pendingRequestCapacity = max(1, pendingRequestCapacity)
        self.challengeLifetime = max(1, challengeLifetime)
        self.replayCacheCapacity = max(1, replayCacheCapacity)
    }

    public func beginAuthentication(
        _ presentation: MCPAuthenticationPresentation,
        connectionIdentifier: String
    ) throws -> MCPAuthenticationChallenge {
        guard isValid(presentation), isValidIdentifier(connectionIdentifier) else {
            throw MCPPairingCoordinatorError.invalidPresentation
        }
        let timestamp = now()
        pruneExpiredChallenges(asOf: timestamp)
        guard challenges.count < authenticationCapacity else {
            throw MCPPairingCoordinatorError.authenticationCapacityExceeded
        }

        let nonce = try nonceGenerator.nextNonce(byteCount: Self.nonceByteCount)
        guard nonce.count == Self.nonceByteCount else {
            throw MCPPairingCoordinatorError.invalidNonce
        }
        guard recordNonce(nonce) else {
            throw MCPPairingCoordinatorError.nonceReuseDetected
        }

        let challengeIdentifier = UUID().uuidString.lowercased()
        let transcript = try MCPAuthenticationTranscript.make(
            challengeIdentifier: challengeIdentifier,
            connectionIdentifier: connectionIdentifier,
            nonce: nonce,
            presentation: presentation
        )
        let challenge = MCPAuthenticationChallenge(
            identifier: challengeIdentifier,
            connectionIdentifier: connectionIdentifier,
            nonce: nonce,
            transcript: transcript
        )
        challenges[challengeIdentifier] = ChallengeContext(
            challenge: challenge,
            presentation: presentation,
            createdAt: timestamp
        )
        return challenge
    }

    public func completeAuthentication(
        _ proof: MCPAuthenticationProof
    ) throws -> MCPAuthenticationResult {
        if consumedChallengeIdentifiers.contains(proof.challengeIdentifier) {
            throw MCPPairingCoordinatorError.replayedChallenge
        }
        guard let context = challenges.removeValue(forKey: proof.challengeIdentifier) else {
            throw MCPPairingCoordinatorError.unknownChallenge
        }
        recordConsumedChallenge(proof.challengeIdentifier)
        guard now().timeIntervalSince(context.createdAt) <= challengeLifetime else {
            throw MCPPairingCoordinatorError.challengeExpired
        }

        guard signatureVerifier.verify(
            signature: proof.signature,
            message: context.challenge.transcript,
            publicKey: context.presentation.publicKey
        ) else {
            throw MCPPairingCoordinatorError.invalidSignature
        }

        if let trusted = try trustStore.client(
            identifier: context.presentation.clientIdentifier
        ) {
            guard !trusted.isRevoked else {
                throw MCPPairingCoordinatorError.clientRevoked
            }
            guard
                trusted.publicKey == context.presentation.publicKey,
                trusted.codeIdentity.isMateriallyEquivalent(
                    to: context.presentation.parentIdentity
                )
            else {
                return .approvalRequired(
                    try createPendingRequest(
                        presentation: context.presentation,
                        reason: .identityChanged,
                        previousIdentity: trusted.codeIdentity
                    )
                )
            }

            _ = try trustStore.markSeen(
                identifier: trusted.identifier,
                at: now()
            )
            guard let refreshed = try trustStore.client(identifier: trusted.identifier) else {
                throw MCPPairingCoordinatorError.invalidPresentation
            }
            return .authenticated(refreshed)
        }

        return .approvalRequired(
            try createPendingRequest(
                presentation: context.presentation,
                reason: .firstPairing,
                previousIdentity: nil
            )
        )
    }

    public func approve(requestIdentifier: String) throws -> MCPTrustedClient {
        guard let request = pendingRequests.first(where: {
            $0.identifier == requestIdentifier
        }) else {
            throw MCPPairingCoordinatorError.pendingRequestNotFound
        }
        let existing = try trustStore.client(
            identifier: request.presentation.clientIdentifier
        )
        if existing?.isRevoked == true {
            throw MCPPairingCoordinatorError.clientRevoked
        }
        let approvalDate = now()
        let client = MCPTrustedClient(
            identifier: request.presentation.clientIdentifier,
            displayName: request.presentation.displayName,
            publicKey: request.presentation.publicKey,
            codeIdentity: request.presentation.parentIdentity,
            createdAt: existing?.createdAt ?? approvalDate,
            lastSeenAt: approvalDate,
            revokedAt: nil
        )
        try trustStore.trust(client)
        pendingRequests.removeAll { $0.identifier == requestIdentifier }
        return client
    }

    @discardableResult
    public func reject(requestIdentifier: String) -> Bool {
        let originalCount = pendingRequests.count
        pendingRequests.removeAll { $0.identifier == requestIdentifier }
        return pendingRequests.count != originalCount
    }

    private func createPendingRequest(
        presentation: MCPAuthenticationPresentation,
        reason: MCPPairingReason,
        previousIdentity: MCPCodeIdentity?
    ) throws -> MCPPairingRequest {
        let replacesExistingRequest = pendingRequests.contains {
            $0.presentation.clientIdentifier == presentation.clientIdentifier
        }
        guard replacesExistingRequest || pendingRequests.count < pendingRequestCapacity else {
            throw MCPPairingCoordinatorError.pairingCapacityExceeded
        }
        pendingRequests.removeAll {
            $0.presentation.clientIdentifier == presentation.clientIdentifier
        }
        let request = MCPPairingRequest(
            identifier: UUID().uuidString.lowercased(),
            presentation: presentation,
            reason: reason,
            previousIdentity: previousIdentity,
            requestedAt: now()
        )
        pendingRequests.append(request)
        return request
    }

    private func recordConsumedChallenge(_ identifier: String) {
        consumedChallengeIdentifiers.insert(identifier)
        consumedChallengeOrder.append(identifier)
        if consumedChallengeOrder.count > replayCacheCapacity {
            let evicted = consumedChallengeOrder.removeFirst()
            consumedChallengeIdentifiers.remove(evicted)
        }
    }

    private func recordNonce(_ nonce: Data) -> Bool {
        guard usedNonces.insert(nonce).inserted else { return false }
        usedNonceOrder.append(nonce)
        if usedNonceOrder.count > replayCacheCapacity {
            let evicted = usedNonceOrder.removeFirst()
            usedNonces.remove(evicted)
        }
        return true
    }

    private func pruneExpiredChallenges(asOf timestamp: Date) {
        let expiredIdentifiers = challenges.compactMap { identifier, context in
            timestamp.timeIntervalSince(context.createdAt) > challengeLifetime
                ? identifier
                : nil
        }
        for identifier in expiredIdentifiers {
            challenges.removeValue(forKey: identifier)
            recordConsumedChallenge(identifier)
        }
    }

    private func isValid(_ presentation: MCPAuthenticationPresentation) -> Bool {
        guard
            isValidIdentifier(presentation.clientIdentifier),
            !presentation.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            presentation.displayName.count <= 128,
            !presentation.publicKey.isEmpty,
            presentation.publicKey.count <= 512,
            presentation.parentIdentity.executablePath.hasPrefix("/")
        else {
            return false
        }
        if presentation.parentIdentity.isSigned {
            return presentation.parentIdentity.teamIdentifier?.isEmpty == false
                && presentation.parentIdentity.signingIdentifier?.isEmpty == false
        }
        return presentation.parentIdentity.codeDirectoryHash?.isEmpty == false
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 256
    }
}

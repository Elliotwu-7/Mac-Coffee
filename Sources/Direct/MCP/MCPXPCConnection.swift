import Foundation
import MacCoffeeCore

public final class MCPXPCConnection: NSObject, MCPXPCAppService, @unchecked Sendable {
    private struct State {
        var authenticatedClient: MCPTrustedClient?
        var pendingRequestIdentifiers: Set<String> = []
        var subscriptions: [String: MCPStatusSubscriptionToken] = [:]
        var isClosed = false
    }

    private let connection: NSXPCConnection
    private let pairingCoordinator: MCPPairingCoordinator
    private let controlService: MCPControlService
    private let onClosed: @Sendable () -> Void
    private let stateLock = NSLock()
    private var state = State()

    public init(
        connection: NSXPCConnection,
        pairingCoordinator: MCPPairingCoordinator,
        controlService: MCPControlService,
        onClosed: @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.pairingCoordinator = pairingCoordinator
        self.controlService = controlService
        self.onClosed = onClosed
        super.init()
    }

    public var authenticatedClientIdentifier: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.authenticatedClient?.identifier
    }

    public func beginAuthentication(
        _ hello: MCPXPCAuthenticationHello,
        withReply reply: @escaping (MCPXPCAuthenticationChallenge?, MCPXPCError?) -> Void
    ) {
        let reply = AuthenticationChallengeReply(reply)
        Task { @MainActor [weak self] in
            guard let self, !self.isClosed else {
                reply.call(nil, Self.error(code: .appNotRunning))
                return
            }
            do {
                let presentation = try MCPXPCCodec.decodeAuthenticationHello(hello)
                let challenge = try pairingCoordinator.beginAuthentication(
                    presentation,
                    connectionIdentifier: hello.connectionIdentifier
                )
                let value = MCPXPCAuthenticationChallenge(
                    schemaVersion: MCPContract.schemaVersion,
                    challengeIdentifier: challenge.identifier,
                    nonce: challenge.nonce,
                    transcript: challenge.transcript
                )
                try MCPXPCCodec.validate(value)
                reply.call(value, nil)
            } catch {
                reply.call(nil, Self.map(error))
            }
        }
    }

    public func completeAuthentication(
        _ proof: MCPXPCAuthenticationProof,
        withReply reply: @escaping (MCPXPCAuthenticationResult?, MCPXPCError?) -> Void
    ) {
        let reply = AuthenticationResultReply(reply)
        Task { @MainActor [weak self] in
            guard let self, !self.isClosed else {
                reply.call(nil, Self.error(code: .appNotRunning))
                return
            }
            do {
                try MCPXPCCodec.validate(proof)
                let result = try pairingCoordinator.completeAuthentication(
                    MCPAuthenticationProof(
                        challengeIdentifier: proof.challengeIdentifier,
                        signature: proof.signature
                    )
                )
                let value: MCPXPCAuthenticationResult
                switch result {
                case let .authenticated(client):
                    self.setAuthenticatedClient(client)
                    value = MCPXPCAuthenticationResult(
                        schemaVersion: MCPContract.schemaVersion,
                        state: .authenticated,
                        clientJSON: try JSONEncoder().encode(client),
                        pairingRequestJSON: nil
                    )
                case let .approvalRequired(request):
                    value = MCPXPCAuthenticationResult(
                        schemaVersion: MCPContract.schemaVersion,
                        state: .approvalRequired,
                        clientJSON: nil,
                        pairingRequestJSON: try JSONEncoder().encode(request)
                    )
                }
                try MCPXPCCodec.validate(value)
                reply.call(value, nil)
            } catch {
                reply.call(nil, Self.map(error))
            }
        }
    }

    public func perform(
        _ request: MCPXPCRequest,
        withReply reply: @escaping (MCPXPCResponse) -> Void
    ) {
        let reply = ResponseReply(reply)
        let client: MCPTrustedClient
        do {
            client = try requireAuthenticatedClient()
            _ = try MCPXPCCodec.decodeRequest(
                request,
                authenticatedClientIdentifier: client.identifier,
                now: Date()
            )
            guard registerPendingRequest(request.requestIdentifier) else {
                throw MCPXPCCodecError.invalidField("requestIdentifier")
            }
        } catch {
            reply.call(Self.failureResponse(for: request.requestIdentifier, error: error))
            return
        }

        let action = request.action
        let payloadJSON = request.payloadJSON
        let requestIdentifier = request.requestIdentifier
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.consumePendingRequest(requestIdentifier) else { return }
            do {
                let clientContext = MCPClientContext(
                    identifier: client.identifier,
                    displayName: client.displayName
                )
                let responsePayload: Data
                switch MCPXPCAction(rawValue: action) {
                case .readStatus:
                    responsePayload = try JSONEncoder().encode(
                        controlService.readStatus(client: clientContext)
                    )
                case .readActivity:
                    responsePayload = try JSONEncoder().encode(
                        controlService.readActivity(client: clientContext)
                    )
                case nil:
                    let command = try MCPCommandParser.parse(
                        toolName: action,
                        argumentsJSON: payloadJSON
                    )
                    responsePayload = try JSONEncoder().encode(
                        try controlService.execute(command, client: clientContext)
                    )
                }
                let response = MCPXPCResponse(
                    schemaVersion: MCPContract.schemaVersion,
                    requestIdentifier: requestIdentifier,
                    payloadJSON: responsePayload,
                    error: nil
                )
                try MCPXPCCodec.validate(response)
                reply.call(response)
            } catch {
                reply.call(Self.failureResponse(for: requestIdentifier, error: error))
            }
        }
    }

    public func subscribe(
        _ request: MCPXPCSubscription,
        withReply reply: @escaping (MCPXPCResponse) -> Void
    ) {
        let reply = ResponseReply(reply)
        let client: MCPTrustedClient
        do {
            client = try requireAuthenticatedClient()
            _ = try MCPXPCCodec.decodeSubscription(
                request,
                authenticatedClientIdentifier: client.identifier,
                now: Date()
            )
        } catch {
            reply.call(Self.failureResponse(for: request.subscriptionIdentifier, error: error))
            return
        }

        let subscriptionIdentifier = request.subscriptionIdentifier
        Task { @MainActor [weak self] in
            guard let self, !self.isClosed else {
                reply.call(Self.failureResponse(
                    for: subscriptionIdentifier,
                    error: MCPServiceError(code: .appNotRunning)
                ))
                return
            }
            let token = controlService.statusPublisher.subscribe(
                client: MCPClientContext(
                    identifier: client.identifier,
                    displayName: client.displayName
                )
            ) { [weak self] envelope in
                guard let self,
                      let payload = try? JSONEncoder().encode(envelope) else { return }
                self.send(
                    MCPXPCEvent(
                        schemaVersion: MCPContract.schemaVersion,
                        subscriptionIdentifier: subscriptionIdentifier,
                        sequence: Int64(clamping: envelope.sequence),
                        payloadJSON: payload
                    )
                )
            }
            guard self.storeSubscription(
                token,
                identifier: subscriptionIdentifier
            ) else {
                controlService.statusPublisher.cancel(token)
                reply.call(Self.failureResponse(
                    for: subscriptionIdentifier,
                    error: MCPXPCCodecError.invalidField("subscriptionIdentifier")
                ))
                return
            }
            reply.call(MCPXPCResponse(
                schemaVersion: MCPContract.schemaVersion,
                requestIdentifier: subscriptionIdentifier,
                payloadJSON: Data("{\"subscribed\":true}".utf8),
                error: nil
            ))
        }
    }

    public func cancel(_ request: MCPXPCCancellation) {
        guard (try? MCPXPCCodec.validate(request)) != nil else { return }
        let token: MCPStatusSubscriptionToken?
        stateLock.lock()
        state.pendingRequestIdentifiers.remove(request.requestIdentifier)
        token = state.subscriptions.removeValue(forKey: request.requestIdentifier)
        stateLock.unlock()
        if let token {
            Task { @MainActor [controlService] in
                controlService.statusPublisher.cancel(token)
            }
        }
    }

    public func close(_ request: MCPXPCClose) {
        guard (try? MCPXPCCodec.validate(request)) != nil else { return }
        close(reason: request.reason)
    }

    public func close(reason: MCPXPCCloseReason) {
        let tokens = transitionToClosed()
        guard tokens != nil else { return }
        cancelSubscriptions(tokens ?? [])

        let close = MCPXPCClose(
            schemaVersion: MCPContract.schemaVersion,
            reason: reason,
            message: nil
        )
        guard let callback = callbackProxy() else {
            connection.invalidate()
            onClosed()
            return
        }
        let connection = connection
        let onClosed = onClosed
        let completion = CloseCompletion(connection: connection, onClosed: onClosed)
        callback.closed(close) {
            completion.finish()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            completion.finish()
        }
    }

    public func connectionInvalidated() {
        let tokens = transitionToClosed()
        guard let tokens else { return }
        cancelSubscriptions(tokens)
        onClosed()
    }

    public func connectionInterrupted() {
        connectionInvalidated()
    }

    private var isClosed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.isClosed
    }

    private func setAuthenticatedClient(_ client: MCPTrustedClient) {
        stateLock.lock()
        if !state.isClosed {
            state.authenticatedClient = client
        }
        stateLock.unlock()
    }

    private func requireAuthenticatedClient() throws -> MCPTrustedClient {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !state.isClosed else {
            throw MCPServiceError(code: .appNotRunning)
        }
        guard let client = state.authenticatedClient else {
            throw MCPServiceError(code: .clientUnpaired)
        }
        return client
    }

    private func registerPendingRequest(_ identifier: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !state.isClosed else { return false }
        return state.pendingRequestIdentifiers.insert(identifier).inserted
    }

    private func consumePendingRequest(_ identifier: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !state.isClosed else { return false }
        return state.pendingRequestIdentifiers.remove(identifier) != nil
    }

    private func storeSubscription(
        _ token: MCPStatusSubscriptionToken,
        identifier: String
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !state.isClosed, state.subscriptions[identifier] == nil else {
            return false
        }
        state.subscriptions[identifier] = token
        return true
    }

    private func transitionToClosed() -> [MCPStatusSubscriptionToken]? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !state.isClosed else { return nil }
        state.isClosed = true
        state.authenticatedClient = nil
        state.pendingRequestIdentifiers.removeAll()
        let tokens = Array(state.subscriptions.values)
        state.subscriptions.removeAll()
        return tokens
    }

    private func cancelSubscriptions(_ tokens: [MCPStatusSubscriptionToken]) {
        guard !tokens.isEmpty else { return }
        Task { @MainActor [controlService] in
            for token in tokens {
                controlService.statusPublisher.cancel(token)
            }
        }
    }

    private func send(_ event: MCPXPCEvent) {
        guard (try? MCPXPCCodec.validate(event)) != nil else { return }
        callbackProxy()?.receive(event)
    }

    private func callbackProxy() -> MCPXPCHelperCallback? {
        connection.remoteObjectProxyWithErrorHandler { _ in } as? MCPXPCHelperCallback
    }

    private static func failureResponse(
        for identifier: String,
        error: Error
    ) -> MCPXPCResponse {
        MCPXPCResponse(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: identifier,
            payloadJSON: nil,
            error: map(error)
        )
    }

    private static func map(_ error: Error) -> MCPXPCError {
        if let serviceError = error as? MCPServiceError {
            return self.error(
                code: serviceError.code,
                message: serviceError.field
            )
        }
        if let pairingError = error as? MCPPairingCoordinatorError {
            switch pairingError {
            case .clientRevoked:
                return self.error(code: .clientRevoked)
            default:
                return self.error(code: .clientUnpaired)
            }
        }
        if let codecError = error as? MCPXPCCodecError {
            switch codecError {
            case .unsupportedSchemaVersion:
                return self.error(code: .versionMismatch)
            case .authenticationRequired:
                return self.error(code: .clientUnpaired)
            case .deadlineExpired:
                return self.error(code: .invalidArgument, message: "deadline")
            case let .invalidField(field):
                return self.error(code: .invalidArgument, message: field)
            case .payloadTooLarge, .malformedJSON:
                return self.error(code: .invalidArgument, message: "payload")
            }
        }
        return self.error(code: .internalError)
    }

    private static func error(
        code: MCPErrorCode,
        message: String? = nil
    ) -> MCPXPCError {
        MCPXPCError(
            code: code.rawValue,
            message: message ?? code.rawValue,
            retryable: code.isRetryable
        )
    }
}

private final class AuthenticationChallengeReply: @unchecked Sendable {
    private let block: (MCPXPCAuthenticationChallenge?, MCPXPCError?) -> Void

    init(_ block: @escaping (MCPXPCAuthenticationChallenge?, MCPXPCError?) -> Void) {
        self.block = block
    }

    func call(_ value: MCPXPCAuthenticationChallenge?, _ error: MCPXPCError?) {
        block(value, error)
    }
}

private final class AuthenticationResultReply: @unchecked Sendable {
    private let block: (MCPXPCAuthenticationResult?, MCPXPCError?) -> Void

    init(_ block: @escaping (MCPXPCAuthenticationResult?, MCPXPCError?) -> Void) {
        self.block = block
    }

    func call(_ value: MCPXPCAuthenticationResult?, _ error: MCPXPCError?) {
        block(value, error)
    }
}

private final class ResponseReply: @unchecked Sendable {
    private let block: (MCPXPCResponse) -> Void

    init(_ block: @escaping (MCPXPCResponse) -> Void) {
        self.block = block
    }

    func call(_ value: MCPXPCResponse) {
        block(value)
    }
}

private final class CloseCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let connection: NSXPCConnection
    private let onClosed: @Sendable () -> Void

    init(
        connection: NSXPCConnection,
        onClosed: @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.onClosed = onClosed
    }

    func finish() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        connection.invalidate()
        onClosed()
    }
}

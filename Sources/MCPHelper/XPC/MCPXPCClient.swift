import Foundation
import MacCoffeeCore

public protocol MCPXPCClientCredentialProviding: Sendable {
    func authenticationPresentation() throws -> MCPAuthenticationPresentation
    func sign(_ transcript: Data) throws -> Data
}

public protocol MCPXPCAppEndpointProviding: Sendable {
    func currentEndpoint() async throws -> NSXPCListenerEndpoint
}

public enum MCPXPCClientAuthorization: Equatable, Sendable {
    case authenticated(MCPTrustedClient)
    case approvalRequired(MCPPairingRequest)
}

public enum MCPXPCClientError: Error, Equatable, Sendable {
    case appNotRunning
    case clientUnpaired
    case clientRevoked
    case mcpDisabled
    case timedOut
    case cancelled
    case protocolViolation
    case remote(code: String, message: String, retryable: Bool)
}

public final class MCPXPCClientSubscription: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?

    init(cancellation: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
    }

    public func cancel() {
        lock.lock()
        let cancellation = cancellation
        self.cancellation = nil
        lock.unlock()
        cancellation?()
    }

    deinit {
        cancel()
    }
}

public final class MCPXPCClient: @unchecked Sendable {
    public typealias EventHandler = @Sendable (
        Result<Data, MCPXPCClientError>
    ) -> Void
    public typealias CloseHandler = @Sendable (MCPXPCCloseReason) -> Void

    private struct State {
        var connection: NSXPCConnection?
        var callback: MCPXPCClientCallback?
        var authorization: MCPXPCClientAuthorization?
        var terminalError: MCPXPCClientError?
        var eventHandlers: [String: EventHandler] = [:]
    }

    private let endpointProvider: MCPXPCAppEndpointProviding
    private let credentials: MCPXPCClientCredentialProviding
    private let defaultTimeout: TimeInterval
    private let closeHandler: CloseHandler
    private let stateLock = NSLock()
    private var state = State()

    public init(
        endpointProvider: MCPXPCAppEndpointProviding,
        credentials: MCPXPCClientCredentialProviding,
        defaultTimeout: TimeInterval = 5,
        closeHandler: @escaping CloseHandler = { _ in }
    ) {
        self.endpointProvider = endpointProvider
        self.credentials = credentials
        self.defaultTimeout = min(30, max(0.05, defaultTimeout))
        self.closeHandler = closeHandler
    }

    public func connect() async throws -> MCPXPCClientAuthorization {
        let endpoint: NSXPCListenerEndpoint
        do {
            endpoint = try await endpointProvider.currentEndpoint()
        } catch {
            throw MCPXPCClientError.appNotRunning
        }

        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        let callback = MCPXPCClientCallback()
        callback.owner = self
        connection.remoteObjectInterface = MCPXPCInterfaces.appService()
        connection.exportedInterface = MCPXPCInterfaces.helperCallback()
        connection.exportedObject = callback
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let connection else { return }
            self?.connectionInvalidated(connection)
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let connection else { return }
            self?.connectionInvalidated(connection)
        }

        replaceConnection(with: connection, callback: callback)
        connection.activate()

        do {
            let presentation = try credentials.authenticationPresentation()
            let hello = MCPXPCAuthenticationHello(
                schemaVersion: MCPContract.schemaVersion,
                connectionIdentifier: UUID().uuidString.lowercased(),
                presentationJSON: try JSONEncoder().encode(presentation)
            )
            let challenge = try await beginAuthentication(
                hello,
                connection: connection
            )
            try MCPXPCCodec.validate(challenge)
            let proof = MCPXPCAuthenticationProof(
                schemaVersion: MCPContract.schemaVersion,
                challengeIdentifier: challenge.challengeIdentifier,
                signature: try credentials.sign(challenge.transcript)
            )
            let result = try await completeAuthentication(
                proof,
                connection: connection
            )
            try MCPXPCCodec.validate(result)

            let authorization: MCPXPCClientAuthorization
            switch result.state {
            case .authenticated:
                guard let data = result.clientJSON,
                      let client = try? JSONDecoder().decode(
                        MCPTrustedClient.self,
                        from: data
                      ) else {
                    throw MCPXPCClientError.protocolViolation
                }
                authorization = .authenticated(client)
            case .approvalRequired:
                guard let data = result.pairingRequestJSON,
                      let request = try? JSONDecoder().decode(
                        MCPPairingRequest.self,
                        from: data
                      ) else {
                    throw MCPXPCClientError.protocolViolation
                }
                authorization = .approvalRequired(request)
            }
            setAuthorization(authorization, for: connection)
            return authorization
        } catch {
            if let error = error as? MCPXPCClientError {
                if error != .clientUnpaired {
                    invalidateIfCurrent(connection)
                }
                throw error
            }
            invalidateIfCurrent(connection)
            throw MCPXPCClientError.protocolViolation
        }
    }

    public func perform(
        action: String,
        payloadJSON: Data,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        let connection = try authenticatedConnection()
        let connectionReference = MCPXPCConnectionReference(connection)
        let requestIdentifier = UUID().uuidString.lowercased()
        let timeout = boundedTimeout(timeout)
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: requestIdentifier,
            action: action,
            payloadJSON: payloadJSON,
            deadline: Date().addingTimeInterval(timeout)
        )
        let response: MCPXPCResponse = try await awaitReply(
            timeout: timeout,
            onTimeoutOrCancellation: { [weak self, connectionReference] in
                guard let self, let connection = connectionReference.connection else { return }
                self.sendCancellation(
                    identifier: requestIdentifier,
                    connection: connection
                )
            }
        ) { [weak self, weak connection, connectionReference] reply in
            guard let self, let connection else {
                reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                return
            }
            guard let proxy = self.proxy(
                for: connection,
                errorHandler: { _ in
                    reply.resolve(.failure(self.currentTerminalError(
                        for: connectionReference.connection
                    ) ?? .appNotRunning))
                }
            ) else {
                reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                return
            }
            proxy.perform(request) { reply.resolve(.success($0)) }
        }
        return try payload(from: response)
    }

    public func subscribeStatus(
        timeout: TimeInterval? = nil,
        handler: @escaping EventHandler
    ) async throws -> MCPXPCClientSubscription {
        let connection = try authenticatedConnection()
        let connectionReference = MCPXPCConnectionReference(connection)
        let identifier = UUID().uuidString.lowercased()
        let timeout = boundedTimeout(timeout)
        storeEventHandler(handler, identifier: identifier, connection: connection)
        let request = MCPXPCSubscription(
            schemaVersion: MCPContract.schemaVersion,
            subscriptionIdentifier: identifier,
            resourceURI: MCPResourceURI.status.rawValue,
            deadline: Date().addingTimeInterval(timeout)
        )
        do {
            let response: MCPXPCResponse = try await awaitReply(
                timeout: timeout,
                onTimeoutOrCancellation: { [weak self, connectionReference] in
                    guard let self, let connection = connectionReference.connection else { return }
                    self.sendCancellation(identifier: identifier, connection: connection)
                }
            ) { [weak self, weak connection, connectionReference] reply in
                guard let self, let connection,
                      let proxy = self.proxy(
                        for: connection,
                        errorHandler: { _ in
                            reply.resolve(.failure(self.currentTerminalError(
                                for: connectionReference.connection
                            ) ?? .appNotRunning))
                        }
                      ) else {
                    reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                    return
                }
                proxy.subscribe(request) { reply.resolve(.success($0)) }
            }
            _ = try payload(from: response)
        } catch {
            removeEventHandler(identifier: identifier)
            throw error
        }
        return MCPXPCClientSubscription { [weak self, connectionReference] in
            guard let self, let connection = connectionReference.connection else { return }
            self.removeEventHandler(identifier: identifier)
            self.sendCancellation(identifier: identifier, connection: connection)
        }
    }

    public func disconnect() {
        let connection: NSXPCConnection?
        stateLock.lock()
        connection = state.connection
        state.connection = nil
        state.callback = nil
        state.authorization = nil
        state.terminalError = .appNotRunning
        let handlers = Array(state.eventHandlers.values)
        state.eventHandlers.removeAll()
        stateLock.unlock()
        for handler in handlers {
            handler(.failure(.appNotRunning))
        }
        if let connection {
            let close = MCPXPCClose(
                schemaVersion: MCPContract.schemaVersion,
                reason: .clientRequest,
                message: nil
            )
            proxy(for: connection, errorHandler: { _ in })?.close(close)
            connection.invalidate()
        }
    }

    fileprivate func receive(_ event: MCPXPCEvent) {
        guard (try? MCPXPCCodec.validate(event)) != nil else { return }
        stateLock.lock()
        let handler = state.eventHandlers[event.subscriptionIdentifier]
        stateLock.unlock()
        handler?(.success(event.payloadJSON))
    }

    fileprivate func closed(_ close: MCPXPCClose) {
        guard (try? MCPXPCCodec.validate(close)) != nil else { return }
        let error = Self.error(for: close.reason)
        stateLock.lock()
        state.authorization = nil
        state.terminalError = error
        let handlers = Array(state.eventHandlers.values)
        state.eventHandlers.removeAll()
        stateLock.unlock()
        for handler in handlers {
            handler(.failure(error))
        }
        closeHandler(close.reason)
    }

    private func beginAuthentication(
        _ hello: MCPXPCAuthenticationHello,
        connection: NSXPCConnection
    ) async throws -> MCPXPCAuthenticationChallenge {
        let connectionReference = MCPXPCConnectionReference(connection)
        return try await awaitReply(
            timeout: defaultTimeout,
            onTimeoutOrCancellation: { [connectionReference] in
                connectionReference.connection?.invalidate()
            }
        ) { [weak self, weak connection] reply in
            guard let self, let connection,
                  let proxy = self.proxy(
                    for: connection,
                    errorHandler: { _ in
                        reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                    }
                  ) else {
                reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                return
            }
            proxy.beginAuthentication(hello) { challenge, error in
                if let error {
                    reply.resolve(.failure(Self.map(error)))
                } else if let challenge {
                    reply.resolve(.success(challenge))
                } else {
                    reply.resolve(.failure(MCPXPCClientError.protocolViolation))
                }
            }
        }
    }

    private func completeAuthentication(
        _ proof: MCPXPCAuthenticationProof,
        connection: NSXPCConnection
    ) async throws -> MCPXPCAuthenticationResult {
        let connectionReference = MCPXPCConnectionReference(connection)
        return try await awaitReply(
            timeout: defaultTimeout,
            onTimeoutOrCancellation: { [connectionReference] in
                connectionReference.connection?.invalidate()
            }
        ) { [weak self, weak connection] reply in
            guard let self, let connection,
                  let proxy = self.proxy(
                    for: connection,
                    errorHandler: { _ in
                        reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                    }
                  ) else {
                reply.resolve(.failure(MCPXPCClientError.appNotRunning))
                return
            }
            proxy.completeAuthentication(proof) { result, error in
                if let error {
                    reply.resolve(.failure(Self.map(error)))
                } else if let result {
                    reply.resolve(.success(result))
                } else {
                    reply.resolve(.failure(MCPXPCClientError.protocolViolation))
                }
            }
        }
    }

    private func authenticatedConnection() throws -> NSXPCConnection {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let terminalError = state.terminalError {
            throw terminalError
        }
        guard let connection = state.connection else {
            throw MCPXPCClientError.appNotRunning
        }
        guard case .authenticated = state.authorization else {
            throw MCPXPCClientError.clientUnpaired
        }
        return connection
    }

    private func replaceConnection(
        with connection: NSXPCConnection,
        callback: MCPXPCClientCallback
    ) {
        stateLock.lock()
        let oldConnection = state.connection
        let oldHandlers = Array(state.eventHandlers.values)
        state = State(connection: connection, callback: callback)
        stateLock.unlock()
        oldConnection?.invalidate()
        for handler in oldHandlers {
            handler(.failure(.appNotRunning))
        }
    }

    private func setAuthorization(
        _ authorization: MCPXPCClientAuthorization,
        for connection: NSXPCConnection
    ) {
        stateLock.lock()
        guard state.connection === connection else {
            stateLock.unlock()
            return
        }
        state.authorization = authorization
        switch authorization {
        case .authenticated:
            state.terminalError = nil
        case .approvalRequired:
            state.terminalError = .clientUnpaired
        }
        stateLock.unlock()
    }

    private func invalidateIfCurrent(_ connection: NSXPCConnection) {
        stateLock.lock()
        let isCurrent = state.connection === connection
        if isCurrent {
            state.connection = nil
            state.callback = nil
            state.authorization = nil
        }
        stateLock.unlock()
        connection.invalidate()
    }

    private func connectionInvalidated(_ connection: NSXPCConnection) {
        stateLock.lock()
        guard state.connection === connection else {
            stateLock.unlock()
            return
        }
        state.connection = nil
        state.callback = nil
        state.authorization = nil
        if state.terminalError == nil {
            state.terminalError = .appNotRunning
        }
        let error = state.terminalError ?? .appNotRunning
        let handlers = Array(state.eventHandlers.values)
        state.eventHandlers.removeAll()
        stateLock.unlock()
        for handler in handlers {
            handler(.failure(error))
        }
    }

    private func currentTerminalError(
        for connection: NSXPCConnection?
    ) -> MCPXPCClientError? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard state.connection === connection || state.connection == nil else {
            return .appNotRunning
        }
        return state.terminalError
    }

    private func storeEventHandler(
        _ handler: @escaping EventHandler,
        identifier: String,
        connection: NSXPCConnection
    ) {
        stateLock.lock()
        if state.connection === connection {
            state.eventHandlers[identifier] = handler
        }
        stateLock.unlock()
    }

    private func removeEventHandler(identifier: String) {
        stateLock.lock()
        state.eventHandlers.removeValue(forKey: identifier)
        stateLock.unlock()
    }

    private func sendCancellation(
        identifier: String,
        connection: NSXPCConnection
    ) {
        let cancellation = MCPXPCCancellation(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: identifier
        )
        proxy(for: connection, errorHandler: { _ in })?.cancel(cancellation)
    }

    private func proxy(
        for connection: NSXPCConnection,
        errorHandler: @escaping @Sendable (Error) -> Void
    ) -> MCPXPCAppService? {
        connection.remoteObjectProxyWithErrorHandler(errorHandler) as? MCPXPCAppService
    }

    private func payload(from response: MCPXPCResponse) throws -> Data {
        do {
            try MCPXPCCodec.validate(response)
        } catch {
            throw MCPXPCClientError.protocolViolation
        }
        if let error = response.error {
            throw Self.map(error)
        }
        guard let payload = response.payloadJSON else {
            throw MCPXPCClientError.protocolViolation
        }
        return payload
    }

    private func boundedTimeout(_ value: TimeInterval?) -> TimeInterval {
        min(30, max(0.05, value ?? defaultTimeout))
    }

    private func awaitReply<Value: Sendable>(
        timeout: TimeInterval,
        onTimeoutOrCancellation: @escaping @Sendable () -> Void,
        start: @escaping (
            MCPXPCReplyGate<Value>
        ) -> Void
    ) async throws -> Value {
        let gate = MCPXPCReplyGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                start(gate)
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + timeout
                ) {
                    if gate.resolve(.failure(MCPXPCClientError.timedOut)) {
                        onTimeoutOrCancellation()
                    }
                }
            }
        } onCancel: {
            if gate.resolve(.failure(MCPXPCClientError.cancelled)) {
                onTimeoutOrCancellation()
            }
        }
    }

    private static func map(_ error: MCPXPCError) -> MCPXPCClientError {
        guard let code = MCPErrorCode(rawValue: error.code) else {
            return .remote(
                code: error.code,
                message: error.message,
                retryable: error.retryable
            )
        }
        switch code {
        case .appNotRunning:
            return .appNotRunning
        case .clientUnpaired:
            return .clientUnpaired
        case .clientRevoked:
            return .clientRevoked
        case .mcpDisabled:
            return .mcpDisabled
        default:
            return .remote(
                code: error.code,
                message: error.message,
                retryable: error.retryable
            )
        }
    }

    private static func error(for reason: MCPXPCCloseReason) -> MCPXPCClientError {
        switch reason {
        case .clientRevoked:
            .clientRevoked
        case .integrationDisabled:
            .mcpDisabled
        case .clientRequest, .protocolError, .appTermination:
            .appNotRunning
        }
    }
}

private final class MCPXPCConnectionReference: @unchecked Sendable {
    weak var connection: NSXPCConnection?

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }
}

private final class MCPXPCClientCallback: NSObject, MCPXPCHelperCallback,
    @unchecked Sendable {
    weak var owner: MCPXPCClient?

    func receive(_ event: MCPXPCEvent) {
        owner?.receive(event)
    }

    func closed(_ close: MCPXPCClose, withReply reply: @escaping () -> Void) {
        owner?.closed(close)
        reply()
    }
}

private final class MCPXPCReplyGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return false
        }
        isResolved = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            pendingResult = result
            lock.unlock()
        }
        return true
    }
}

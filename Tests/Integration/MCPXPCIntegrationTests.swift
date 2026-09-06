import CryptoKit
import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPXPCIntegrationTests: XCTestCase {
    func testMissingEndpointReportsAppNotRunningWithoutCreatingOrLaunchingAnything() async {
        let client = MCPXPCClient(
            endpointProvider: UnavailableEndpointProvider(),
            credentials: TestClientCredentials(),
            defaultTimeout: 0.2
        )

        await assertClientError(.appNotRunning) {
            try await client.connect()
        }
    }

    func testInvalidatedEndpointReportsAppNotRunning() async throws {
        let listener = NSXPCListener.anonymous()
        let endpoint = listener.endpoint
        listener.activate()
        listener.invalidate()
        let client = MCPXPCClient(
            endpointProvider: StaticEndpointProvider(endpoint: endpoint),
            credentials: TestClientCredentials(),
            defaultTimeout: 0.2
        )

        await assertClientError(.appNotRunning) {
            try await client.connect()
        }
    }

    func testUnauthenticatedConnectionCannotReadStatus() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: true)
        system.start()
        defer { system.stop(reason: .appTermination) }

        let connection = NSXPCConnection(listenerEndpoint: try await system.provider.currentEndpoint())
        let callback = RecordingHelperCallback()
        connection.remoteObjectInterface = MCPXPCInterfaces.appService()
        connection.exportedInterface = MCPXPCInterfaces.helperCallback()
        connection.exportedObject = callback
        connection.activate()
        defer { connection.invalidate() }
        let proxy = try XCTUnwrap(
            connection.remoteObjectProxyWithErrorHandler { _ in } as? MCPXPCAppService
        )
        let request = MCPXPCRequest(
            schemaVersion: MCPContract.schemaVersion,
            requestIdentifier: UUID().uuidString,
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8),
            deadline: Date().addingTimeInterval(1)
        )
        let response = await withCheckedContinuation { continuation in
            proxy.perform(request) { continuation.resume(returning: $0) }
        }

        XCTAssertNil(response.payloadJSON)
        XCTAssertEqual(response.error?.code, MCPErrorCode.clientUnpaired.rawValue)
    }

    func testAuthenticatedClientReadsAndMutatesRealAppModel() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: true)
        system.start()
        defer { system.stop(reason: .appTermination) }
        let client = makeClient(endpointProvider: system.provider, credentials: credentials)

        guard case let .authenticated(trusted) = try await client.connect() else {
            return XCTFail("Expected authenticated client")
        }
        XCTAssertEqual(trusted.identifier, credentials.presentation.clientIdentifier)

        let statusData = try await client.perform(
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8)
        )
        let status = try JSONDecoder().decode(
            MCPEnvelope<MCPStatusSnapshot>.self,
            from: statusData
        )
        XCTAssertEqual(status.data.mode, .off)

        let mutationData = try await client.perform(
            action: MCPToolName.setBatteryThreshold.rawValue,
            payloadJSON: Data("{\"percent\":22,\"requestId\":\"integration-1\"}".utf8)
        )
        let mutation = try JSONDecoder().decode(
            MCPEnvelope<MCPStatusSnapshot>.self,
            from: mutationData
        )
        XCTAssertEqual(mutation.data.battery.threshold, 22)
        XCTAssertEqual(system.model.batteryThreshold, 22)
    }

    func testUnpairedClientReceivesApprovalWithoutAnyStatusPayload() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: false)
        system.start()
        defer { system.stop(reason: .appTermination) }
        let client = makeClient(endpointProvider: system.provider, credentials: credentials)

        guard case let .approvalRequired(request) = try await client.connect() else {
            return XCTFail("Expected pairing approval")
        }
        XCTAssertEqual(request.presentation.clientIdentifier, credentials.presentation.clientIdentifier)
        await assertClientError(.clientUnpaired) {
            try await client.perform(
                action: MCPToolName.getStatus.rawValue,
                payloadJSON: Data("{}".utf8)
            )
        }
    }

    func testStatusSubscriptionPublishesModelChanges() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: true)
        system.start()
        defer { system.stop(reason: .appTermination) }
        let client = makeClient(endpointProvider: system.provider, credentials: credentials)
        _ = try await client.connect()
        let eventExpectation = expectation(description: "status event")
        let eventValue = LockedValue<MCPEnvelope<MCPStatusSnapshot>?>(nil)

        let subscription = try await client.subscribeStatus { result in
            guard case let .success(data) = result,
                  let envelope = try? JSONDecoder().decode(
                    MCPEnvelope<MCPStatusSnapshot>.self,
                    from: data
                  ),
                  envelope.data.battery.threshold == 24 else { return }
            eventValue.set(envelope)
            eventExpectation.fulfill()
        }
        _ = try await client.perform(
            action: MCPToolName.setBatteryThreshold.rawValue,
            payloadJSON: Data("{\"percent\":24}".utf8)
        )

        await fulfillment(of: [eventExpectation], timeout: 2)
        XCTAssertEqual(eventValue.get()?.data.battery.threshold, 24)
        subscription.cancel()
    }

    func testRequestTimeoutPropagatesCancellationToServer() async throws {
        let endpointProvider = MutableEndpointProvider()
        let credentials = TestClientCredentials()
        let cancellationExpectation = expectation(description: "server received cancellation")
        let hanging = HangingXPCServer(
            endpointProvider: endpointProvider,
            trustedClient: credentials.trustedClient,
            onCancellation: { cancellationExpectation.fulfill() }
        )
        hanging.start()
        defer { hanging.stop() }
        let client = makeClient(
            endpointProvider: endpointProvider,
            credentials: credentials,
            timeout: 0.15
        )
        _ = try await client.connect()

        await assertClientError(.timedOut) {
            try await client.perform(
                action: MCPToolName.getStatus.rawValue,
                payloadJSON: Data("{}".utf8)
            )
        }
        await fulfillment(of: [cancellationExpectation], timeout: 1)
    }

    func testClientReconnectsAfterAppPublishesANewEndpoint() async throws {
        let credentials = TestClientCredentials()
        let endpointProvider = MutableEndpointProvider()
        let first = try makeSystem(
            credentials: credentials,
            pretrusted: true,
            endpointProvider: endpointProvider
        )
        first.start()
        let client = makeClient(endpointProvider: endpointProvider, credentials: credentials)
        _ = try await client.connect()
        _ = try await client.perform(
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8)
        )
        first.stop(reason: .appTermination)

        let second = try makeSystem(
            credentials: credentials,
            pretrusted: true,
            endpointProvider: endpointProvider
        )
        second.start()
        defer { second.stop(reason: .appTermination) }

        _ = try await client.connect()
        let data = try await client.perform(
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8)
        )
        XCTAssertNoThrow(
            try JSONDecoder().decode(MCPEnvelope<MCPStatusSnapshot>.self, from: data)
        )
    }

    func testRevokeAndDisableImmediatelyCloseActiveConnections() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: true)
        system.start()
        let revokeExpectation = expectation(description: "revoked connection closed")
        let client = MCPXPCClient(
            endpointProvider: system.provider,
            credentials: credentials,
            defaultTimeout: 1,
            closeHandler: { reason in
                if reason == .clientRevoked { revokeExpectation.fulfill() }
            }
        )
        _ = try await client.connect()

        system.listener.closeConnections(
            clientIdentifier: credentials.presentation.clientIdentifier,
            reason: .clientRevoked
        )
        await fulfillment(of: [revokeExpectation], timeout: 1)
        await assertClientError(.clientRevoked) {
            try await client.perform(
                action: MCPToolName.getStatus.rawValue,
                payloadJSON: Data("{}".utf8)
            )
        }

        let disableExpectation = expectation(description: "disabled connection closed")
        let secondClient = MCPXPCClient(
            endpointProvider: system.provider,
            credentials: credentials,
            defaultTimeout: 1,
            closeHandler: { reason in
                if reason == .integrationDisabled { disableExpectation.fulfill() }
            }
        )
        _ = try await secondClient.connect()
        system.stop(reason: .integrationDisabled)
        await fulfillment(of: [disableExpectation], timeout: 1)
        await assertProviderUnavailable(system.provider)
        await assertClientError(.mcpDisabled) {
            try await secondClient.perform(
                action: MCPToolName.getStatus.rawValue,
                payloadJSON: Data("{}".utf8)
            )
        }
    }

    func testListenerCanRestartAfterIntegrationIsDisabled() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: true)
        system.start()
        let firstClient = makeClient(
            endpointProvider: system.provider,
            credentials: credentials
        )
        _ = try await firstClient.connect()

        system.stop(reason: .integrationDisabled)
        system.start()
        defer { system.stop(reason: .appTermination) }

        let secondClient = makeClient(
            endpointProvider: system.provider,
            credentials: credentials
        )
        _ = try await secondClient.connect()
        let data = try await secondClient.perform(
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: Data("{}".utf8)
        )
        XCTAssertNoThrow(
            try JSONDecoder().decode(MCPEnvelope<MCPStatusSnapshot>.self, from: data)
        )
    }

    func testAuthenticatedClientReadsStatusAndBoundedActivityResources() async throws {
        let credentials = TestClientCredentials()
        let system = try makeSystem(credentials: credentials, pretrusted: true)
        system.start()
        defer { system.stop(reason: .appTermination) }
        let client = makeClient(endpointProvider: system.provider, credentials: credentials)
        _ = try await client.connect()

        _ = try await client.perform(
            action: MCPToolName.setBatteryThreshold.rawValue,
            payloadJSON: Data("{\"percent\":23}".utf8)
        )
        let statusData = try await client.perform(
            action: "read:maccoffee://status",
            payloadJSON: Data("{}".utf8)
        )
        let status = try JSONDecoder().decode(
            MCPEnvelope<MCPStatusSnapshot>.self,
            from: statusData
        )
        XCTAssertEqual(status.data.battery.threshold, 23)

        let activityData = try await client.perform(
            action: "read:maccoffee://activity",
            payloadJSON: Data("{}".utf8)
        )
        let activity = try JSONDecoder().decode(MCPActivitySnapshot.self, from: activityData)
        XCTAssertEqual(activity.schemaVersion, 1)
        XCTAssertEqual(
            activity.entries.map(\.action),
            [.setBatteryThreshold, .readStatus, .readActivity]
        )
    }

    private func makeClient(
        endpointProvider: MCPXPCAppEndpointProviding,
        credentials: TestClientCredentials,
        timeout: TimeInterval = 1
    ) -> MCPXPCClient {
        MCPXPCClient(
            endpointProvider: endpointProvider,
            credentials: credentials,
            defaultTimeout: timeout
        )
    }

    private func makeSystem(
        credentials: TestClientCredentials,
        pretrusted: Bool,
        endpointProvider: MutableEndpointProvider? = nil
    ) throws -> IntegrationSystem {
        let settings = FakeSettingsStore()
        let model = AppModel(environment: AppEnvironment(
            powerAssertions: FakePowerAssertionManager(),
            battery: FakeBatteryMonitor(state: .acDesktop),
            scheduler: FakeSessionScheduler(),
            settings: settings,
            launchAtLogin: FakeLaunchAtLoginManager(),
            notifications: FakeNotificationSender(),
            lifecycle: FakeLifecycleObserver(),
            localization: LocalizationController(
                settings: settings,
                systemLocale: { Locale(identifier: "en-US") }
            )
        ))
        let trustStore = MCPTrustStore(credentials: FakeMCPCredentialStore())
        if pretrusted {
            try trustStore.trust(credentials.trustedClient)
        }
        let pairing = MCPPairingCoordinator(
            trustStore: trustStore,
            nonceGenerator: IntegrationNonceGenerator(),
            signatureVerifier: MCPP256SignatureVerifier()
        )
        let control = MCPControlService(model: model)
        let endpointProvider = endpointProvider ?? MutableEndpointProvider()
        let listener = MCPXPCListener(
            pairingCoordinator: pairing,
            controlService: control,
            connectionValidator: { _ in true }
        )
        return IntegrationSystem(
            provider: endpointProvider,
            model: model,
            listener: listener
        )
    }

    private func assertClientError<T: Sendable>(
        _ expected: MCPXPCClientError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as MCPXPCClientError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertProviderUnavailable(
        _ provider: MCPXPCAppEndpointProviding
    ) async {
        do {
            _ = try await provider.currentEndpoint()
            XCTFail("Expected endpoint provider to be unavailable")
        } catch {
            // Expected after the app unregisters its anonymous endpoint.
        }
    }
}

@MainActor
private final class IntegrationSystem {
    let provider: MutableEndpointProvider
    let model: AppModel
    let listener: MCPXPCListener

    init(
        provider: MutableEndpointProvider,
        model: AppModel,
        listener: MCPXPCListener
    ) {
        self.provider = provider
        self.model = model
        self.listener = listener
    }

    func start() {
        provider.publish(listener.start())
    }

    func stop(reason: MCPXPCCloseReason) {
        provider.clear()
        listener.stop(reason: reason)
    }
}

private enum TestEndpointProviderError: Error {
    case unavailable
}

private struct UnavailableEndpointProvider: MCPXPCAppEndpointProviding {
    func currentEndpoint() async throws -> NSXPCListenerEndpoint {
        throw TestEndpointProviderError.unavailable
    }
}

private struct StaticEndpointProvider: MCPXPCAppEndpointProviding {
    let endpoint: NSXPCListenerEndpoint

    func currentEndpoint() async throws -> NSXPCListenerEndpoint {
        endpoint
    }
}

private final class MutableEndpointProvider: MCPXPCAppEndpointProviding,
    @unchecked Sendable {
    private let lock = NSLock()
    private var endpoint: NSXPCListenerEndpoint?

    func publish(_ endpoint: NSXPCListenerEndpoint) {
        lock.lock()
        self.endpoint = endpoint
        lock.unlock()
    }

    func clear() {
        lock.lock()
        endpoint = nil
        lock.unlock()
    }

    func currentEndpoint() async throws -> NSXPCListenerEndpoint {
        let current: NSXPCListenerEndpoint? = lock.withLock { self.endpoint }
        guard let current else { throw TestEndpointProviderError.unavailable }
        return current
    }
}

private final class TestClientCredentials: MCPXPCClientCredentialProviding, @unchecked Sendable {
    private let key = P256.Signing.PrivateKey()
    let presentation: MCPAuthenticationPresentation

    init() {
        let identity = MCPCodeIdentity(
            executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
            bundleIdentifier: "com.openai.codex",
            teamIdentifier: "OPENAI",
            signingIdentifier: "com.openai.codex",
            codeDirectoryHash: "integration-hash",
            isSigned: true
        )
        presentation = MCPAuthenticationPresentation(
            clientIdentifier: "integration-client-\(UUID().uuidString.lowercased())",
            displayName: "Integration client",
            publicKey: key.publicKey.x963Representation,
            parentIdentity: identity
        )
    }

    var trustedClient: MCPTrustedClient {
        MCPTrustedClient(
            identifier: presentation.clientIdentifier,
            displayName: presentation.displayName,
            publicKey: presentation.publicKey,
            codeIdentity: presentation.parentIdentity,
            createdAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: Date(timeIntervalSince1970: 1),
            revokedAt: nil
        )
    }

    func authenticationPresentation() throws -> MCPAuthenticationPresentation {
        presentation
    }

    func sign(_ transcript: Data) throws -> Data {
        try key.signature(for: transcript).derRepresentation
    }
}

private final class IntegrationNonceGenerator: MCPNonceGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt8 = 0

    func nextNonce(byteCount: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        counter &+= 1
        return Data(repeating: counter, count: byteCount)
    }
}

private final class RecordingHelperCallback: NSObject, MCPXPCHelperCallback {
    func receive(_ event: MCPXPCEvent) {}
    func closed(_ close: MCPXPCClose, withReply reply: @escaping () -> Void) {
        reply()
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class HangingXPCServer: NSObject, NSXPCListenerDelegate, MCPXPCAppService {
    private let endpointProvider: MutableEndpointProvider
    private let trustedClient: MCPTrustedClient
    private let onCancellation: @Sendable () -> Void
    private let listener = NSXPCListener.anonymous()

    init(
        endpointProvider: MutableEndpointProvider,
        trustedClient: MCPTrustedClient,
        onCancellation: @escaping @Sendable () -> Void
    ) {
        self.endpointProvider = endpointProvider
        self.trustedClient = trustedClient
        self.onCancellation = onCancellation
    }

    func start() {
        listener.delegate = self
        listener.activate()
        endpointProvider.publish(listener.endpoint)
    }

    func stop() {
        endpointProvider.clear()
        listener.invalidate()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = MCPXPCInterfaces.appService()
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = MCPXPCInterfaces.helperCallback()
        newConnection.activate()
        return true
    }

    func beginAuthentication(
        _ hello: MCPXPCAuthenticationHello,
        withReply reply: @escaping (MCPXPCAuthenticationChallenge?, MCPXPCError?) -> Void
    ) {
        reply(
            MCPXPCAuthenticationChallenge(
                schemaVersion: MCPContract.schemaVersion,
                challengeIdentifier: "hanging-challenge",
                nonce: Data(repeating: 7, count: 32),
                transcript: Data("hanging-transcript".utf8)
            ),
            nil
        )
    }

    func completeAuthentication(
        _ proof: MCPXPCAuthenticationProof,
        withReply reply: @escaping (MCPXPCAuthenticationResult?, MCPXPCError?) -> Void
    ) {
        reply(
            MCPXPCAuthenticationResult(
                schemaVersion: MCPContract.schemaVersion,
                state: .authenticated,
                clientJSON: try? JSONEncoder().encode(trustedClient),
                pairingRequestJSON: nil
            ),
            nil
        )
    }

    func perform(
        _ request: MCPXPCRequest,
        withReply reply: @escaping (MCPXPCResponse) -> Void
    ) {}

    func subscribe(
        _ request: MCPXPCSubscription,
        withReply reply: @escaping (MCPXPCResponse) -> Void
    ) {}

    func cancel(_ request: MCPXPCCancellation) {
        onCancellation()
    }

    func close(_ request: MCPXPCClose) {}
}

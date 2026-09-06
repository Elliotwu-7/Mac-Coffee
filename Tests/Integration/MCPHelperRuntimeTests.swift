import CryptoKit
import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPHelperRuntimeTests: XCTestCase {
    func testConcurrentInitialRequestsShareOneAuthenticationAttempt() async throws {
        let credentials = TestRuntimeCredentials()
        let system = try RuntimeIntegrationSystem(credentials: credentials)
        system.start()
        defer { system.stop() }
        let provider = CountingDelayedEndpointProvider(base: system.provider)
        let client = MCPXPCClient(
            endpointProvider: provider,
            credentials: credentials,
            defaultTimeout: 1
        )
        let runtime = MCPHelperRuntime(
            clientFactory: { client },
            availabilityProbe: { true }
        )
        let payload = Data("{}".utf8)

        async let first = runtime.perform(
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: payload
        )
        async let second = runtime.perform(
            action: MCPToolName.getStatus.rawValue,
            payloadJSON: payload
        )
        _ = try await (first, second)

        XCTAssertEqual(provider.requestCount, 1)
    }
}

private final class CountingDelayedEndpointProvider: MCPXPCAppEndpointProviding,
    @unchecked Sendable {
    private let lock = NSLock()
    private let base: RuntimeEndpointProvider
    private var requests = 0

    init(base: RuntimeEndpointProvider) {
        self.base = base
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    func currentEndpoint() async throws -> NSXPCListenerEndpoint {
        lock.withLock { requests += 1 }
        try await Task.sleep(for: .milliseconds(100))
        return try await base.currentEndpoint()
    }
}

private final class RuntimeEndpointProvider: MCPXPCAppEndpointProviding,
    @unchecked Sendable {
    private let lock = NSLock()
    private var endpoint: NSXPCListenerEndpoint?

    func publish(_ endpoint: NSXPCListenerEndpoint) {
        lock.withLock { self.endpoint = endpoint }
    }

    func clear() {
        lock.withLock { endpoint = nil }
    }

    func currentEndpoint() async throws -> NSXPCListenerEndpoint {
        guard let endpoint = lock.withLock({ endpoint }) else {
            throw MCPXPCClientError.appNotRunning
        }
        return endpoint
    }
}

@MainActor
private final class RuntimeIntegrationSystem {
    let provider = RuntimeEndpointProvider()
    private let listener: MCPXPCListener

    init(credentials: TestRuntimeCredentials) throws {
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
        try trustStore.trust(credentials.trustedClient)
        listener = MCPXPCListener(
            pairingCoordinator: MCPPairingCoordinator(
                trustStore: trustStore,
                nonceGenerator: RuntimeNonceGenerator(),
                signatureVerifier: MCPP256SignatureVerifier()
            ),
            controlService: MCPControlService(model: model),
            connectionValidator: { _ in true }
        )
    }

    func start() {
        provider.publish(listener.start())
    }

    func stop() {
        provider.clear()
        listener.stop(reason: .appTermination)
    }
}

private final class RuntimeNonceGenerator: MCPNonceGenerating, @unchecked Sendable {
    func nextNonce(byteCount: Int) throws -> Data {
        Data(repeating: 7, count: byteCount)
    }
}

private final class TestRuntimeCredentials: MCPXPCClientCredentialProviding,
    @unchecked Sendable {
    private let key = P256.Signing.PrivateKey()
    private let presentation: MCPAuthenticationPresentation

    init() {
        presentation = MCPAuthenticationPresentation(
            clientIdentifier: "runtime-client-\(UUID().uuidString.lowercased())",
            displayName: "Runtime client",
            publicKey: key.publicKey.x963Representation,
            parentIdentity: MCPCodeIdentity(
                executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
                bundleIdentifier: "com.openai.codex",
                teamIdentifier: "OPENAI",
                signingIdentifier: "com.openai.codex",
                codeDirectoryHash: "runtime-hash",
                isSigned: true
            )
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

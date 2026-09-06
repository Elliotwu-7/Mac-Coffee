import Combine
import CryptoKit
import Darwin
import Foundation
import MacCoffeeCore

@MainActor
protocol MCPListenerLifecycle: AnyObject {
  func start() -> NSXPCListenerEndpoint
  func stop(reason: MCPXPCCloseReason)
  func closeConnections(clientIdentifier: String, reason: MCPXPCCloseReason)
}

extension MCPXPCListener: MCPListenerLifecycle {}

@MainActor
protocol MCPBrokerRegistration: AnyObject {
  func register(_ endpoint: NSXPCListenerEndpoint) async throws
  func unregister() async
  func setRecoveryHandlers(
    onStarted: @escaping @Sendable () -> Void,
    onCompleted: @escaping @Sendable (Result<Void, MCPBrokerRegistrarError>) -> Void
  )
}

extension MCPBrokerRegistrar: MCPBrokerRegistration {}

@MainActor
final class DirectMCPEnvironment: ObservableObject {
  enum ConnectionState: Equatable, Sendable {
    case disabled
    case starting
    case ready
    case failed
  }

  let model: AppModel
  let settings: MCPSettings
  let trustStore: MCPTrustStore
  let pairingCoordinator: MCPPairingCoordinator
  let controlService: MCPControlService

  @Published private(set) var connectionState: ConnectionState = .disabled

  private let listener: MCPListenerLifecycle
  private let broker: MCPBrokerRegistration
  private var lifecycleTask: Task<Void, Never>?
  private var lifecycleGeneration: UInt64 = 0
  private var isTerminating = false

  init(
    model: AppModel,
    settings: MCPSettings,
    trustStore: MCPTrustStore,
    pairingCoordinator: MCPPairingCoordinator,
    controlService: MCPControlService,
    listener: MCPListenerLifecycle,
    broker: MCPBrokerRegistration
  ) {
    self.model = model
    self.settings = settings
    self.trustStore = trustStore
    self.pairingCoordinator = pairingCoordinator
    self.controlService = controlService
    self.listener = listener
    self.broker = broker
    broker.setRecoveryHandlers(
      onStarted: { [weak self] in
        Task { @MainActor in
          guard let self, self.settings.isEnabled, !self.isTerminating else { return }
          self.connectionState = .starting
        }
      },
      onCompleted: { [weak self] result in
        Task { @MainActor in
          guard let self, self.settings.isEnabled, !self.isTerminating else { return }
          switch result {
          case .success:
            self.connectionState = .ready
          case .failure:
            self.connectionState = .failed
          }
        }
      }
    )
  }

  static func live(
    model: AppModel,
    settingsStore: MCPSettingsStoring
  ) -> DirectMCPEnvironment {
#if DEBUG
    if CommandLine.arguments.contains("--ui-mcp-fixture") {
      return uiTestFixture(model: model, settingsStore: settingsStore)
    }
#endif
    let trustStore = MCPTrustStore(
      credentials: KeychainMCPCredentialStore()
    )
    let pairingCoordinator = MCPPairingCoordinator(
      trustStore: trustStore,
      nonceGenerator: SecurityRandomNonceGenerator(),
      signatureVerifier: MCPP256SignatureVerifier()
    )
    let controlService = MCPControlService(model: model)
    let listener = MCPXPCListener(
      pairingCoordinator: pairingCoordinator,
      controlService: controlService,
      connectionValidator: { connection in
        connection.effectiveUserIdentifier == geteuid()
      }
    )
    return DirectMCPEnvironment(
      model: model,
      settings: MCPSettings(store: settingsStore),
      trustStore: trustStore,
      pairingCoordinator: pairingCoordinator,
      controlService: controlService,
      listener: listener,
      broker: MCPBrokerRegistrar()
    )
  }

#if DEBUG
  private static func uiTestFixture(
    model: AppModel,
    settingsStore: MCPSettingsStoring
  ) -> DirectMCPEnvironment {
    let trustStore = MCPTrustStore(credentials: MCPFixtureCredentialStore())
    let pairingCoordinator = MCPPairingCoordinator(
      trustStore: trustStore,
      nonceGenerator: SecurityRandomNonceGenerator(),
      signatureVerifier: MCPP256SignatureVerifier()
    )
    let activityStore = MCPActivityStore()
    let controlService = MCPControlService(
      model: model,
      activityStore: activityStore
    )
    let listener = MCPXPCListener(
      pairingCoordinator: pairingCoordinator,
      controlService: controlService,
      connectionValidator: { connection in
        connection.effectiveUserIdentifier == geteuid()
      }
    )
    let environment = DirectMCPEnvironment(
      model: model,
      settings: MCPSettings(store: settingsStore),
      trustStore: trustStore,
      pairingCoordinator: pairingCoordinator,
      controlService: controlService,
      listener: listener,
      broker: MCPBrokerRegistrar()
    )
    do {
      try seedUITestFixture(
        trustStore: trustStore,
        pairingCoordinator: pairingCoordinator,
        activityStore: activityStore
      )
    } catch {
      preconditionFailure("Could not seed the MCP UI test fixture")
    }
    return environment
  }

  private static func seedUITestFixture(
    trustStore: MCPTrustStore,
    pairingCoordinator: MCPPairingCoordinator,
    activityStore: MCPActivityStore
  ) throws {
    let identity = MCPCodeIdentity(
      executablePath: "/Applications/Claude.app/Contents/MacOS/Claude",
      bundleIdentifier: "com.anthropic.claudefordesktop",
      teamIdentifier: "TESTTEAM01",
      signingIdentifier: "com.anthropic.claudefordesktop",
      codeDirectoryHash: nil,
      isSigned: true
    )
    let trusted = MCPTrustedClient(
      identifier: "fixture-claude",
      displayName: "Claude Desktop",
      publicKey: Data([4, 1, 2, 3]),
      codeIdentity: identity,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      lastSeenAt: Date(),
      revokedAt: nil
    )
    try trustStore.trust(trusted)

    try seedPendingRequest(
      identifier: "fixture-codex",
      displayName: "Codex",
      identity: MCPCodeIdentity(
        executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
        bundleIdentifier: "com.openai.codex",
        teamIdentifier: "TESTTEAM02",
        signingIdentifier: "com.openai.codex",
        codeDirectoryHash: nil,
        isSigned: true
      ),
      pairingCoordinator: pairingCoordinator
    )
    try seedPendingRequest(
      identifier: "fixture-local",
      displayName: "Local automation",
      identity: MCPCodeIdentity(
        executablePath: "/usr/local/bin/local-automation",
        bundleIdentifier: nil,
        teamIdentifier: nil,
        signingIdentifier: nil,
        codeDirectoryHash: "fixture-hash",
        isSigned: false
      ),
      pairingCoordinator: pairingCoordinator
    )

    let client = MCPClientContext(
      identifier: trusted.identifier,
      displayName: trusted.displayName
    )
    activityStore.record(
      client: client,
      action: .readStatus,
      outcome: .success,
      replayed: false
    )
    activityStore.record(
      client: client,
      action: .setSession,
      outcome: .failure(.batteryBlocked),
      replayed: false
    )
  }

  private static func seedPendingRequest(
    identifier: String,
    displayName: String,
    identity: MCPCodeIdentity,
    pairingCoordinator: MCPPairingCoordinator
  ) throws {
    let privateKey = P256.Signing.PrivateKey()
    let challenge = try pairingCoordinator.beginAuthentication(
      MCPAuthenticationPresentation(
        clientIdentifier: identifier,
        displayName: displayName,
        publicKey: privateKey.publicKey.x963Representation,
        parentIdentity: identity
      ),
      connectionIdentifier: "fixture-connection-\(identifier)"
    )
    let signature = try privateKey.signature(for: challenge.transcript)
    _ = try pairingCoordinator.completeAuthentication(
      MCPAuthenticationProof(
        challengeIdentifier: challenge.identifier,
        signature: signature.derRepresentation
      )
    )
  }
#endif

  func startIfEnabled() {
    guard settings.isEnabled else {
      connectionState = .disabled
      return
    }
    enable()
  }

  func setEnabled(_ enabled: Bool) {
    guard !isTerminating else { return }
    settings.setEnabled(enabled)
    if enabled {
      enable()
    } else {
      disable(reason: .integrationDisabled)
    }
  }

  func prepareForTermination() {
    guard !isTerminating else { return }
    isTerminating = true
    advanceGeneration()
    listener.stop(reason: .appTermination)
    connectionState = .disabled
    enqueue { [weak self] in
      await self?.broker.unregister()
    }
  }

  func closeConnections(
    clientIdentifier: String,
    reason: MCPXPCCloseReason
  ) {
    listener.closeConnections(
      clientIdentifier: clientIdentifier,
      reason: reason
    )
  }

  func waitForIdle() async {
    let generation = lifecycleGeneration
    await lifecycleTask?.value
    if generation != lifecycleGeneration {
      await waitForIdle()
    }
  }

  private func enable() {
    let generation = advanceGeneration()
    let endpoint = listener.start()
    connectionState = .starting
    enqueue { [weak self] in
      guard let self else { return }
      do {
        try await broker.register(endpoint)
        guard
          generation == lifecycleGeneration,
          settings.isEnabled,
          !isTerminating
        else {
          await broker.unregister()
          return
        }
        connectionState = .ready
      } catch {
        guard generation == lifecycleGeneration, !isTerminating else { return }
        listener.stop(reason: .integrationDisabled)
        connectionState = .failed
      }
    }
  }

  private func disable(reason: MCPXPCCloseReason) {
    advanceGeneration()
    listener.stop(reason: reason)
    connectionState = .disabled
    enqueue { [weak self] in
      await self?.broker.unregister()
    }
  }

  @discardableResult
  private func advanceGeneration() -> UInt64 {
    lifecycleGeneration =
      lifecycleGeneration == .max
      ? 1
      : lifecycleGeneration + 1
    return lifecycleGeneration
  }

  private func enqueue(
    _ operation: @escaping @MainActor () async -> Void
  ) {
    let previous = lifecycleTask
    lifecycleTask = Task { @MainActor in
      await previous?.value
      await operation()
    }
  }
}

#if DEBUG
private final class MCPFixtureCredentialStore: MCPCredentialStoring {
  private var values: [String: Data] = [:]

  func data(for key: String) throws -> Data? {
    values[key]
  }

  func setData(_ data: Data, for key: String) throws {
    values[key] = data
  }

  func removeData(for key: String) throws {
    values.removeValue(forKey: key)
  }
}
#endif

import Foundation

actor MCPHelperRuntime {
  typealias ClientFactory = @Sendable () throws -> MCPXPCClient
  typealias AvailabilityProbe = @Sendable () async -> Bool

  private struct ConnectionAttempt {
    let identifier: UUID
    let task: Task<MCPXPCClientAuthorization, Error>
  }

  private let clientFactory: ClientFactory
  private let availabilityProbe: AvailabilityProbe
  private var client: MCPXPCClient?
  private var isConnected = false
  private var connectionAttempt: ConnectionAttempt?
  private var statusSubscription: MCPXPCClientSubscription?

  init(
    clientFactory: @escaping ClientFactory = {
      let credentials = MCPHelperCredentials()
      return MCPXPCClient(
        endpointProvider: MCPBrokerEndpointProvider(),
        credentials: credentials
      )
    },
    availabilityProbe: @escaping AvailabilityProbe = {
      do {
        _ = try await MCPBrokerEndpointProvider().currentEndpoint()
        return true
      } catch {
        return false
      }
    }
  ) {
    self.clientFactory = clientFactory
    self.availabilityProbe = availabilityProbe
  }

  func appAvailable() async -> Bool {
    await availabilityProbe()
  }

  func perform(action: String, payloadJSON: Data) async throws -> Data {
    try Task.checkCancellation()
    let client = try await connectedClient()
    do {
      let response = try await client.perform(
        action: action,
        payloadJSON: payloadJSON
      )
      try Task.checkCancellation()
      return response
    } catch {
      if Self.invalidatesConnection(error) {
        isConnected = false
      }
      throw error
    }
  }

  func subscribeStatus(
    handler: @escaping @Sendable (Data) -> Void
  ) async throws {
    let client = try await connectedClient()
    do {
      let subscription = try await client.subscribeStatus { result in
        if case .success(let data) = result {
          handler(data)
        }
      }
      statusSubscription?.cancel()
      statusSubscription = subscription
    } catch {
      if Self.invalidatesConnection(error) {
        isConnected = false
      }
      throw error
    }
  }

  func unsubscribeStatus() {
    statusSubscription?.cancel()
    statusSubscription = nil
  }

  private func connectedClient() async throws -> MCPXPCClient {
    let client: MCPXPCClient
    if let existing = self.client {
      client = existing
    } else {
      client = try clientFactory()
      self.client = client
    }
    guard !isConnected else { return client }

    let attempt: ConnectionAttempt
    if let connectionAttempt {
      attempt = connectionAttempt
    } else {
      let created = ConnectionAttempt(
        identifier: UUID(),
        task: Task { try await client.connect() }
      )
      connectionAttempt = created
      attempt = created
    }

    let authorization: MCPXPCClientAuthorization
    do {
      authorization = try await attempt.task.value
    } catch {
      clearConnectionAttempt(identifier: attempt.identifier)
      throw error
    }
    clearConnectionAttempt(identifier: attempt.identifier)

    switch authorization {
    case .authenticated:
      isConnected = true
      return client
    case .approvalRequired:
      isConnected = false
      throw MCPXPCClientError.clientUnpaired
    }
  }

  private func clearConnectionAttempt(identifier: UUID) {
    if connectionAttempt?.identifier == identifier {
      connectionAttempt = nil
    }
  }

  private static func invalidatesConnection(_ error: Error) -> Bool {
    switch error {
    case MCPXPCClientError.appNotRunning,
      MCPXPCClientError.clientRevoked,
      MCPXPCClientError.mcpDisabled,
      MCPXPCClientError.protocolViolation:
      true
    default:
      false
    }
  }
}

import Combine
import Foundation
import MacCoffeeCore

@MainActor
final class MCPSettingsViewModel: ObservableObject {
  enum Notice: String, Identifiable {
    case approvalFailed
    case trustStoreUnavailable

    var id: String { rawValue }

    var localizationKey: String {
      switch self {
      case .approvalFailed:
        "mcp.notice.approvalFailed"
      case .trustStoreUnavailable:
        "mcp.notice.trustStoreUnavailable"
      }
    }
  }

  @Published private(set) var trustedClients: [MCPTrustedClient] = []
  @Published var notice: Notice?

  private let environment: DirectMCPEnvironment

  init(environment: DirectMCPEnvironment) {
    self.environment = environment
    refreshTrustedClients()
  }

  func approve(_ request: MCPPairingRequest) {
    do {
      _ = try environment.pairingCoordinator.approve(
        requestIdentifier: request.identifier
      )
      refreshTrustedClients()
    } catch {
      notice = .approvalFailed
    }
  }

  func reject(_ request: MCPPairingRequest) {
    _ = environment.pairingCoordinator.reject(
      requestIdentifier: request.identifier
    )
  }

  func revoke(_ client: MCPTrustedClient) {
    do {
      guard try environment.trustStore.revoke(
        identifier: client.identifier,
        at: Date()
      ) else { return }
      environment.closeConnections(
        clientIdentifier: client.identifier,
        reason: .clientRevoked
      )
      refreshTrustedClients()
    } catch {
      notice = .trustStoreUnavailable
    }
  }

  func forget(_ client: MCPTrustedClient) {
    do {
      guard try environment.trustStore.forget(
        identifier: client.identifier
      ) else { return }
      environment.closeConnections(
        clientIdentifier: client.identifier,
        reason: .clientRevoked
      )
      refreshTrustedClients()
    } catch {
      notice = .trustStoreUnavailable
    }
  }

  func refreshTrustedClients() {
    do {
      trustedClients = try environment.trustStore.clients().sorted(by: Self.sortClients)
    } catch {
      trustedClients = []
      notice = .trustStoreUnavailable
    }
  }

  private static func sortClients(
    _ lhs: MCPTrustedClient,
    _ rhs: MCPTrustedClient
  ) -> Bool {
    if lhs.isRevoked != rhs.isRevoked {
      return !lhs.isRevoked
    }
    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
  }
}

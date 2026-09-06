import Foundation

public final class MCPBrokerConnection: NSObject, MCPBrokerService, @unchecked Sendable {
  private let connectionIdentifier: UUID
  private let role: MCPBrokerPeerRole
  private let registry: MCPBrokerRegistry

  public init(
    connectionIdentifier: UUID,
    role: MCPBrokerPeerRole,
    registry: MCPBrokerRegistry
  ) {
    self.connectionIdentifier = connectionIdentifier
    self.role = role
    self.registry = registry
    super.init()
  }

  public func registerAppEndpoint(
    _ endpoint: NSXPCListenerEndpoint,
    withReply reply: @escaping (MCPBrokerXPCError?) -> Void
  ) {
    do {
      try registry.register(
        endpoint: endpoint,
        connectionIdentifier: connectionIdentifier,
        requesterRole: role
      )
      reply(nil)
    } catch {
      reply(Self.map(error))
    }
  }

  public func unregisterAppEndpoint(
    _ reply: @escaping (MCPBrokerXPCError?) -> Void
  ) {
    do {
      try registry.unregister(
        connectionIdentifier: connectionIdentifier,
        requesterRole: role
      )
      reply(nil)
    } catch {
      reply(Self.map(error))
    }
  }

  public func currentAppEndpoint(
    _ reply: @escaping (NSXPCListenerEndpoint?, MCPBrokerXPCError?) -> Void
  ) {
    do {
      reply(try registry.currentEndpoint(requesterRole: role), nil)
    } catch {
      reply(nil, Self.map(error))
    }
  }

  public func connectionInvalidated() {
    registry.connectionInvalidated(connectionIdentifier)
  }

  private static func map(_ error: Error) -> MCPBrokerXPCError {
    if let error = error as? MCPBrokerRegistryError {
      return MCPBrokerXPCError(code: error.xpcCode)
    }
    return MCPBrokerXPCError(code: .internalError)
  }
}

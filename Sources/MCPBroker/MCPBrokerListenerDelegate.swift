import Foundation

public final class MCPBrokerListenerDelegate: NSObject, NSXPCListenerDelegate,
  @unchecked Sendable
{
  public typealias PeerValidator = @Sendable (NSXPCConnection) -> MCPBrokerPeerRole?

  private let registry: MCPBrokerRegistry
  private let peerValidator: PeerValidator

  public init(
    registry: MCPBrokerRegistry = MCPBrokerRegistry(),
    peerValidator: @escaping PeerValidator
  ) {
    self.registry = registry
    self.peerValidator = peerValidator
    super.init()
  }

  public func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    guard let role = peerValidator(newConnection) else { return false }

    let bridge = MCPBrokerConnection(
      connectionIdentifier: UUID(),
      role: role,
      registry: registry
    )
    newConnection.exportedInterface = MCPBrokerInterfaces.service()
    newConnection.exportedObject = bridge
    newConnection.invalidationHandler = { [weak bridge] in
      bridge?.connectionInvalidated()
    }
    newConnection.interruptionHandler = { [weak bridge] in
      bridge?.connectionInvalidated()
    }
    newConnection.activate()
    return true
  }
}

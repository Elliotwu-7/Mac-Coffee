import Foundation

public final class MCPBrokerEndpointProvider: MCPXPCAppEndpointProviding,
  @unchecked Sendable
{
  public typealias ConnectionFactory = () -> NSXPCConnection

  private let connectionFactory: ConnectionFactory

  public init(
    connectionFactory: @escaping ConnectionFactory = {
      NSXPCConnection(serviceName: MCPBrokerConstants.serviceName)
    }
  ) {
    self.connectionFactory = connectionFactory
  }

  public func currentEndpoint() async throws -> NSXPCListenerEndpoint {
    let connection = connectionFactory()
    connection.remoteObjectInterface = MCPBrokerInterfaces.service()
    connection.activate()
    defer { connection.invalidate() }

    return try await withCheckedThrowingContinuation { continuation in
      let gate = MCPBrokerReplyGate(continuation)
      DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + 5
      ) {
        gate.resolve(.failure(MCPXPCClientError.appNotRunning))
      }
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          gate.resolve(.failure(MCPXPCClientError.appNotRunning))
        }) as? MCPBrokerService
      else {
        gate.resolve(.failure(MCPXPCClientError.appNotRunning))
        return
      }
      proxy.currentAppEndpoint { endpoint, error in
        if let endpoint {
          gate.resolve(.success(endpoint))
        } else if error?.code == .unauthorized {
          gate.resolve(.failure(MCPXPCClientError.protocolViolation))
        } else {
          gate.resolve(.failure(MCPXPCClientError.appNotRunning))
        }
      }
    }
  }
}

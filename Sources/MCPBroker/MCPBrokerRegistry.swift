import Foundation

public enum MCPBrokerPeerRole: Equatable, Sendable {
  case app
  case helper
}

public enum MCPBrokerRegistryError: Error, Equatable, Sendable {
  case appNotRunning
  case unauthorized
  case registrationConflict

  var xpcCode: MCPBrokerErrorCode {
    switch self {
    case .appNotRunning:
      .appNotRunning
    case .unauthorized:
      .unauthorized
    case .registrationConflict:
      .registrationConflict
    }
  }
}

public final class MCPBrokerRegistry: @unchecked Sendable {
  private struct Registration {
    let endpoint: NSXPCListenerEndpoint
    let connectionIdentifier: UUID
  }

  private let lock = NSLock()
  private var registration: Registration?

  public init() {}

  public func register(
    endpoint: NSXPCListenerEndpoint,
    connectionIdentifier: UUID,
    requesterRole: MCPBrokerPeerRole
  ) throws {
    guard requesterRole == .app else {
      throw MCPBrokerRegistryError.unauthorized
    }

    lock.lock()
    defer { lock.unlock() }
    if let registration,
      registration.connectionIdentifier != connectionIdentifier
    {
      throw MCPBrokerRegistryError.registrationConflict
    }
    registration = Registration(
      endpoint: endpoint,
      connectionIdentifier: connectionIdentifier
    )
  }

  public func unregister(
    connectionIdentifier: UUID,
    requesterRole: MCPBrokerPeerRole
  ) throws {
    guard requesterRole == .app else {
      throw MCPBrokerRegistryError.unauthorized
    }

    lock.lock()
    defer { lock.unlock() }
    guard registration?.connectionIdentifier == connectionIdentifier else {
      throw MCPBrokerRegistryError.unauthorized
    }
    registration = nil
  }

  public func currentEndpoint(
    requesterRole: MCPBrokerPeerRole
  ) throws -> NSXPCListenerEndpoint {
    guard requesterRole == .helper else {
      throw MCPBrokerRegistryError.unauthorized
    }

    lock.lock()
    defer { lock.unlock() }
    guard let endpoint = registration?.endpoint else {
      throw MCPBrokerRegistryError.appNotRunning
    }
    return endpoint
  }

  public func connectionInvalidated(_ connectionIdentifier: UUID) {
    lock.lock()
    if registration?.connectionIdentifier == connectionIdentifier {
      registration = nil
    }
    lock.unlock()
  }
}

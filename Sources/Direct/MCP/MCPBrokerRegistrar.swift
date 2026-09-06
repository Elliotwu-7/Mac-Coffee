import Foundation

public enum MCPBrokerRegistrarError: Error, Equatable, Sendable {
  case unavailable
  case unauthorized
  case registrationConflict
  case internalError
}

public final class MCPBrokerRegistrar: @unchecked Sendable {
  public typealias ConnectionFactory = () -> NSXPCConnection

  private struct ActiveConnection {
    let token: UUID
    let connection: NSXPCConnection
  }

  private struct Registration {
    let generation: UUID
    let endpoint: NSXPCListenerEndpoint
    var active: ActiveConnection?
    var isRecovering: Bool
  }

  private struct RecoveryHandlers {
    let onStarted: @Sendable () -> Void
    let onCompleted: @Sendable (Result<Void, MCPBrokerRegistrarError>) -> Void
  }

  private let connectionFactory: ConnectionFactory
  private let recoveryAttemptDidRegister: (NSXPCConnection) -> Void
  private let lock = NSLock()
  private var registration: Registration?
  private var recoveryHandlers: RecoveryHandlers?

  public init(
    connectionFactory: @escaping ConnectionFactory = {
      NSXPCConnection(serviceName: MCPBrokerConstants.serviceName)
    }
  ) {
    self.connectionFactory = connectionFactory
    recoveryAttemptDidRegister = { _ in }
  }

  init(
    connectionFactory: @escaping ConnectionFactory,
    recoveryAttemptDidRegister: @escaping (NSXPCConnection) -> Void
  ) {
    self.connectionFactory = connectionFactory
    self.recoveryAttemptDidRegister = recoveryAttemptDidRegister
  }

  public func register(_ endpoint: NSXPCListenerEndpoint) async throws {
    await unregister()

    let generation = UUID()
    lock.withLock {
      registration = Registration(
        generation: generation,
        endpoint: endpoint,
        active: nil,
        isRecovering: false
      )
    }
    do {
      _ = try await establishConnection(endpoint: endpoint, generation: generation)
    } catch {
      clearRegistration(generation: generation)
      throw error
    }
  }

  public func setRecoveryHandlers(
    onStarted: @escaping @Sendable () -> Void,
    onCompleted: @escaping @Sendable (Result<Void, MCPBrokerRegistrarError>) -> Void
  ) {
    lock.withLock {
      recoveryHandlers = RecoveryHandlers(
        onStarted: onStarted,
        onCompleted: onCompleted
      )
    }
  }

  private func establishConnection(
    endpoint: NSXPCListenerEndpoint,
    generation: UUID
  ) async throws -> ActiveConnection {
    let connection = connectionFactory()
    let token = UUID()
    connection.remoteObjectInterface = MCPBrokerInterfaces.service()
    connection.invalidationHandler = { [weak self] in
      self?.connectionLost(generation: generation, token: token)
    }
    connection.interruptionHandler = { [weak self] in
      self?.connectionLost(generation: generation, token: token)
    }
    let accepted = lock.withLock {
      guard var current = registration, current.generation == generation else { return false }
      current.active = ActiveConnection(token: token, connection: connection)
      registration = current
      return true
    }
    guard accepted else {
      connection.invalidate()
      throw MCPBrokerRegistrarError.unavailable
    }
    connection.activate()
    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let gate = MCPBrokerReplyGate(continuation)
        DispatchQueue.global(qos: .utility).asyncAfter(
          deadline: .now() + 5
        ) {
          gate.resolve(.failure(MCPBrokerRegistrarError.unavailable))
        }
        guard
          let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            gate.resolve(.failure(MCPBrokerRegistrarError.unavailable))
          }) as? MCPBrokerService
        else {
          gate.resolve(.failure(MCPBrokerRegistrarError.unavailable))
          return
        }
        proxy.registerAppEndpoint(endpoint) { error in
          if let error {
            gate.resolve(.failure(Self.map(error.code)))
          } else {
            gate.resolve(.success(()))
          }
        }
      }
    } catch {
      clearActiveConnection(generation: generation, token: token)
      connection.invalidate()
      throw error
    }
    return ActiveConnection(token: token, connection: connection)
  }

  public func unregister() async {
    let registration = lock.withLock {
      let registration = self.registration
      self.registration = nil
      return registration
    }
    guard let connection = registration?.active?.connection else { return }

    _ = try? await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      let gate = MCPBrokerReplyGate(continuation)
      DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + 0.5
      ) {
        gate.resolve(.success(()))
      }
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          gate.resolve(.success(()))
        }) as? MCPBrokerService
      else {
        gate.resolve(.success(()))
        return
      }
      proxy.unregisterAppEndpoint { _ in gate.resolve(.success(())) }
    }
    connection.invalidate()
  }

  private func clearRegistration(generation: UUID) {
    lock.withLock {
      if registration?.generation == generation {
        registration = nil
      }
    }
  }

  private func clearActiveConnection(generation: UUID, token: UUID) {
    lock.withLock {
      guard var current = registration,
        current.generation == generation,
        current.active?.token == token
      else { return }
      current.active = nil
      registration = current
    }
  }

  private func connectionLost(generation: UUID, token: UUID) {
    let endpoint: NSXPCListenerEndpoint? = lock.withLock {
      guard var current = registration,
        current.generation == generation,
        current.active?.token == token
      else { return nil }
      current.active = nil
      guard !current.isRecovering else {
        registration = current
        return nil
      }
      current.isRecovering = true
      registration = current
      return current.endpoint
    }
    guard let endpoint else { return }
    let onStarted = lock.withLock { recoveryHandlers?.onStarted }
    onStarted?()

    Task { [weak self] in
      await self?.recover(endpoint: endpoint, generation: generation)
    }
  }

  private func recover(endpoint: NSXPCListenerEndpoint, generation: UUID) async {
    let retryDelays: [Duration] = [
      .zero,
      .milliseconds(100),
      .milliseconds(250),
      .milliseconds(500),
      .seconds(1),
      .seconds(2),
    ]
    for delay in retryDelays {
      if delay != .zero {
        try? await Task.sleep(for: delay)
      }
      guard isCurrent(generation: generation) else { return }
      do {
        let established = try await establishConnection(
          endpoint: endpoint,
          generation: generation
        )
        recoveryAttemptDidRegister(established.connection)
        if finishRecovery(
          generation: generation,
          activeToken: established.token,
          result: .success(())
        ) {
          return
        }
      } catch {
        continue
      }
    }
    _ = finishRecovery(
      generation: generation,
      activeToken: nil,
      result: .failure(.unavailable)
    )
  }

  private func isCurrent(generation: UUID) -> Bool {
    lock.withLock { registration?.generation == generation }
  }

  private func finishRecovery(
    generation: UUID,
    activeToken: UUID?,
    result: Result<Void, MCPBrokerRegistrarError>
  ) -> Bool {
    let outcome = lock.withLock {
      () -> (Bool, (@Sendable (Result<Void, MCPBrokerRegistrarError>) -> Void)?) in
      guard var current = registration, current.generation == generation else {
        return (false, nil)
      }
      if let activeToken, current.active?.token != activeToken {
        return (false, nil)
      }
      current.isRecovering = false
      registration = current
      return (true, recoveryHandlers?.onCompleted)
    }
    guard outcome.0 else { return false }
    outcome.1?(result)
    return true
  }

  private static func map(_ code: MCPBrokerErrorCode) -> MCPBrokerRegistrarError {
    switch code {
    case .appNotRunning:
      .unavailable
    case .unauthorized:
      .unauthorized
    case .registrationConflict:
      .registrationConflict
    case .internalError:
      .internalError
    }
  }
}

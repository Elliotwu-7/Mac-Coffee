import Foundation
import MacCoffeeCore

public final class MCPXPCListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    public typealias ConnectionValidator = @Sendable (NSXPCConnection) -> Bool
    public typealias ListenerFactory = @Sendable () -> NSXPCListener

    private let listenerFactory: ListenerFactory
    private let pairingCoordinator: MCPPairingCoordinator
    private let controlService: MCPControlService
    private let connectionValidator: ConnectionValidator
    private let stateLock = NSLock()

    private var listener: NSXPCListener?
    private var isActive = false
    private var connections: [UUID: MCPXPCConnection] = [:]

    public init(
        listenerFactory: @escaping ListenerFactory = { .anonymous() },
        pairingCoordinator: MCPPairingCoordinator,
        controlService: MCPControlService,
        connectionValidator: @escaping ConnectionValidator
    ) {
        self.listenerFactory = listenerFactory
        self.pairingCoordinator = pairingCoordinator
        self.controlService = controlService
        self.connectionValidator = connectionValidator
        super.init()
    }

    @discardableResult
    public func start() -> NSXPCListenerEndpoint {
        stateLock.lock()
        if isActive, let listener {
            stateLock.unlock()
            return listener.endpoint
        }

        let listener = listenerFactory()
        listener.delegate = self
        self.listener = listener
        isActive = true
        listener.activate()
        stateLock.unlock()
        return listener.endpoint
    }

    public func stop(reason: MCPXPCCloseReason) {
        let snapshot: [MCPXPCConnection]
        let listener: NSXPCListener?
        stateLock.lock()
        snapshot = Array(connections.values)
        listener = self.listener
        self.listener = nil
        isActive = false
        connections.removeAll()
        stateLock.unlock()

        for connection in snapshot {
            connection.close(reason: reason)
        }
        listener?.invalidate()
    }

    public func closeConnections(
        clientIdentifier: String,
        reason: MCPXPCCloseReason
    ) {
        stateLock.lock()
        let matching = connections.values.filter {
            $0.authenticatedClientIdentifier == clientIdentifier
        }
        stateLock.unlock()
        for connection in matching {
            connection.close(reason: reason)
        }
    }

    public var activeConnectionCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return connections.count
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard connectionValidator(newConnection) else { return false }

        let identifier = UUID()
        let bridge = MCPXPCConnection(
            connection: newConnection,
            pairingCoordinator: pairingCoordinator,
            controlService: controlService,
            onClosed: { [weak self] in
                self?.removeConnection(identifier: identifier)
            }
        )
        newConnection.exportedInterface = MCPXPCInterfaces.appService()
        newConnection.exportedObject = bridge
        newConnection.remoteObjectInterface = MCPXPCInterfaces.helperCallback()
        newConnection.invalidationHandler = { [weak bridge] in
            bridge?.connectionInvalidated()
        }
        newConnection.interruptionHandler = { [weak bridge] in
            bridge?.connectionInterrupted()
        }

        stateLock.lock()
        guard self.listener === listener, isActive else {
            stateLock.unlock()
            return false
        }
        connections[identifier] = bridge
        stateLock.unlock()
        newConnection.activate()
        return true
    }

    private func removeConnection(identifier: UUID) {
        stateLock.lock()
        connections.removeValue(forKey: identifier)
        stateLock.unlock()
    }
}

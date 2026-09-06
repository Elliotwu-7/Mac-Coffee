import Foundation

public enum MCPCachedCommandResult: Equatable, Sendable {
    case success(MCPEnvelope<MCPStatusSnapshot>)
    case failure(MCPServiceError)

    var activityOutcome: MCPActivityOutcome {
        switch self {
        case .success:
            .success
        case let .failure(error):
            .failure(error.code)
        }
    }
}

@MainActor
public final class MCPRequestCache {
    private struct Key: Hashable {
        let clientIdentifier: String
        let requestID: String
    }

    private struct Entry {
        let command: MCPCommand
        let result: MCPCachedCommandResult
    }

    private let capacity: Int
    private var values: [Key: Entry] = [:]
    private var insertionOrder: [Key] = []

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    public func result(
        clientIdentifier: String,
        requestID: String,
        command: MCPCommand
    ) throws -> MCPCachedCommandResult? {
        guard let entry = values[Key(clientIdentifier: clientIdentifier, requestID: requestID)] else {
            return nil
        }
        guard entry.command == command else {
            throw MCPServiceError.invalidArgument(field: "requestId")
        }
        return entry.result
    }

    public func insert(
        _ result: MCPCachedCommandResult,
        command: MCPCommand,
        clientIdentifier: String,
        requestID: String
    ) {
        let key = Key(clientIdentifier: clientIdentifier, requestID: requestID)
        guard values[key] == nil else { return }

        values[key] = Entry(command: command, result: result)
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            let evicted = insertionOrder.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }
}

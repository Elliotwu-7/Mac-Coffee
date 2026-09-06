import Foundation

@MainActor
public protocol MCPControlServicing: AnyObject {
    func execute(
        _ command: MCPCommand,
        client: MCPClientContext
    ) throws -> MCPEnvelope<MCPStatusSnapshot>
}

public extension MCPControlServicing {
    func execute(_ command: MCPCommand) throws -> MCPEnvelope<MCPStatusSnapshot> {
        try execute(command, client: .unattributed)
    }
}

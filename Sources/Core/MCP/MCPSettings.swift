import Combine
import Foundation

@MainActor
public final class MCPSettings: ObservableObject {
    @Published public private(set) var isEnabled: Bool

    private let store: MCPSettingsStoring

    public init(store: MCPSettingsStoring) {
        self.store = store
        isEnabled = store.mcpEnabled
    }

    public func setEnabled(_ enabled: Bool) {
        store.mcpEnabled = enabled
        isEnabled = enabled
    }
}

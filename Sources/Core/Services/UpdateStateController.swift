import Combine
import Foundation

public struct UpdateRelease: Equatable, Identifiable, Sendable {
    public let version: String

    public var id: String { version }

    public init(version: String) {
        self.version = version
    }
}

@MainActor
public final class UpdateStateController: ObservableObject {
    @Published public private(set) var availableRelease: UpdateRelease?
    public private(set) var isPanelVisible = false

    public init() {}

    public func present(version: String) {
        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVersion.isEmpty else { return }
        availableRelease = UpdateRelease(version: normalizedVersion)
    }

    public func dismiss() {
        availableRelease = nil
    }

    public func panelDidAppear() {
        isPanelVisible = true
    }

    public func panelDidDisappear() {
        isPanelVisible = false
    }
}

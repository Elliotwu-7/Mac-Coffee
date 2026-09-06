import Combine
import Foundation

@MainActor
public protocol MCPDebounceScheduling: AnyObject {
    func schedule(_ action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
public final class MCPTaskDebounceScheduler: MCPDebounceScheduling {
    private let delayNanoseconds: UInt64
    private var task: Task<Void, Never>?

    public init(delay: TimeInterval = 0.05) {
        delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
    }

    public func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

public struct MCPStatusSubscriptionToken: Hashable, Sendable {
    fileprivate let id: UUID
}

@MainActor
public final class MCPStatusPublisher {
    public typealias Handler = @MainActor (MCPEnvelope<MCPStatusSnapshot>) -> Void

    private struct Subscriber {
        let client: MCPClientContext
        let handler: Handler
    }

    private let model: AppModel
    private let snapshotFactory: MCPSnapshotFactory
    private let activityStore: MCPActivityStore
    private let debounceScheduler: MCPDebounceScheduling
    private var subscribers: [UUID: Subscriber] = [:]
    private var cancellables: Set<AnyCancellable> = []

    public init(
        model: AppModel,
        snapshotFactory: MCPSnapshotFactory,
        activityStore: MCPActivityStore,
        debounceScheduler: MCPDebounceScheduling
    ) {
        self.model = model
        self.snapshotFactory = snapshotFactory
        self.activityStore = activityStore
        self.debounceScheduler = debounceScheduler

        model.objectWillChange
            .sink { @MainActor [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
        model.environment.localization.objectWillChange
            .sink { @MainActor [weak self] _ in self?.schedulePublish() }
            .store(in: &cancellables)
    }

    public func subscribe(
        client: MCPClientContext,
        handler: @escaping Handler
    ) -> MCPStatusSubscriptionToken {
        let token = MCPStatusSubscriptionToken(id: UUID())
        subscribers[token.id] = Subscriber(client: client, handler: handler)
        activityStore.record(
            client: client,
            action: .subscribeStatus,
            outcome: .success,
            replayed: false
        )
        return token
    }

    public func cancel(_ token: MCPStatusSubscriptionToken) {
        guard let subscriber = subscribers.removeValue(forKey: token.id) else { return }
        activityStore.record(
            client: subscriber.client,
            action: .unsubscribeStatus,
            outcome: .success,
            replayed: false
        )
    }

    private func schedulePublish() {
        debounceScheduler.schedule { [weak self] in
            self?.publishCurrentStatus()
        }
    }

    private func publishCurrentStatus() {
        guard !subscribers.isEmpty else { return }
        let snapshot = snapshotFactory.makeStatus(from: model)
        for subscriber in subscribers.values {
            subscriber.handler(snapshot)
        }
    }
}

import Foundation

@MainActor
public protocol SessionScheduling: AnyObject {
    var hasScheduledAction: Bool { get }
    func schedule(deadline: Date, action: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

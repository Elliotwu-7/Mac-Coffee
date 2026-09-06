import Foundation

@MainActor
public protocol LifecycleObserving: AnyObject {
    var onWake: (() -> Void)? { get set }
    var onClockChange: (() -> Void)? { get set }
    var onActivation: (() -> Void)? { get set }
    var onTermination: (() -> Void)? { get set }
    func start()
    func stop()
}

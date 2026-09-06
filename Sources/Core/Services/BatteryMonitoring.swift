import Foundation

@MainActor
public protocol BatteryMonitoring: AnyObject {
    var currentState: BatteryState { get }
    var onChange: ((BatteryState) -> Void)? { get set }
    func start()
    func stop()
}

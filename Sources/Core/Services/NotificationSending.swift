import Foundation

public enum AppNotificationEvent: Equatable, Sendable {
    case timerCompleted
    case lowBatteryStopped
    case updateAvailable(version: String)
}

@MainActor
public protocol NotificationSending: AnyObject {
    func requestAuthorizationIfNeeded()
    func send(_ event: AppNotificationEvent)
}

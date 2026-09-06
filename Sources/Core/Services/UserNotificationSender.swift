import Foundation
@preconcurrency import UserNotifications

public struct LocalizedNotificationMessage: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

@MainActor
public final class UserNotificationSender: NotificationSending {
    private let center: UNUserNotificationCenter?
    private let settings: SettingsStoring
    private let localization: LocalizationController

    public init(
        center: UNUserNotificationCenter? = nil,
        settings: SettingsStoring,
        localization: LocalizationController
    ) {
        self.center = center
        self.settings = settings
        self.localization = localization
    }

    public func requestAuthorizationIfNeeded() {
        guard !settings.notificationAuthorizationRequested else { return }
        settings.notificationAuthorizationRequested = true
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func send(_ event: AppNotificationEvent) {
        requestAuthorizationIfNeeded()

        let message = localizedMessage(for: event)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.rekurt.maccoffee.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { _ in }
    }

    public func localizedMessage(for event: AppNotificationEvent) -> LocalizedNotificationMessage {
        let bodyKey: String
        switch event {
        case .timerCompleted:
            bodyKey = "notification.timerCompleted"
        case .lowBatteryStopped:
            bodyKey = "notification.lowBatteryStopped"
        case let .updateAvailable(version):
            return LocalizedNotificationMessage(
                title: localization.localized("notification.title"),
                body: localization.format("notification.updateAvailable", arguments: version)
            )
        }
        return LocalizedNotificationMessage(
            title: localization.localized("notification.title"),
            body: localization.localized(bodyKey)
        )
    }

    private var notificationCenter: UNUserNotificationCenter {
        center ?? .current()
    }
}

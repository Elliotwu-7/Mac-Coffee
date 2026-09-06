import Combine
import Foundation

@MainActor
public final class UpdateNoticeCoordinator {
    private let state: UpdateStateController
    private let settings: SettingsStoring
    private let notifications: NotificationSending
    private var releaseObservation: AnyCancellable?

    public init(
        state: UpdateStateController,
        settings: SettingsStoring,
        notifications: NotificationSending
    ) {
        self.state = state
        self.settings = settings
        self.notifications = notifications
        releaseObservation = state.$availableRelease
            .compactMap { $0 }
            .sink { [weak self] release in
                self?.announceIfNeeded(release)
            }
    }

    private func announceIfNeeded(_ release: UpdateRelease) {
        guard settings.lastAnnouncedUpdateVersion != release.version else { return }
        settings.lastAnnouncedUpdateVersion = release.version
        guard !state.isPanelVisible else { return }
        notifications.send(.updateAvailable(version: release.version))
    }
}

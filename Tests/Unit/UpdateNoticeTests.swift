import XCTest
@testable import MacCoffeeCore

@MainActor
final class UpdateNoticeTests: XCTestCase {
    func testUpdateStatePresentsAndDismissesOneReleaseWithoutTouchingOtherAppState() {
        let state = UpdateStateController()

        state.present(version: "2.0.0")

        XCTAssertEqual(state.availableRelease, UpdateRelease(version: "2.0.0"))
        XCTAssertFalse(state.isPanelVisible)

        state.dismiss()

        XCTAssertNil(state.availableRelease)
    }

    func testCoordinatorNotifiesOnlyOnceForEachReleaseWhilePanelIsClosed() {
        let state = UpdateStateController()
        let settings = FakeSettingsStore()
        let notifications = FakeNotificationSender()
        let coordinator = UpdateNoticeCoordinator(
            state: state,
            settings: settings,
            notifications: notifications
        )

        state.present(version: "2.0.0")
        state.present(version: "2.0.0")

        XCTAssertEqual(notifications.events, [.updateAvailable(version: "2.0.0")])
        XCTAssertEqual(settings.lastAnnouncedUpdateVersion, "2.0.0")

        state.dismiss()
        state.present(version: "2.1.0")

        XCTAssertEqual(
            notifications.events,
            [.updateAvailable(version: "2.0.0"), .updateAvailable(version: "2.1.0")]
        )
        XCTAssertEqual(settings.lastAnnouncedUpdateVersion, "2.1.0")
        withExtendedLifetime(coordinator) {}
    }

    func testVisiblePanelCountsAsAnnouncementWithoutSendingSystemNotification() {
        let state = UpdateStateController()
        state.panelDidAppear()
        let settings = FakeSettingsStore()
        let notifications = FakeNotificationSender()
        let coordinator = UpdateNoticeCoordinator(
            state: state,
            settings: settings,
            notifications: notifications
        )

        state.present(version: "3.0.0")

        XCTAssertTrue(notifications.events.isEmpty)
        XCTAssertEqual(settings.lastAnnouncedUpdateVersion, "3.0.0")
        withExtendedLifetime(coordinator) {}
    }

    func testPersistedAnnouncementPreventsDuplicateNotificationAfterRelaunch() {
        let state = UpdateStateController()
        let settings = FakeSettingsStore(lastAnnouncedUpdateVersion: "4.0.0")
        let notifications = FakeNotificationSender()
        let coordinator = UpdateNoticeCoordinator(
            state: state,
            settings: settings,
            notifications: notifications
        )

        state.present(version: "4.0.0")

        XCTAssertTrue(notifications.events.isEmpty)
        withExtendedLifetime(coordinator) {}
    }
}

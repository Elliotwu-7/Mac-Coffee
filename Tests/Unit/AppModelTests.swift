import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class AppModelTests: XCTestCase {
    func testEveryLaunchStartsOff() {
        let harness = Harness(savedDuration: .hours4)

        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertNil(harness.model.session)
        XCTAssertEqual(harness.model.selectedDuration, .hours4)
        XCTAssertTrue(harness.battery.started)
        XCTAssertTrue(harness.lifecycle.started)
    }

    func testModeSwitchPreservesDeadline() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        harness.model.selectDuration(.hours1)
        try harness.model.setMode(.system)
        let deadline = harness.model.session?.expiresAt

        try harness.model.setMode(.display)

        XCTAssertEqual(harness.model.session?.expiresAt, deadline)
        XCTAssertEqual(harness.model.mode, .display)
    }

    func testApplyingIdenticalSessionRestartsItsDeadline() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        try harness.model.applySession(mode: .system, duration: .hours1)

        harness.clock.now = Date(timeIntervalSince1970: 1_500)
        try harness.model.applySession(mode: .system, duration: .hours1)

        XCTAssertEqual(harness.model.session?.startedAt, harness.clock.now)
        XCTAssertEqual(
            harness.model.session?.expiresAt,
            Date(timeIntervalSince1970: 5_100)
        )
        XCTAssertEqual(harness.scheduler.scheduleCount, 2)
    }

    func testTurningOffClearsSessionAndSchedule() throws {
        let harness = Harness()
        try harness.model.setMode(.system)

        try harness.model.setMode(.off)

        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertNil(harness.model.session)
        XCTAssertFalse(harness.scheduler.hasScheduledAction)
    }

    func testIndefiniteSessionHasNoScheduledAction() throws {
        let harness = Harness()
        harness.model.selectDuration(.indefinite)

        try harness.model.setMode(.display)

        XCTAssertNil(harness.model.session?.expiresAt)
        XCTAssertFalse(harness.scheduler.hasScheduledAction)
    }

    func testLowBatteryStopsAndNotifies() throws {
        let harness = Harness()
        try harness.model.setMode(.system)

        harness.battery.emit(.init(powerSource: .battery, percentage: 15, hasInternalBattery: true))

        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertTrue(harness.model.isBatteryBlocked)
        XCTAssertEqual(harness.notifications.events, [.lowBatteryStopped])
    }

    func testBlockedBatteryRejectsActivationAndStatusCanBeDismissed() {
        let harness = Harness(
            batteryState: BatteryState(powerSource: .battery, percentage: 15, hasInternalBattery: true)
        )

        XCTAssertThrowsError(try harness.model.setMode(.system))
        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertEqual(harness.model.statusNotice, .batteryBlocked)
        XCTAssertNotNil(harness.model.statusMessage)

        harness.model.dismissStatus()
        XCTAssertNil(harness.model.statusNotice)
        XCTAssertNil(harness.model.statusMessage)
    }

    func testBatteryThresholdClampsPersistsAndReevaluatesBattery() {
        let harness = Harness(
            batteryState: BatteryState(powerSource: .battery, percentage: 20, hasInternalBattery: true)
        )

        harness.model.setBatteryThreshold(50)

        XCTAssertEqual(harness.model.batteryThreshold, 30)
        XCTAssertEqual(harness.settings.batteryThreshold, 30)
        XCTAssertTrue(harness.model.isBatteryBlocked)

        harness.model.setBatteryThreshold(0)
        XCTAssertEqual(harness.model.batteryThreshold, 10)
        XCTAssertEqual(harness.settings.batteryThreshold, 10)
        XCTAssertFalse(harness.model.isBatteryBlocked)
    }

    func testAssertionFailureKeepsPriorModeAndShowsError() throws {
        let harness = Harness()
        try harness.model.setMode(.system)
        harness.power.failNextTransition = true

        XCTAssertThrowsError(try harness.model.setMode(.display))

        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertNotNil(harness.model.statusMessage)
    }

    func testSameModeRetriesCleanupAfterFailedTransitionChangedConfirmedMode() throws {
        let harness = Harness()
        try harness.model.setMode(.system)
        harness.power.failNextTransition = true
        harness.power.confirmedModeOnFailure = .display

        XCTAssertThrowsError(try harness.model.setMode(.display))
        XCTAssertEqual(harness.model.mode, .display)
        XCTAssertEqual(harness.model.statusNotice, .powerAssertionFailed)
        harness.model.dismissStatus()

        try harness.model.setMode(.display)

        XCTAssertEqual(harness.power.transitions, [.system, .display, .display])
        XCTAssertNil(harness.model.statusNotice)
    }

    func testLaunchAtLoginSuccessFailureAndActivationRefresh() throws {
        let harness = Harness()

        try harness.model.setLaunchAtLogin(true)
        XCTAssertEqual(harness.model.launchAtLoginStatus, .enabled)
        XCTAssertTrue(harness.settings.launchAtLoginRequested)

        harness.launchAtLogin.shouldFail = true
        XCTAssertThrowsError(try harness.model.setLaunchAtLogin(false))
        XCTAssertEqual(harness.model.launchAtLoginStatus, .enabled)
        XCTAssertNotNil(harness.model.statusMessage)

        harness.launchAtLogin.shouldFail = false
        try harness.launchAtLogin.setEnabled(false)
        harness.lifecycle.onActivation?()
        XCTAssertEqual(harness.model.launchAtLoginStatus, .disabled)
    }

    func testTimerCompletionStopsAndNotifies() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        harness.model.selectDuration(.minutes30)
        try harness.model.setMode(.system)

        harness.clock.now = Date(timeIntervalSince1970: 2_800)
        harness.scheduler.fire()

        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertNil(harness.model.session)
        XCTAssertEqual(harness.notifications.events, [.timerCompleted])
        XCTAssertEqual(
            harness.model.statusMessage,
            String(localized: "notification.timerCompleted", bundle: .main)
        )
    }

    func testBackwardClockChangeReschedulesInsteadOfExpiringEarly() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        harness.model.selectDuration(.hours1)
        try harness.model.setMode(.system)
        XCTAssertEqual(harness.scheduler.scheduleCount, 1)

        harness.clock.now = Date(timeIntervalSince1970: 900)
        harness.scheduler.fire()

        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertNotNil(harness.model.session)
        XCTAssertTrue(harness.scheduler.hasScheduledAction)
        XCTAssertEqual(harness.scheduler.scheduleCount, 2)
    }

    func testLifecycleWakeAndClockChangeRevalidateDeadline() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        try harness.model.setMode(.system)
        XCTAssertEqual(harness.scheduler.scheduleCount, 1)

        harness.lifecycle.onWake?()
        harness.lifecycle.onClockChange?()

        XCTAssertEqual(harness.scheduler.scheduleCount, 3)
    }

    func testActivationRefreshesSystemLanguageWithoutReplacingWakeSession() throws {
        let locale = TestLocaleBox(Locale(identifier: "en-US"))
        let harness = Harness(systemLocale: { locale.current })
        harness.model.selectDuration(.hours2)
        try harness.model.setMode(.system)
        let originalSession = harness.model.session

        locale.current = Locale(identifier: "ru-RU")
        harness.lifecycle.onActivation?()

        XCTAssertEqual(harness.localization.locale.language.languageCode?.identifier, "ru")
        XCTAssertEqual(harness.model.session, originalSession)
        XCTAssertEqual(harness.power.transitions, [.system])
    }

    func testTimerReleaseFailureKeepsConfirmedModeAndShowsError() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        harness.model.selectDuration(.minutes30)
        try harness.model.setMode(.system)
        harness.clock.now = Date(timeIntervalSince1970: 2_800)
        harness.power.failNextTransition = true

        harness.scheduler.fire()

        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertEqual(harness.model.session?.mode, .system)
        XCTAssertNotNil(harness.model.statusMessage)
    }

    func testTimerReleaseFailureReconcilesAChangedConfirmedAssertion() throws {
        let harness = Harness(now: Date(timeIntervalSince1970: 1_000))
        harness.model.selectDuration(.minutes30)
        try harness.model.setMode(.display)
        harness.clock.now = Date(timeIntervalSince1970: 2_800)
        harness.power.failNextTransition = true
        harness.power.confirmedModeOnFailure = .system

        harness.scheduler.fire()

        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertEqual(harness.model.session?.mode, .system)
        XCTAssertFalse(harness.scheduler.hasScheduledAction)
    }

    func testPersistentExpiredReleaseFailureDoesNotBusyRetry() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let power = FakePowerAssertionManager()
        let scheduler = TaskSessionScheduler(now: { clock.now })
        let model = AppModel(environment: AppEnvironment(
            powerAssertions: power,
            battery: FakeBatteryMonitor(),
            scheduler: scheduler,
            settings: FakeSettingsStore(savedDuration: .minutes30),
            launchAtLogin: FakeLaunchAtLoginManager(),
            notifications: FakeNotificationSender(),
            lifecycle: FakeLifecycleObserver(),
            now: { clock.now }
        ))
        try model.setMode(.system)
        clock.now = Date(timeIntervalSince1970: 2_800)
        power.failEveryTransition = true

        model.revalidateDeadline()
        let transitionCount = power.transitions.count
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(power.transitions.count, transitionCount)
        XCTAssertEqual(model.mode, .system)
        XCTAssertFalse(scheduler.hasScheduledAction)
    }

    func testTerminationCancelsAndReleasesEverything() throws {
        let harness = Harness()
        try harness.model.setMode(.display)

        harness.lifecycle.onTermination?()

        XCTAssertFalse(harness.scheduler.hasScheduledAction)
        XCTAssertTrue(harness.power.releaseAllCalled)
        XCTAssertFalse(harness.battery.started)
        XCTAssertFalse(harness.lifecycle.started)
    }

    func testTerminationPreparesIntegrationsBeforeReleasingAssertions() {
        let harness = Harness()
        var events: [String] = []
        harness.termination.register { events.append("integration") }
        harness.power.onReleaseAll = { events.append("assertions") }

        harness.model.prepareForTermination()

        XCTAssertEqual(events, ["integration", "assertions"])
    }
}

@MainActor
private final class Harness {
    let clock: TestClock
    let settings: FakeSettingsStore
    let power = FakePowerAssertionManager()
    let battery: FakeBatteryMonitor
    let scheduler = FakeSessionScheduler()
    let launchAtLogin = FakeLaunchAtLoginManager()
    let notifications = FakeNotificationSender()
    let lifecycle = FakeLifecycleObserver()
    let termination = TerminationPreparationCoordinator()
    let localization: LocalizationController
    let model: AppModel

    init(
        now: Date = Date(timeIntervalSince1970: 1_000),
        savedDuration: SessionDuration = .hours1,
        batteryState: BatteryState = .acDesktop,
        systemLocale: @escaping () -> Locale = { Locale(identifier: "en-US") }
    ) {
        clock = TestClock(now: now)
        battery = FakeBatteryMonitor(state: batteryState)
        settings = FakeSettingsStore(savedDuration: savedDuration)
        localization = LocalizationController(settings: settings, systemLocale: systemLocale)
        model = AppModel(environment: AppEnvironment(
            powerAssertions: power,
            battery: battery,
            scheduler: scheduler,
            settings: settings,
            launchAtLogin: launchAtLogin,
            notifications: notifications,
            lifecycle: lifecycle,
            termination: termination,
            localization: localization,
            now: { [clock] in clock.now }
        ))
    }
}

private final class TestLocaleBox {
    var current: Locale

    init(_ current: Locale) {
        self.current = current
    }
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

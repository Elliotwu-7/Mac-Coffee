import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPControlServiceTests: XCTestCase {
    func testGetStatusIsReadOnly() throws {
        let harness = MCPControlHarness()

        let result = try harness.service.execute(.getStatus)

        XCTAssertEqual(result.data.mode, .off)
        XCTAssertTrue(harness.power.transitions.isEmpty)
        XCTAssertEqual(harness.scheduler.scheduleCount, 0)
    }

    func testSetSessionStartsRequestedModeAndDurationExactlyOnce() throws {
        let harness = MCPControlHarness()

        let result = try harness.service.execute(
            .setSession(mode: .system, duration: .hours2, requestID: "session-1")
        )

        XCTAssertEqual(result.requestID, "session-1")
        XCTAssertEqual(result.data.mode, .system)
        XCTAssertEqual(result.data.session?.duration, .hours2)
        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertEqual(harness.model.selectedDuration, .hours2)
        XCTAssertEqual(harness.settings.selectedDuration, .hours2)
        XCTAssertEqual(harness.power.transitions, [.system])
        XCTAssertEqual(harness.scheduler.scheduleCount, 2)
    }

    func testChangingModeWithSameDurationPreservesDeadline() throws {
        let harness = MCPControlHarness()
        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: nil)
        )
        let originalDeadline = harness.model.session?.expiresAt

        let result = try harness.service.execute(
            .setSession(mode: .display, duration: .hours1, requestID: nil)
        )

        XCTAssertEqual(result.data.mode, .display)
        XCTAssertEqual(harness.model.session?.expiresAt, originalDeadline)
        XCTAssertEqual(harness.power.transitions, [.system, .display])
    }

    func testChangingDurationReplacesDeadlineFromCurrentTime() throws {
        let harness = MCPControlHarness(now: Date(timeIntervalSince1970: 1_000))
        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: nil)
        )
        harness.clock.now = Date(timeIntervalSince1970: 2_000)

        let result = try harness.service.execute(
            .setSession(mode: .system, duration: .minutes30, requestID: nil)
        )

        XCTAssertEqual(result.data.session?.startedAt, "1970-01-01T00:33:20.000Z")
        XCTAssertEqual(result.data.session?.expiresAt, "1970-01-01T01:03:20.000Z")
        XCTAssertEqual(harness.power.transitions, [.system])
    }

    func testStopUsesTheSameOffTransitionAsTheAppModel() throws {
        let harness = MCPControlHarness()
        _ = try harness.service.execute(
            .setSession(mode: .display, duration: .indefinite, requestID: nil)
        )

        let result = try harness.service.execute(.stopSession(requestID: "stop-1"))

        XCTAssertEqual(result.requestID, "stop-1")
        XCTAssertEqual(result.data.mode, .off)
        XCTAssertNil(result.data.session)
        XCTAssertEqual(harness.power.transitions, [.display, .off])
        XCTAssertFalse(harness.scheduler.hasScheduledAction)
    }

    func testBlockedBatteryRejectsActivationWithoutChangingDuration() {
        let harness = MCPControlHarness(
            savedDuration: .hours4,
            batteryState: BatteryState(
                powerSource: .battery,
                percentage: 15,
                hasInternalBattery: true
            )
        )

        assertServiceError(.batteryBlocked) {
            _ = try harness.service.execute(
                .setSession(mode: .system, duration: .minutes30, requestID: nil)
            )
        }

        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertEqual(harness.model.selectedDuration, .hours4)
        XCTAssertEqual(harness.settings.selectedDuration, .hours4)
        XCTAssertTrue(harness.power.transitions.isEmpty)
    }

    func testAssertionFailureMapsToStableErrorAndReconciledState() throws {
        let harness = MCPControlHarness()
        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: nil)
        )
        harness.power.failNextTransition = true

        assertServiceError(.assertionFailed) {
            _ = try harness.service.execute(
                .setSession(mode: .display, duration: .hours2, requestID: nil)
            )
        }

        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertEqual(harness.model.selectedDuration, .hours1)
        XCTAssertEqual(harness.model.statusNotice, .powerAssertionFailed)
    }

    func testBatteryThresholdPersistsAndReturnsReevaluatedState() throws {
        let harness = MCPControlHarness(
            batteryState: BatteryState(
                powerSource: .battery,
                percentage: 20,
                hasInternalBattery: true
            )
        )

        let result = try harness.service.execute(
            .setBatteryThreshold(percent: 20, requestID: "battery-1")
        )

        XCTAssertEqual(result.data.battery.threshold, 20)
        XCTAssertTrue(result.data.battery.blocked)
        XCTAssertEqual(harness.settings.batteryThreshold, 20)
    }

    func testLaunchAtLoginUsesAppModelAndReturnsPlatformState() throws {
        let harness = MCPControlHarness()

        let result = try harness.service.execute(
            .setLaunchAtLogin(enabled: true, requestID: nil)
        )

        XCTAssertEqual(result.data.launchAtLogin, .enabled)
        XCTAssertEqual(harness.model.launchAtLoginStatus, .enabled)
        XCTAssertTrue(harness.settings.launchAtLoginRequested)
    }

    func testLanguageChangesImmediatelyWithoutTouchingActiveSession() throws {
        let harness = MCPControlHarness()
        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours2, requestID: nil)
        )
        let originalSession = harness.model.session
        let transitions = harness.power.transitions

        let result = try harness.service.execute(
            .setLanguage(language: .japanese, requestID: "language-1")
        )

        XCTAssertEqual(result.requestID, "language-1")
        XCTAssertEqual(result.data.language.selected, "ja")
        XCTAssertEqual(result.data.language.effective, "ja")
        XCTAssertEqual(harness.model.session, originalSession)
        XCTAssertEqual(harness.power.transitions, transitions)
    }

    func testDirectlyConstructedInvalidCommandsAreRejectedAtServiceBoundary() {
        let harness = MCPControlHarness()

        assertServiceError(.invalidArgument) {
            _ = try harness.service.execute(
                .setSession(mode: .off, duration: .hours1, requestID: nil)
            )
        }
        assertServiceError(.invalidArgument) {
            _ = try harness.service.execute(
                .setBatteryThreshold(percent: 31, requestID: nil)
            )
        }

        XCTAssertEqual(harness.model.mode, .off)
        XCTAssertTrue(harness.power.transitions.isEmpty)
    }

    func testLaunchAtLoginFailureMapsToInternalErrorWithoutLyingAboutState() {
        let harness = MCPControlHarness()
        harness.launchAtLogin.shouldFail = true

        assertServiceError(.internalError) {
            _ = try harness.service.execute(
                .setLaunchAtLogin(enabled: true, requestID: nil)
            )
        }

        XCTAssertEqual(harness.model.launchAtLoginStatus, .disabled)
        XCTAssertFalse(harness.settings.launchAtLoginRequested)
    }

    private func assertServiceError(
        _ expected: MCPErrorCode,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? MCPServiceError)?.code, expected, file: file, line: line)
        }
    }
}

@MainActor
private final class MCPControlHarness {
    let clock: MCPTestClock
    let settings: FakeSettingsStore
    let power = FakePowerAssertionManager()
    let battery: FakeBatteryMonitor
    let scheduler = FakeSessionScheduler()
    let launchAtLogin = FakeLaunchAtLoginManager()
    let localization: LocalizationController
    let model: AppModel
    let service: MCPControlService

    init(
        now: Date = Date(timeIntervalSince1970: 1_000),
        savedDuration: SessionDuration = .hours1,
        batteryState: BatteryState = .acDesktop
    ) {
        clock = MCPTestClock(now: now)
        settings = FakeSettingsStore(savedDuration: savedDuration)
        battery = FakeBatteryMonitor(state: batteryState)
        localization = LocalizationController(
            settings: settings,
            systemLocale: { Locale(identifier: "en-US") }
        )
        model = AppModel(environment: AppEnvironment(
            powerAssertions: power,
            battery: battery,
            scheduler: scheduler,
            settings: settings,
            launchAtLogin: launchAtLogin,
            notifications: FakeNotificationSender(),
            lifecycle: FakeLifecycleObserver(),
            localization: localization,
            now: { [clock] in clock.now }
        ))
        service = MCPControlService(
            model: model,
            now: { [clock] in clock.now }
        )
    }
}

private final class MCPTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

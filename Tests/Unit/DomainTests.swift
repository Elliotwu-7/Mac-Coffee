import Foundation
import XCTest
@testable import MacCoffeeCore

final class DomainTests: XCTestCase {
    func testWakeModesIncludeOffAndBothActiveModes() {
        XCTAssertEqual(WakeMode.allCases, [.off, .system, .display])
    }

    func testDurationPresetsHaveExactIntervals() {
        XCTAssertEqual(SessionDuration.minutes30.interval, 1_800)
        XCTAssertEqual(SessionDuration.hours1.interval, 3_600)
        XCTAssertEqual(SessionDuration.hours2.interval, 7_200)
        XCTAssertEqual(SessionDuration.hours4.interval, 14_400)
        XCTAssertEqual(SessionDuration.hours8.interval, 28_800)
        XCTAssertNil(SessionDuration.indefinite.interval)
    }

    func testFiniteSessionUsesAbsoluteExpiration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = WakeSession(mode: .system, startedAt: start, duration: .minutes30)

        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 2_800))
    }

    func testIndefiniteSessionHasNoExpiration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = WakeSession(mode: .display, startedAt: start, duration: .indefinite)

        XCTAssertNil(session.expiresAt)
    }

    func testDesktopPowerStateIsNeverReportedAsBatteryPowered() {
        XCTAssertEqual(BatteryState.acDesktop.powerSource, .ac)
        XCTAssertFalse(BatteryState.acDesktop.hasInternalBattery)
        XCTAssertNil(BatteryState.acDesktop.percentage)
    }
}

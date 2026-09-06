import IOKit.pwr_mgt
import XCTest
@testable import MacCoffeeCore

final class PowerAssertionManagerTests: XCTestCase {
    func testSystemModeUsesIdleSystemAssertion() throws {
        let driver = FakePowerAssertionDriver()
        let manager = IOKitPowerAssertionManager(driver: driver)

        try manager.transition(to: .system)

        XCTAssertEqual(driver.createdTypes, [kIOPMAssertionTypePreventUserIdleSystemSleep as String])
        XCTAssertEqual(manager.activeMode, .system)
    }

    func testDisplayModeUsesIdleDisplayAssertion() throws {
        let driver = FakePowerAssertionDriver()
        let manager = IOKitPowerAssertionManager(driver: driver)

        try manager.transition(to: .display)

        XCTAssertEqual(driver.createdTypes, [kIOPMAssertionTypePreventUserIdleDisplaySleep as String])
        XCTAssertEqual(manager.activeMode, .display)
    }

    func testReplacementIsCreatedBeforePreviousRelease() throws {
        let driver = FakePowerAssertionDriver()
        let manager = IOKitPowerAssertionManager(driver: driver)
        try manager.transition(to: .system)

        try manager.transition(to: .display)

        XCTAssertEqual(
            driver.events,
            [
                .create(kIOPMAssertionTypePreventUserIdleSystemSleep as String),
                .create(kIOPMAssertionTypePreventUserIdleDisplaySleep as String),
                .release(1)
            ]
        )
    }

    func testCreationFailureKeepsConfirmedMode() throws {
        let driver = FakePowerAssertionDriver(failCreateAtCall: 2)
        let manager = IOKitPowerAssertionManager(driver: driver)
        try manager.transition(to: .system)

        XCTAssertThrowsError(try manager.transition(to: .display))
        XCTAssertEqual(manager.activeMode, .system)
    }

    func testOffReleasesAssertion() throws {
        let driver = FakePowerAssertionDriver()
        let manager = IOKitPowerAssertionManager(driver: driver)
        try manager.transition(to: .system)

        try manager.transition(to: .off)

        XCTAssertEqual(manager.activeMode, .off)
        XCTAssertEqual(driver.events.last, .release(1))
    }

    func testFailedReplacementReleaseIsRetriedByReleaseAll() throws {
        let driver = FakePowerAssertionDriver(failReleaseIDs: [1])
        let manager = IOKitPowerAssertionManager(driver: driver)
        try manager.transition(to: .system)

        XCTAssertThrowsError(try manager.transition(to: .display))
        XCTAssertEqual(manager.activeMode, .display)

        driver.failReleaseIDs = []
        manager.releaseAll()

        XCTAssertEqual(manager.activeMode, .off)
        XCTAssertEqual(driver.events.suffix(2), [.release(1), .release(2)])
    }

    func testOffRetriesEveryStaleAssertionBeforeReportingOff() throws {
        let driver = FakePowerAssertionDriver(failReleaseIDs: [1])
        let manager = IOKitPowerAssertionManager(driver: driver)
        try manager.transition(to: .system)

        XCTAssertThrowsError(try manager.transition(to: .display))
        XCTAssertEqual(manager.activeMode, .display)

        XCTAssertThrowsError(try manager.transition(to: .off))
        XCTAssertEqual(manager.activeMode, .system)

        driver.failReleaseIDs = []
        try manager.transition(to: .off)

        XCTAssertEqual(manager.activeMode, .off)
        XCTAssertEqual(driver.events.suffix(3), [.release(1), .release(2), .release(1)])
    }

    func testNewTransitionRetriesStaleAssertionsBeforeCreatingAnotherOne() throws {
        let driver = FakePowerAssertionDriver(failReleaseIDs: [1])
        let manager = IOKitPowerAssertionManager(driver: driver)
        try manager.transition(to: .system)
        XCTAssertThrowsError(try manager.transition(to: .display))

        let eventCount = driver.events.count
        XCTAssertThrowsError(try manager.transition(to: .system))

        XCTAssertEqual(driver.events.count, eventCount + 1)
        XCTAssertEqual(driver.events.last, .release(1))
        XCTAssertEqual(manager.activeMode, .display)
    }
}

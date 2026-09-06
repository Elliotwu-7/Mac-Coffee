import XCTest
@testable import MacCoffeeCore

final class LowBatteryPolicyTests: XCTestCase {
    func testBatteryAtThresholdBlocks() {
        let state = BatteryState(powerSource: .battery, percentage: 15, hasInternalBattery: true)

        XCTAssertTrue(
            LowBatteryPolicy.nextBlockedState(
                currentlyBlocked: false,
                battery: state,
                threshold: 15
            )
        )
    }

    func testHysteresisRequiresThresholdPlusTwo() {
        let sixteen = BatteryState(powerSource: .battery, percentage: 16, hasInternalBattery: true)
        let seventeen = BatteryState(powerSource: .battery, percentage: 17, hasInternalBattery: true)
        let eighteen = BatteryState(powerSource: .battery, percentage: 18, hasInternalBattery: true)

        XCTAssertTrue(LowBatteryPolicy.nextBlockedState(currentlyBlocked: true, battery: sixteen, threshold: 15))
        XCTAssertTrue(LowBatteryPolicy.nextBlockedState(currentlyBlocked: true, battery: seventeen, threshold: 15))
        XCTAssertFalse(LowBatteryPolicy.nextBlockedState(currentlyBlocked: true, battery: eighteen, threshold: 15))
    }

    func testACDesktopClearsBlock() {
        XCTAssertFalse(LowBatteryPolicy.nextBlockedState(currentlyBlocked: true, battery: .acDesktop, threshold: 15))
    }

    func testTransientUnknownBatteryReadingPreservesCurrentBlock() {
        let unknownPercentage = BatteryState(powerSource: .battery, percentage: nil, hasInternalBattery: true)
        let unknownSource = BatteryState(powerSource: .unknown, percentage: nil, hasInternalBattery: true)

        XCTAssertTrue(LowBatteryPolicy.nextBlockedState(currentlyBlocked: true, battery: unknownPercentage, threshold: 15))
        XCTAssertTrue(LowBatteryPolicy.nextBlockedState(currentlyBlocked: true, battery: unknownSource, threshold: 15))
        XCTAssertFalse(LowBatteryPolicy.nextBlockedState(currentlyBlocked: false, battery: unknownSource, threshold: 15))
    }

    func testThresholdIsClampedToSupportedRange() {
        let nine = BatteryState(powerSource: .battery, percentage: 9, hasInternalBattery: true)
        let thirtyOne = BatteryState(powerSource: .battery, percentage: 31, hasInternalBattery: true)

        XCTAssertTrue(LowBatteryPolicy.nextBlockedState(currentlyBlocked: false, battery: nine, threshold: 0))
        XCTAssertFalse(LowBatteryPolicy.nextBlockedState(currentlyBlocked: false, battery: thirtyOne, threshold: 100))
    }
}

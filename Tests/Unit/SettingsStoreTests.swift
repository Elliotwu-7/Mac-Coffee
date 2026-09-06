import Foundation
import XCTest
@testable import MacCoffeeCore

final class SettingsStoreTests: XCTestCase {
    private var preferences: InMemorySettingsPreferences!

    override func setUp() {
        super.setUp()
        preferences = InMemorySettingsPreferences()
    }

    override func tearDown() {
        preferences = nil
        super.tearDown()
    }

    func testDefaultsMatchProductDecisions() {
        let store = UserDefaultsSettingsStore(preferences: preferences)

        XCTAssertEqual(store.selectedLanguage, .system)
        XCTAssertEqual(store.selectedDuration, .hours1)
        XCTAssertEqual(store.batteryThreshold, 15)
        XCTAssertFalse(store.launchAtLoginRequested)
        XCTAssertFalse(store.notificationAuthorizationRequested)
        XCTAssertNil(store.lastAnnouncedUpdateVersion)
        XCTAssertFalse(store.mcpEnabled)
    }

    func testValuesRoundTripAndThresholdIsClamped() {
        let store = UserDefaultsSettingsStore(preferences: preferences)

        store.selectedLanguage = .german
        store.selectedDuration = .hours4
        store.batteryThreshold = 50
        store.launchAtLoginRequested = true
        store.notificationAuthorizationRequested = true
        store.lastAnnouncedUpdateVersion = "2.0.0"
        store.mcpEnabled = true

        let reloaded = UserDefaultsSettingsStore(preferences: preferences)
        XCTAssertEqual(reloaded.selectedLanguage, .german)
        XCTAssertEqual(reloaded.selectedDuration, .hours4)
        XCTAssertEqual(reloaded.batteryThreshold, 30)
        XCTAssertTrue(reloaded.launchAtLoginRequested)
        XCTAssertTrue(reloaded.notificationAuthorizationRequested)
        XCTAssertEqual(reloaded.lastAnnouncedUpdateVersion, "2.0.0")
        XCTAssertTrue(reloaded.mcpEnabled)
    }

    func testStoreNeverDefinesActiveModeOrSessionKeys() {
        let store = UserDefaultsSettingsStore(preferences: preferences)
        store.selectedDuration = .hours1

        XCTAssertNil(preferences.object(forKey: "mode"))
        XCTAssertNil(preferences.object(forKey: "session"))
        XCTAssertNil(preferences.object(forKey: "activeMode"))
    }
}

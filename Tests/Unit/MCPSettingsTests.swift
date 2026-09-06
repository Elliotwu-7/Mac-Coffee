import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPSettingsTests: XCTestCase {
    func testMCPIsOffByDefaultAndCorruptPreferenceFailsClosed() {
        let preferences = InMemorySettingsPreferences()
        let initial = UserDefaultsSettingsStore(preferences: preferences)
        XCTAssertFalse(initial.mcpEnabled)

        preferences.set("true", forKey: "mcpEnabled")
        let corrupt = UserDefaultsSettingsStore(preferences: preferences)
        XCTAssertFalse(corrupt.mcpEnabled)
    }

    func testEnablementPersistsAndControllerPublishesImmediately() {
        let preferences = InMemorySettingsPreferences()
        let store = UserDefaultsSettingsStore(preferences: preferences)
        let settings = MCPSettings(store: store)

        settings.setEnabled(true)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(UserDefaultsSettingsStore(preferences: preferences).mcpEnabled)
        settings.setEnabled(false)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(UserDefaultsSettingsStore(preferences: preferences).mcpEnabled)
    }

    func testPreferencesNeverContainTrustedClientMaterial() {
        let preferences = InMemorySettingsPreferences()
        let settings = MCPSettings(
            store: UserDefaultsSettingsStore(preferences: preferences)
        )

        settings.setEnabled(true)

        XCTAssertEqual(preferences.object(forKey: "mcpEnabled") as? Bool, true)
        XCTAssertNil(preferences.object(forKey: "trustedClients"))
        XCTAssertNil(preferences.object(forKey: "mcpPublicKey"))
        XCTAssertNil(preferences.object(forKey: "mcpPrivateKey"))
    }
}

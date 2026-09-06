import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPSnapshotTests: XCTestCase {
    func testOffSnapshotUsesVersionedEnvelopeAndExplicitUnknownValues() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let harness = SnapshotHarness(bundle: fixture.bundle)
        let factory = MCPSnapshotFactory(
            localization: harness.localization,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let result = factory.makeStatus(from: harness.model)

        XCTAssertEqual(result.schemaVersion, 1)
        XCTAssertEqual(result.sequence, 1)
        XCTAssertEqual(result.timestamp, "1970-01-01T00:16:40.000Z")
        XCTAssertNil(result.requestID)
        XCTAssertEqual(result.data.mode, .off)
        XCTAssertNil(result.data.session)
        XCTAssertEqual(result.data.selectedDuration, .hours1)
        XCTAssertEqual(
            result.data.battery,
            MCPBatterySnapshot(
                powerSource: .ac,
                percentage: nil,
                hasInternalBattery: false,
                threshold: 15,
                blocked: false
            )
        )
        XCTAssertEqual(result.data.launchAtLogin, .disabled)
        XCTAssertEqual(result.data.language.selected, "system")
        XCTAssertEqual(result.data.language.effective, "en")
        XCTAssertFalse(result.data.busy)
        XCTAssertNil(result.data.notice)
        XCTAssertEqual(result.displayText, "Mac Coffee is off.")
    }

    func testActiveFiniteSessionPreservesDomainDatesAndMode() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let harness = SnapshotHarness(bundle: fixture.bundle)
        harness.model.selectDuration(.hours2)
        try harness.model.setMode(.system)
        let factory = MCPSnapshotFactory(localization: harness.localization)

        let result = factory.makeStatus(from: harness.model, requestID: "status-1")

        XCTAssertEqual(result.requestID, "status-1")
        XCTAssertEqual(result.data.mode, .system)
        XCTAssertEqual(
            result.data.session,
            MCPSessionSnapshot(
                mode: .system,
                duration: .hours2,
                startedAt: "1970-01-01T00:16:40.000Z",
                expiresAt: "1970-01-01T02:16:40.000Z"
            )
        )
        XCTAssertEqual(result.displayText, "Mac Coffee is keeping your Mac awake.")
    }

    func testIndefiniteDisplaySessionHasExplicitNullExpiration() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let harness = SnapshotHarness(bundle: fixture.bundle)
        harness.model.selectDuration(.indefinite)
        try harness.model.setMode(.display)

        let result = MCPSnapshotFactory(localization: harness.localization)
            .makeStatus(from: harness.model)

        XCTAssertNil(result.data.session?.expiresAt)
        XCTAssertEqual(result.displayText, "Mac Coffee is keeping your Mac and display awake.")
    }

    func testLanguageChangeUpdatesDisplayTextWithoutChangingSession() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let harness = SnapshotHarness(bundle: fixture.bundle)
        try harness.model.setMode(.system)
        let session = harness.model.session
        let factory = MCPSnapshotFactory(localization: harness.localization)

        let english = factory.makeStatus(from: harness.model)
        harness.localization.select(.russian)
        let russian = factory.makeStatus(from: harness.model)

        XCTAssertEqual(english.displayText, "Mac Coffee is keeping your Mac awake.")
        XCTAssertEqual(russian.displayText, "Mac Coffee не даёт вашему Mac уснуть.")
        XCTAssertEqual(russian.data.language.selected, "ru")
        XCTAssertEqual(russian.data.language.effective, "ru")
        XCTAssertEqual(harness.model.session, session)
        XCTAssertEqual(russian.sequence, english.sequence + 1)
    }

    func testProjectionRepresentsUnknownLaptopBatteryBusyNoticeAndLaunchStates() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let settings = FakeSettingsStore(selectedLanguage: .english)
        let localization = LocalizationController(
            settings: settings,
            systemLocale: { Locale(identifier: "en-US") },
            bundle: fixture.bundle
        )
        let factory = MCPSnapshotFactory(localization: localization)
        let base = MCPAppState(
            mode: .off,
            session: nil,
            selectedDuration: .minutes30,
            batteryState: BatteryState(
                powerSource: .unknown,
                percentage: nil,
                hasInternalBattery: true
            ),
            batteryThreshold: 22,
            isBatteryBlocked: true,
            launchAtLoginStatus: .requiresApproval,
            statusNotice: .timerCompleted,
            isBusy: true
        )

        let result = factory.makeStatus(from: base)

        XCTAssertEqual(result.data.battery.powerSource, .unknown)
        XCTAssertNil(result.data.battery.percentage)
        XCTAssertTrue(result.data.battery.hasInternalBattery)
        XCTAssertEqual(result.data.battery.threshold, 22)
        XCTAssertTrue(result.data.battery.blocked)
        XCTAssertEqual(result.data.launchAtLogin, .requiresApproval)
        XCTAssertEqual(result.data.notice?.code, .timerCompleted)
        XCTAssertEqual(result.data.notice?.displayText, "The timer finished.")
        XCTAssertTrue(result.data.busy)
    }

    func testEveryLaunchAtLoginStateMapsToAStableWireValue() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let localization = LocalizationController(
            settings: FakeSettingsStore(selectedLanguage: .english),
            systemLocale: { Locale(identifier: "en-US") },
            bundle: fixture.bundle
        )
        let factory = MCPSnapshotFactory(localization: localization)
        let expected: [(LaunchAtLoginStatus, MCPLaunchAtLoginState)] = [
            (.enabled, .enabled),
            (.disabled, .disabled),
            (.requiresApproval, .requiresApproval),
            (.unavailable, .unavailable)
        ]

        for (source, wire) in expected {
            let state = makeOffState(launchAtLoginStatus: source)
            XCTAssertEqual(factory.makeStatus(from: state).data.launchAtLogin, wire)
        }
    }

    func testJSONEncodingKeepsRequiredNullableStatusFields() throws {
        let fixture = try MCPLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let harness = SnapshotHarness(bundle: fixture.bundle)
        let off = MCPSnapshotFactory(localization: harness.localization)
            .makeStatus(from: harness.model)
        let offObject = try jsonObject(off)
        let offData = try XCTUnwrap(offObject["data"] as? [String: Any])
        let battery = try XCTUnwrap(offData["battery"] as? [String: Any])

        XCTAssertTrue(offData["session"] is NSNull)
        XCTAssertTrue(offData["notice"] is NSNull)
        XCTAssertTrue(battery["percentage"] is NSNull)

        harness.model.selectDuration(.indefinite)
        try harness.model.setMode(.system)
        let active = MCPSnapshotFactory(localization: harness.localization)
            .makeStatus(from: harness.model)
        let activeObject = try jsonObject(active)
        let activeData = try XCTUnwrap(activeObject["data"] as? [String: Any])
        let session = try XCTUnwrap(activeData["session"] as? [String: Any])

        XCTAssertTrue(session["expiresAt"] is NSNull)
    }

    private func jsonObject(_ envelope: MCPEnvelope<MCPStatusSnapshot>) throws -> [String: Any] {
        let data = try JSONEncoder().encode(envelope)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeOffState(launchAtLoginStatus: LaunchAtLoginStatus) -> MCPAppState {
        MCPAppState(
            mode: .off,
            session: nil,
            selectedDuration: .hours1,
            batteryState: .acDesktop,
            batteryThreshold: 15,
            isBatteryBlocked: false,
            launchAtLoginStatus: launchAtLoginStatus,
            statusNotice: nil,
            isBusy: false
        )
    }
}

@MainActor
private final class SnapshotHarness {
    let settings = FakeSettingsStore(selectedLanguage: .system)
    let localization: LocalizationController
    let model: AppModel

    init(bundle: Bundle) {
        localization = LocalizationController(
            settings: settings,
            systemLocale: { Locale(identifier: "en-US") },
            bundle: bundle
        )
        model = AppModel(environment: AppEnvironment(
            powerAssertions: FakePowerAssertionManager(),
            battery: FakeBatteryMonitor(),
            scheduler: FakeSessionScheduler(),
            settings: settings,
            launchAtLogin: FakeLaunchAtLoginManager(),
            notifications: FakeNotificationSender(),
            lifecycle: FakeLifecycleObserver(),
            localization: localization,
            now: { Date(timeIntervalSince1970: 1_000) }
        ))
    }
}

private enum MCPLocalizationFixture {
    static func make() throws -> (bundle: Bundle, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCoffeeMCPLocalization.\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.rekurt.maccoffee.mcp-snapshot-tests</string><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array></dict></plist>
        """.write(to: url.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try write([
            "mcp.status.off": "Mac Coffee is off.",
            "mcp.status.system": "Mac Coffee is keeping your Mac awake.",
            "mcp.status.display": "Mac Coffee is keeping your Mac and display awake.",
            "battery.blocked": "Battery protection.",
            "notification.timerCompleted": "The timer finished.",
            "error.powerAssertion": "The wake assertion failed.",
            "error.launchAtLogin": "Launch at Login failed."
        ], language: "en", in: url)
        try write([
            "mcp.status.off": "Mac Coffee выключен.",
            "mcp.status.system": "Mac Coffee не даёт вашему Mac уснуть.",
            "mcp.status.display": "Mac Coffee не даёт Mac и экрану уснуть.",
            "battery.blocked": "Защита батареи.",
            "notification.timerCompleted": "Таймер завершён.",
            "error.powerAssertion": "Ошибка режима бодрствования.",
            "error.launchAtLogin": "Ошибка автозапуска."
        ], language: "ru", in: url)
        return (try XCTUnwrap(Bundle(url: url)), url)
    }

    private static func write(_ strings: [String: String], language: String, in url: URL) throws {
        let directory = url.appendingPathComponent("\(language).lproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = strings
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\" = \"\($0.value)\";" }
            .joined(separator: "\n")
        try contents.write(
            to: directory.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
    }
}

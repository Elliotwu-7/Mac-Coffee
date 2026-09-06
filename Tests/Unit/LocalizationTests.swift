import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private let locales = ["en", "ru", "de", "fr", "zh-Hans", "ja", "ko", "es"]

    func testEverySupportedLocaleHasMatchingNonEmptyKeysAndPlaceholders() throws {
        let english = try strings(in: "en")

        for locale in locales {
            let localized = try strings(in: locale)

            XCTAssertEqual(Set(localized.keys), Set(english.keys), "\(locale) has a different key set")
            for (key, value) in localized {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(locale).\(key) is empty")
                XCTAssertEqual(
                    placeholders(in: value),
                    placeholders(in: try XCTUnwrap(english[key])),
                    "\(locale).\(key) has different placeholders"
                )
            }
        }
    }

    func testEnglishDefinesLanguageAndFailureStringsNeededByTheInterface() throws {
        let english = try strings(in: "en")
        let required = Set([
            "settings.language", "settings.language.system", "settings.language.help",
            "settings.updates", "settings.updates.help", "settings.updates.currentVersion",
            "update.note.title", "update.note.message", "update.action.install", "update.action.later",
            "notification.updateAvailable",
            "about.versionFormat", "error.launchAtLogin", "error.generic",
            "action.quit", "action.cancel", "action.confirmQuit", "quit.message"
        ])

        XCTAssertTrue(Set(english.keys).isSuperset(of: required))
        XCTAssertEqual(placeholders(in: try XCTUnwrap(english["about.versionFormat"])), ["%@", "%@"])
        XCTAssertEqual(placeholders(in: try XCTUnwrap(english["settings.updates.currentVersion"])), ["%@"])
        XCTAssertEqual(placeholders(in: try XCTUnwrap(english["update.note.title"])), ["%@"])
        XCTAssertEqual(placeholders(in: try XCTUnwrap(english["notification.updateAvailable"])), ["%@"])
    }

    func testEnglishContainsNativeLanguageNamesForTheLanguagePicker() throws {
        let english = try strings(in: "en")

        XCTAssertEqual(english["language.russian"], "Русский")
        XCTAssertEqual(english["language.english"], "English")
        XCTAssertEqual(english["language.german"], "Deutsch")
        XCTAssertEqual(english["language.french"], "Français")
        XCTAssertEqual(english["language.simplifiedChinese"], "简体中文")
        XCTAssertEqual(english["language.japanese"], "日本語")
        XCTAssertEqual(english["language.korean"], "한국어")
        XCTAssertEqual(english["language.spanish"], "Español")
    }

    func testEnglishDefinesEveryMCPInterfaceString() throws {
        let english = try strings(in: "en")
        let required = Set([
            "common.ok", "common.cancel", "common.close",
            "mcp.settings.title", "mcp.settings.integration", "mcp.settings.enabled",
            "mcp.settings.status.label", "mcp.settings.securityHelp",
            "mcp.settings.securityLink", "mcp.settings.setup",
            "mcp.status.disabled", "mcp.status.starting", "mcp.status.ready", "mcp.status.failed",
            "mcp.notice.title", "mcp.notice.approvalFailed", "mcp.notice.trustStoreUnavailable",
            "mcp.pairing.request", "mcp.pairing.reason.first", "mcp.pairing.reason.changed",
            "mcp.pairing.identity", "mcp.pairing.unverifiedWarning", "mcp.pairing.reject",
            "mcp.pairing.approve", "mcp.pairing.confirm.title",
            "mcp.pairing.confirm.verified", "mcp.pairing.confirm.changed",
            "mcp.pairing.confirm.unverified", "mcp.verification.verified",
            "mcp.verification.unverified", "mcp.clients.title", "mcp.clients.empty.title",
            "mcp.clients.empty.help", "mcp.client.revoked", "mcp.client.lastSeen",
            "mcp.client.neverSeen", "mcp.client.revoke", "mcp.client.forget",
            "mcp.client.revoke.confirm.title", "mcp.client.revoke.confirm.message",
            "mcp.client.forget.confirm.title", "mcp.client.forget.confirm.message",
            "mcp.activity.title", "mcp.activity.count", "mcp.activity.empty.title",
            "mcp.activity.empty.help", "mcp.activity.replayed", "mcp.activity.outcome.success",
            "mcp.activity.outcome.failure", "mcp.activity.action.getStatus",
            "mcp.activity.action.setSession", "mcp.activity.action.stopSession",
            "mcp.activity.action.setBatteryThreshold", "mcp.activity.action.setLaunchAtLogin",
            "mcp.activity.action.setLanguage", "mcp.activity.action.readStatus",
            "mcp.activity.action.readCapabilities", "mcp.activity.action.readActivity",
            "mcp.activity.action.subscribeStatus", "mcp.activity.action.unsubscribeStatus",
            "mcp.setup.title", "mcp.setup.subtitle", "mcp.setup.client.title",
            "mcp.setup.client.codex", "mcp.setup.client.claude", "mcp.setup.client.generic",
            "mcp.setup.securityHelp", "mcp.setup.configurationPath", "mcp.setup.helperPath",
            "mcp.setup.diff.title", "mcp.setup.diff.help", "mcp.setup.unchanged.title",
            "mcp.setup.unchanged.message", "mcp.setup.manual.generic.title",
            "mcp.setup.manual.generic.message", "mcp.setup.manual.conflict.title",
            "mcp.setup.manual.conflict.message", "mcp.setup.copy", "mcp.setup.installed.title",
            "mcp.setup.installed.message", "mcp.setup.unavailable.title",
            "mcp.setup.unavailable.message", "mcp.setup.restartHelp", "mcp.setup.install",
            "mcp.setup.confirm.title", "mcp.setup.confirm.message", "mcp.setup.confirm.install",
            "mcp.setup.notice.title", "mcp.setup.notice.planningFailed",
            "mcp.setup.notice.installationFailed"
        ])

        XCTAssertTrue(
            Set(english.keys).isSuperset(of: required),
            "Missing MCP localization keys: \(required.subtracting(english.keys).sorted())"
        )
    }

    func testFrenchAndSpanishRemainingTimeUseNumberNeutralWording() throws {
        XCTAssertEqual(try strings(in: "fr")["status.remaining"], "Temps restant : %@")
        XCTAssertEqual(try strings(in: "es")["status.remaining"], "Tiempo restante: %@")
    }

    private func strings(in language: String) throws -> [String: String] {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository
            .appendingPathComponent("Resources/Shared/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }

    private func placeholders(in value: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|d)"#)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).map { match in
            String(value[Range(match.range, in: value)!])
        }
    }
}

import AppKit
import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class QuitConfirmationCoordinatorTests: XCTestCase {
    func testCancelLeavesPreparationAndTerminationUntouched() {
        var events: [String] = []
        let coordinator = makeCoordinator(
            response: .alertSecondButtonReturn,
            prepare: { events.append("prepare") },
            terminate: { events.append("terminate") }
        )

        coordinator.requestQuit()

        XCTAssertEqual(events, [])
    }

    func testConfirmPreparesExactlyOnceBeforeTermination() {
        var events: [String] = []
        var presentationCount = 0
        let coordinator = makeCoordinator(
            response: .alertFirstButtonReturn,
            onPresent: { presentationCount += 1 },
            prepare: { events.append("prepare") },
            terminate: { events.append("terminate") }
        )

        coordinator.requestQuit()
        coordinator.requestQuit()

        XCTAssertEqual(events, ["prepare", "terminate"])
        XCTAssertEqual(presentationCount, 1)
    }

    func testReentrantRequestDoesNotPresentAnotherDialog() {
        let localization = LocalizationController(
            settings: FakeSettingsStore(selectedLanguage: .english)
        )
        let coordinatorReference = QuitCoordinatorReference()
        var presentationCount = 0
        let coordinator = QuitConfirmationCoordinator(
            localization: localization,
            present: { _ in
                presentationCount += 1
                coordinatorReference.value?.requestQuit()
                return .alertSecondButtonReturn
            },
            prepareForTermination: {
                XCTFail("A cancelled reentrant request must not prepare for termination")
            },
            terminate: {
                XCTFail("A cancelled reentrant request must not terminate")
            }
        )
        coordinatorReference.value = coordinator

        coordinator.requestQuit()

        XCTAssertEqual(presentationCount, 1)
    }

    func testEveryRequestUsesTheLanguageActiveAtPresentationTime() throws {
        let fixture = try QuitLocalizationFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let localization = LocalizationController(
            settings: FakeSettingsStore(selectedLanguage: .english),
            bundle: fixture.bundle
        )
        var presentedCopy: [[String]] = []
        let coordinator = QuitConfirmationCoordinator(
            localization: localization,
            present: { alert in
                presentedCopy.append([
                    alert.messageText,
                    alert.informativeText,
                    alert.buttons[0].title,
                    alert.buttons[1].title
                ])
                XCTAssertEqual(alert.window.identifier?.rawValue, "maccoffee.quit.confirmation")
                return .alertSecondButtonReturn
            },
            prepareForTermination: {
                XCTFail("A cancelled request must not prepare for termination")
            },
            terminate: {
                XCTFail("A cancelled request must not terminate")
            }
        )

        coordinator.requestQuit()
        localization.select(.russian)
        coordinator.requestQuit()

        XCTAssertEqual(presentedCopy, [
            ["Quit Mac Coffee", "Quit Mac Coffee and allow your Mac to sleep normally?", "Quit", "Cancel"],
            ["Выйти из Mac Coffee", "Выйти из Mac Coffee и вернуть обычный режим сна Mac?", "Выйти", "Отмена"]
        ])
    }

    private func makeCoordinator(
        response: NSApplication.ModalResponse,
        onPresent: @escaping () -> Void = {},
        prepare: @escaping @MainActor () -> Void,
        terminate: @escaping @MainActor () -> Void
    ) -> QuitConfirmationCoordinator {
        QuitConfirmationCoordinator(
            localization: LocalizationController(
                settings: FakeSettingsStore(selectedLanguage: .english)
            ),
            present: { _ in
                onPresent()
                return response
            },
            prepareForTermination: prepare,
            terminate: terminate
        )
    }

}

@MainActor
private final class QuitCoordinatorReference {
    var value: QuitConfirmationCoordinator?
}

private enum QuitLocalizationFixture {
    static func make() throws -> (bundle: Bundle, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCoffeeQuitLocalization.\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.rekurt.maccoffee.quit-localization-tests</string><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array></dict></plist>
        """.write(to: url.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try writeStrings([
            "action.quit": "Quit Mac Coffee",
            "action.cancel": "Cancel",
            "action.confirmQuit": "Quit",
            "quit.message": "Quit Mac Coffee and allow your Mac to sleep normally?"
        ], language: "en", in: url)
        try writeStrings([
            "action.quit": "Выйти из Mac Coffee",
            "action.cancel": "Отмена",
            "action.confirmQuit": "Выйти",
            "quit.message": "Выйти из Mac Coffee и вернуть обычный режим сна Mac?"
        ], language: "ru", in: url)
        return (try XCTUnwrap(Bundle(url: url)), url)
    }

    private static func writeStrings(
        _ strings: [String: String],
        language: String,
        in bundleURL: URL
    ) throws {
        let directory = bundleURL.appendingPathComponent("\(language).lproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = strings.map { "\"\($0.key)\" = \"\($0.value)\";" }.joined(separator: "\n")
        try contents.write(
            to: directory.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
    }
}

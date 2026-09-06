import AppKit
import XCTest

@MainActor
final class MacCoffeeUITests: XCTestCase {
    private var app: XCUIApplication!

    func testEnglishModeDurationAndSettingsFlow() {
        launch(language: "en", batteryPercentage: 80)

        XCTAssertTrue(testWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(modePicker.exists)
        XCTAssertTrue(durationPicker.exists)

        testWindow.radioButtons["maccoffee.mode.system"].click()
        XCTAssertTrue(app.staticTexts["Mac Coffee is active"].waitForExistence(timeout: 2))

        testWindow.radioButtons["maccoffee.mode.display"].click()
        testWindow.radioButtons["maccoffee.mode.off"].click()
        XCTAssertTrue(app.staticTexts["Mac Coffee is off"].waitForExistence(timeout: 2))
        testWindow.radioButtons["maccoffee.mode.system"].click()

        for duration in ["minutes30", "hours1", "hours4", "hours8", "indefinite", "hours2"] {
            let button = testWindow.radioButtons["maccoffee.duration.\(duration)"]
            button.click()
            XCTAssertEqual(integerValue(of: button), 1)
        }
        let countdown = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@ AND value CONTAINS %@", "maccoffee.status.card", "remaining")
        ).firstMatch
        XCTAssertTrue(countdown.exists)

        testWindow.buttons["maccoffee.action.settings"].click()
        let loginToggle = app.switches["maccoffee.settings.launchAtLogin"]
        XCTAssertTrue(loginToggle.waitForExistence(timeout: 2))
        loginToggle.click()
        XCTAssertEqual(integerValue(of: loginToggle), 1)
        XCTAssertTrue(app.steppers["maccoffee.settings.batteryThreshold"].exists)

        app.windows["Mac Coffee Settings"].buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(app.exists)
    }

    func testFooterQuitCancellationPreservesActiveSessionProcessAndWindow() throws {
        launch(language: "en", batteryPercentage: 80)
        testWindow.radioButtons["maccoffee.mode.system"].click()
        testWindow.radioButtons["maccoffee.duration.hours2"].click()
        let processID = try XCTUnwrap(runningAppProcessID())
        let session = try XCTUnwrap(sessionMarker())
        let windowFrame = testWindow.frame

        testWindow.buttons["maccoffee.action.quit"].click()

        let confirmation = waitForQuitConfirmation()
        XCTAssertTrue(confirmation.staticTexts["Quit Mac Coffee"].exists)
        XCTAssertTrue(confirmation.staticTexts["Quit Mac Coffee and allow your Mac to sleep normally?"].exists)
        confirmation.buttons["Cancel"].click()

        XCTAssertEqual(try XCTUnwrap(runningAppProcessID()), processID)
        XCTAssertEqual(try XCTUnwrap(sessionMarker()), session)
        XCTAssertEqual(integerValue(of: testWindow.radioButtons["maccoffee.mode.system"]), 1)
        XCTAssertEqual(testWindow.frame, windowFrame)
        XCTAssertTrue(testWindow.exists)
    }

    func testCommandQCancellationUsesTheSameDialogAndPreservesActiveSession() throws {
        launch(language: "en", batteryPercentage: 80)
        testWindow.radioButtons["maccoffee.mode.system"].click()
        testWindow.radioButtons["maccoffee.duration.hours2"].click()
        let processID = try XCTUnwrap(runningAppProcessID())
        let session = try XCTUnwrap(sessionMarker())

        testWindow.click()
        app.typeKey("q", modifierFlags: .command)

        let confirmation = waitForQuitConfirmation()
        XCTAssertTrue(confirmation.staticTexts["Quit Mac Coffee"].exists)
        XCTAssertTrue(confirmation.staticTexts["Quit Mac Coffee and allow your Mac to sleep normally?"].exists)
        confirmation.buttons["Cancel"].click()

        XCTAssertEqual(try XCTUnwrap(runningAppProcessID()), processID)
        XCTAssertEqual(try XCTUnwrap(sessionMarker()), session)
        XCTAssertEqual(integerValue(of: testWindow.radioButtons["maccoffee.mode.system"]), 1)
        XCTAssertTrue(testWindow.exists)
    }

    func testLowBatteryBlocksActivationAndShowsBanner() {
        launch(language: "en", batteryPercentage: 15)

        XCTAssertTrue(testWindow.waitForExistence(timeout: 5))
        testWindow.radioButtons["maccoffee.mode.system"].click()

        let banner = app.descendants(matching: .any)["maccoffee.status.banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Wake mode stopped to protect the battery."].exists)
    }

    func testBatteryThresholdIsClampedToSupportedBounds() {
        launch(language: "en", batteryPercentage: 80, batteryThreshold: 5)
        testWindow.buttons["maccoffee.action.settings"].click()
        let minimumStepper = app.steppers["maccoffee.settings.batteryThreshold"]
        XCTAssertTrue(minimumStepper.waitForExistence(timeout: 2))
        XCTAssertEqual(integerValue(of: minimumStepper), 10)

        app.terminate()
        launch(language: "en", batteryPercentage: 80, batteryThreshold: 40)
        testWindow.buttons["maccoffee.action.settings"].click()
        let maximumStepper = app.steppers["maccoffee.settings.batteryThreshold"]
        XCTAssertTrue(maximumStepper.waitForExistence(timeout: 2))
        XCTAssertEqual(integerValue(of: maximumStepper), 30)
    }

    func testDirectSettingsExposeFunctionalMCPMasterSwitch() {
        launch(language: "en", batteryPercentage: 80, mcpFixture: true)
        testWindow.buttons["maccoffee.action.settings"].click()

        let toggle = app.switches["mcp.settings.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(integerValue(of: toggle), 0)

        let settingsScrollView = app.windows["Mac Coffee Settings"].scrollViews.firstMatch
        XCTAssertTrue(settingsScrollView.exists)
        scrollToMakeHittable(toggle, in: settingsScrollView)
        XCTAssertTrue(toggle.isHittable)
        toggle.click()

        XCTAssertEqual(integerValue(of: toggle), 1)
        XCTAssertTrue(
            app.descendants(matching: .any)["mcp.settings.status"].waitForExistence(timeout: 3)
        )
    }

    func testDirectMCPPairingTrustAndActivityControlsAreAccessible() {
        launch(
            language: "en",
            batteryPercentage: 80,
            mcpFixture: true,
            mcpInitiallyEnabled: true
        )
        testWindow.buttons["maccoffee.action.settings"].click()

        let settingsScrollView = app.scrollViews.firstMatch
        XCTAssertTrue(settingsScrollView.waitForExistence(timeout: 3))
        let codexApprove = app.buttons["mcp.pairing.approve.fixture-codex"]
        let localReject = app.buttons["mcp.pairing.reject.fixture-local"]
        scrollToMakeHittable(codexApprove, in: settingsScrollView)
        XCTAssertTrue(codexApprove.isHittable)
        scrollToMakeHittable(localReject, in: settingsScrollView)
        XCTAssertTrue(localReject.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)["mcp.pairing.warning"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["mcp.client.fixture-claude"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.descendants(matching: .any)["mcp.activity"].exists)

        localReject.click()
        XCTAssertFalse(localReject.exists)

        scrollToMakeHittable(codexApprove, in: settingsScrollView)
        codexApprove.click()
        XCTAssertTrue(
            app.buttons["mcp.pairing.confirm.approve.fixture-codex"]
                .waitForExistence(timeout: 2)
        )
        app.buttons["mcp.pairing.confirm.approve.fixture-codex"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["mcp.client.fixture-codex"]
                .waitForExistence(timeout: 2)
        )
    }

    func testDirectMCPSetupWizardShowsReviewedPathsBeforeAnyInstallAction() {
        launch(language: "en", batteryPercentage: 80, mcpFixture: true)
        testWindow.buttons["maccoffee.action.settings"].click()

        let settingsWindow = app.windows["Mac Coffee Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3))
        let settingsScrollView = settingsWindow.scrollViews.firstMatch
        XCTAssertTrue(settingsScrollView.exists)
        let setupButton = app.buttons["mcp.settings.setup"]
        scrollToMakeHittable(setupButton, in: settingsScrollView)
        XCTAssertTrue(setupButton.isHittable)

        setupButton.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["mcp.setup.wizard"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.descendants(matching: .any)["mcp.setup.path"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["mcp.setup.helper"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["mcp.setup.installed"].exists)
    }

    func testAppStoreSettingsDoNotContainMCPIntegration() {
        app = XCUIApplication(bundleIdentifier: "com.rekurt.maccoffee.debug")
        app.launchArguments = [
            "--ui-testing-window",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        openMenuBarPanel()

        testWindow.buttons["maccoffee.action.settings"].click()

        XCTAssertTrue(
            app.switches["maccoffee.settings.launchAtLogin"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.descendants(matching: .any)["mcp.settings.section"].exists)
        XCTAssertFalse(app.switches["mcp.settings.enabled"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["maccoffee.settings.updates"].exists)
        XCTAssertFalse(app.buttons["maccoffee.settings.checkUpdates"].exists)
    }

    func testRussianLocalizationAndAppStoreHasNoUpdateAction() {
        app = XCUIApplication(bundleIdentifier: "com.rekurt.maccoffee.debug")
        app.launchArguments = [
            "--ui-testing-window",
            "-AppleLanguages", "(ru)",
            "-AppleLocale", "ru_RU"
        ]
        app.launch()
        openMenuBarPanel()

        XCTAssertTrue(testWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(testWindow.radioButtons["maccoffee.mode.system"].exists)
        XCTAssertTrue(app.staticTexts["Длительность"].exists)
        XCTAssertFalse(app.buttons["maccoffee.action.update"].exists)
        assertAppStoreFooterToolbar()
    }

    func testNormalWidthDirectFooterUsesCompactActionToolbar() {
        launch(language: "en", batteryPercentage: 80)

        assertFooterContainer(layout: "toolbar")
        XCTAssertFalse(footerList.exists, "A 420 pt Direct footer must not use its narrow list")
        XCTAssertGreaterThanOrEqual(testWindow.frame.width, 400, "The deterministic host must expose its 420 pt width")
        XCTAssertTrue(modePicker.exists, "The mode picker must be present at normal width")

        let identifiers = ["settings", "about", "quit"]
        assertFooterActionTargets(identifiers, labels: [
            "Settings…", "About Mac Coffee", "Quit Mac Coffee"
        ])

        let settings = footerAction("settings")
        let about = footerAction("about")
        let quit = footerAction("quit")
        assertSameFooterRow([settings, about, quit])
        XCTAssertGreaterThan(about.frame.minX, settings.frame.minX)
        XCTAssertGreaterThan(quit.frame.minX, about.frame.minX)
        XCTAssertLessThan(quit.frame.width, settings.frame.width)
        XCTAssertFalse(footerAction("update").exists)
    }

    func testNarrowFooterUsesSingleColumnActionList() {
        launch(language: "en", batteryPercentage: 80, windowWidth: 280)

        assertFooterContainer(layout: "list")
        XCTAssertFalse(footerToolbar.exists, "A 280 pt Direct footer must not keep its horizontal toolbar")
        XCTAssertGreaterThanOrEqual(testWindow.frame.width, 270, "The deterministic host must expose its 280 pt width")

        let identifiers = ["settings", "about", "quit"]
        assertFooterActionTargets(
            identifiers,
            labels: ["Settings…", "About Mac Coffee", "Quit Mac Coffee"]
        )

        let buttons = identifiers.map(footerAction)
        if let first = buttons.first {
            for button in buttons.dropFirst() {
                XCTAssertEqual(button.frame.minX, first.frame.minX, accuracy: 1)
                XCTAssertEqual(button.frame.width, first.frame.width, accuracy: 1)
                XCTAssertEqual(button.frame.height, first.frame.height, accuracy: 1)
            }
        }
        for (upper, lower) in zip(buttons, buttons.dropFirst()) {
            XCTAssertGreaterThan(lower.frame.minY, upper.frame.minY)
        }
    }

    func testNormalWidthDirectFooterKeepsLocalizedLabelsUnwrappedAcrossExplicitLanguages() {
        for expectation in explicitLanguageExpectations {
            launch(
                language: expectation.languageCode,
                batteryPercentage: 80,
                forceUpdateCapability: true
            )

            assertAdaptiveFooterContainer()
            assertFooterActionTargets(
                ["settings", "about", "quit"],
                labels: expectation.footerLabels
            )

            app.terminate()
        }
    }

    func testDirectSettingsOwnsTheManualUpdateCheckInsteadOfTheFooter() {
        launch(language: "en", batteryPercentage: 80, forceUpdateCapability: true)

        XCTAssertFalse(footerAction("update").exists)
        testWindow.buttons["maccoffee.action.settings"].click()

        let section = app.descendants(matching: .any)["maccoffee.settings.updates"].firstMatch
        let checkButton = app.buttons["maccoffee.settings.checkUpdates"]
        XCTAssertTrue(section.waitForExistence(timeout: 3))
        XCTAssertTrue(checkButton.exists)
        XCTAssertTrue(checkButton.isEnabled)
        XCTAssertEqual(checkButton.label, "Check for Updates…")
    }

    func testAvailableUpdateNoteOffersLaterWithoutChangingTheWakeSession() throws {
        launch(language: "en", batteryPercentage: 80, updateVersion: "9.9.9")
        testWindow.radioButtons["maccoffee.mode.system"].click()
        testWindow.radioButtons["maccoffee.duration.hours2"].click()
        let processID = try XCTUnwrap(runningAppProcessID())
        let session = try XCTUnwrap(sessionMarker())

        let note = testWindow.descendants(matching: .any)["maccoffee.update.note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(testWindow.staticTexts["Mac Coffee 9.9.9 is available"].exists)
        XCTAssertTrue(testWindow.buttons["maccoffee.update.install"].exists)

        testWindow.buttons["maccoffee.update.later"].click()

        XCTAssertFalse(note.exists)
        XCTAssertEqual(try XCTUnwrap(runningAppProcessID()), processID)
        XCTAssertEqual(try XCTUnwrap(sessionMarker()), session)
        XCTAssertEqual(integerValue(of: testWindow.radioButtons["maccoffee.mode.system"]), 1)
    }

    func testExplicitLanguageSwitchPreservesActiveWakeSessionAndKeepsPanelControlsVisible() throws {
        launch(language: "en", batteryPercentage: 80)

        testWindow.radioButtons["maccoffee.mode.system"].click()
        testWindow.radioButtons["maccoffee.duration.hours2"].click()
        let processID = try XCTUnwrap(runningAppProcessID(), "Could not find the launched Mac Coffee process")
        let initialSessionMarker = try XCTUnwrap(sessionMarker(), "Active wake session has no deterministic marker")

        testWindow.buttons["maccoffee.action.settings"].click()
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 2))

        for expectation in explicitLanguageExpectations {
            let picker = languagePicker
            picker.click()
            app.menuItems[expectation.nativeName].click()

            XCTAssertEqual(try XCTUnwrap(runningAppProcessID(), "Mac Coffee process disappeared"), processID)
            XCTAssertEqual(try XCTUnwrap(sessionMarker(), "Wake session marker disappeared"), initialSessionMarker)
            XCTAssertEqual(integerValue(of: testWindow.radioButtons["maccoffee.mode.system"]), 1)
            XCTAssertEqual(integerValue(of: testWindow.radioButtons["maccoffee.duration.hours2"]), 1)
            XCTAssertTrue(testWindow.staticTexts[expectation.activeStatus].exists)
            let countdown = testWindow.staticTexts.matching(
                NSPredicate(format: "value MATCHES %@", expectation.countdownPattern)
            ).firstMatch
            XCTAssertTrue(countdown.waitForExistence(timeout: 2))
            assertCountdown(
                textValue(of: countdown),
                matches: expectation.countdownPattern,
                language: expectation.nativeName
            )
            XCTAssertEqual(
                testWindow.radioButtons["maccoffee.mode.system"].label,
                expectation.modeTitle
            )
            XCTAssertTrue(app.staticTexts[expectation.settingsTitle].exists)
            XCTAssertTrue(String(describing: picker.value).contains(expectation.nativeName))

            app.typeKey("w", modifierFlags: .command)
            openMenuBarPanel()
            assertPanelControlsFitInsideTestWindow()

            testWindow.buttons["maccoffee.action.about"].click()
            let version = app.staticTexts.matching(
                NSPredicate(
                    format: "value BEGINSWITH %@ OR label BEGINSWITH %@",
                    expectation.versionPrefix,
                    expectation.versionPrefix
                )
            ).firstMatch
            XCTAssertTrue(version.waitForExistence(timeout: 2))
            XCTAssertTrue(textValue(of: version).contains(expectation.versionPrefix))
            app.typeKey("w", modifierFlags: .command)

            testWindow.buttons["maccoffee.action.settings"].click()
            XCTAssertTrue(languagePicker.waitForExistence(timeout: 2))
        }
    }

    func testNarrowWindowUsesVerticalModeFallbackWithLocalizedSubtitles() throws {
        // 280 pt is deliberately below the segmented control's guarded width;
        // it exercises the same ViewThatFits fallback a small display would use.
        launch(language: "en", batteryPercentage: 80, windowWidth: 280)

        XCTAssertTrue(fallbackTitle.waitForExistence(timeout: 2))
        XCTAssertFalse(testWindow.descendants(matching: .any)["maccoffee.mode.segmented"].exists)

        testWindow.buttons["maccoffee.action.settings"].click()
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 2))

        for expectation in explicitLanguageExpectations {
            let picker = languagePicker
            picker.click()
            app.menuItems[expectation.nativeName].click()
            app.typeKey("w", modifierFlags: .command)

            let currentFallbackTitle = fallbackTitle
            XCTAssertTrue(currentFallbackTitle.waitForExistence(timeout: 2))
            XCTAssertEqual(textValue(of: currentFallbackTitle), expectation.modeSectionTitle)
            XCTAssertFalse(testWindow.descendants(matching: .any)["maccoffee.mode.segmented"].exists)
            XCTAssertGreaterThan(currentFallbackTitle.frame.width, 0)
            XCTAssertGreaterThan(currentFallbackTitle.frame.height, 0)

            for (mode, expectedSubtitle) in zip(["off", "system", "display"], expectation.modeSubtitles) {
                let modeButton = testWindow.radioButtons["maccoffee.mode.\(mode)"]
                XCTAssertTrue(modeButton.exists)
                XCTAssertTrue(modeButton.isHittable)
                XCTAssertGreaterThan(modeButton.frame.width, 0)
                XCTAssertGreaterThan(modeButton.frame.height, 0)
                modeButton.click()
                let subtitle = testWindow.descendants(matching: .any)["maccoffee.mode.fallback.subtitle"].firstMatch
                XCTAssertTrue(subtitle.waitForExistence(timeout: 2))
                XCTAssertEqual(
                    textValue(of: subtitle),
                    expectedSubtitle,
                    "Wrong \(mode) subtitle for \(expectation.nativeName)"
                )
                XCTAssertGreaterThan(subtitle.frame.width, 0)
                XCTAssertGreaterThanOrEqual(
                    subtitle.frame.height,
                    currentFallbackTitle.frame.height * 0.9,
                    "Subtitle layout is too short to render a full caption"
                )
            }

            testWindow.buttons["maccoffee.action.settings"].click()
            XCTAssertTrue(languagePicker.waitForExistence(timeout: 2))
        }
    }

    private func launch(
        language: String,
        batteryPercentage: Int,
        batteryThreshold: Int? = nil,
        windowWidth: Int? = nil,
        forceUpdateCapability: Bool = false,
        updateVersion: String? = nil,
        mcpFixture: Bool = false,
        mcpInitiallyEnabled: Bool = false
    ) {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-window",
            "--ui-battery-percentage=\(batteryPercentage)",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", localeIdentifier(for: language)
        ]
        if let batteryThreshold {
            app.launchArguments.append("--ui-battery-threshold=\(batteryThreshold)")
        }
        if let windowWidth {
            app.launchArguments.append("--ui-testing-window-width=\(windowWidth)")
        }
        if forceUpdateCapability {
            app.launchArguments.append("--ui-testing-force-update-capability")
        }
        if let updateVersion {
            app.launchArguments.append("--ui-testing-update-version=\(updateVersion)")
        }
        if mcpFixture {
            app.launchArguments.append("--ui-mcp-fixture")
        }
        if mcpInitiallyEnabled {
            app.launchArguments.append("--ui-mcp-enabled")
        }
        app.launch()
        openMenuBarPanel()
    }

    private func openMenuBarPanel() {
        XCTAssertTrue(
            testWindow.waitForExistence(timeout: 10),
            "The deterministic UI-test window did not open"
        )
    }

    private func integerValue(of element: XCUIElement) -> Int? {
        if let number = element.value as? NSNumber {
            return number.intValue
        }
        if let string = element.value as? String {
            return Int(string)
        }
        return nil
    }

    private func textValue(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    private func scrollToMakeHittable(
        _ element: XCUIElement,
        in window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<10 where !element.isHittable {
            window.scroll(byDeltaX: 0, deltaY: -220)
        }
        XCTAssertTrue(element.exists, "Element did not enter the Settings viewport", file: file, line: line)
    }

    private func assertPanelControlsFitInsideTestWindow(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let windowFrame = testWindow.frame
        for identifier in [
            "maccoffee.mode.picker",
            "maccoffee.duration.picker",
            "maccoffee.status.card",
            "maccoffee.action.settings",
            "maccoffee.action.about",
            "maccoffee.action.quit"
        ] {
            let element = testWindow.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(element.exists, "Missing \(identifier)", file: file, line: line)
            XCTAssertGreaterThan(element.frame.width, 0, "\(identifier) has no width", file: file, line: line)
            XCTAssertGreaterThan(element.frame.height, 0, "\(identifier) has no height", file: file, line: line)
            XCTAssertTrue(
                windowFrame.contains(element.frame),
                "\(identifier) is outside the test window: \(element.frame)",
                file: file,
                line: line
            )
            XCTAssertTrue(element.isHittable, "\(identifier) is not hittable", file: file, line: line)
        }

        for identifier in ["off", "system", "display"] {
            let element = testWindow.radioButtons["maccoffee.mode.\(identifier)"]
            XCTAssertGreaterThan(element.frame.width, 0, "Mode \(identifier) is clipped", file: file, line: line)
            XCTAssertGreaterThan(element.frame.height, 0, "Mode \(identifier) is clipped", file: file, line: line)
            XCTAssertTrue(windowFrame.contains(element.frame), "Mode \(identifier) is outside the test window", file: file, line: line)
            XCTAssertFalse(element.label.isEmpty, "Mode \(identifier) is missing a label", file: file, line: line)
            XCTAssertTrue(element.isHittable, "Mode \(identifier) is not hittable", file: file, line: line)
        }

        let durationButtons = ["minutes30", "hours1", "hours2", "hours4", "hours8", "indefinite"].map {
            testWindow.radioButtons["maccoffee.duration.\($0)"]
        }
        let widths = durationButtons.map(\.frame.width)
        XCTAssertTrue(widths.allSatisfy { $0 > 0 }, "A duration segment is clipped", file: file, line: line)
        for button in durationButtons {
            XCTAssertTrue(windowFrame.contains(button.frame), "Duration \(button.identifier) is outside the test window", file: file, line: line)
            XCTAssertFalse(button.label.isEmpty, "Duration \(button.identifier) is missing a label", file: file, line: line)
            XCTAssertTrue(button.isHittable, "Duration \(button.identifier) is not hittable", file: file, line: line)
        }
        if let firstWidth = widths.first {
            for width in widths.dropFirst() {
                XCTAssertEqual(width, firstWidth, accuracy: 3, "Duration segments must be equal width", file: file, line: line)
            }
        }
    }

    private func assertAppStoreFooterToolbar(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertFooterContainer(layout: "toolbar", file: file, line: line)
        XCTAssertFalse(footerList.exists, "A 420 pt App Store footer must not use its narrow list", file: file, line: line)
        XCTAssertFalse(footerAction("update").exists, "The App Store footer must never expose an updater", file: file, line: line)
        assertFooterActionTargets(
            ["settings", "about", "quit"],
            labels: ["Настройки…", "О Mac Coffee", "Выйти из Mac Coffee"],
            file: file,
            line: line
        )

        let settings = footerAction("settings")
        let about = footerAction("about")
        let quit = footerAction("quit")
        assertSameFooterRow([settings, about, quit], file: file, line: line)
        XCTAssertGreaterThan(about.frame.minX, settings.frame.minX, file: file, line: line)
        XCTAssertGreaterThan(quit.frame.minX, about.frame.minX, file: file, line: line)
        XCTAssertLessThan(quit.frame.width, settings.frame.width, file: file, line: line)
    }

    private func assertAdaptiveFooterContainer(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(footer.exists, "Missing maccoffee.footer container", file: file, line: line)
        let toolbarExists = footerToolbar.exists
        let listExists = footerList.exists
        XCTAssertNotEqual(toolbarExists, listExists, "Exactly one adaptive footer layout must be active", file: file, line: line)
        let activeLayout = toolbarExists ? "toolbar" : "list"
        assertFooterContainer(layout: activeLayout, file: file, line: line)
    }

    private func assertFooterActionTargets(
        _ identifiers: [String],
        labels: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(identifiers.count, labels.count, "Each footer action needs an exact localized label", file: file, line: line)
        let container = footer
        XCTAssertTrue(container.exists, "Missing maccoffee.footer container", file: file, line: line)
        for (identifier, expectedLabel) in zip(identifiers, labels) {
            let button = footerAction(identifier)
            XCTAssertTrue(button.exists, "Missing \(identifier) action", file: file, line: line)
            XCTAssertGreaterThan(button.frame.width, 0, "\(identifier) has no width", file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 36, "\(identifier) has no full hit target", file: file, line: line)
            XCTAssertTrue(container.frame.contains(button.frame), "\(identifier) is outside the footer", file: file, line: line)
            XCTAssertTrue(testWindow.frame.contains(button.frame), "\(identifier) is outside the test window", file: file, line: line)
            XCTAssertTrue(button.isHittable, "\(identifier) is not hittable", file: file, line: line)
            XCTAssertFalse(button.label.contains("\n"), "\(identifier) label wrapped", file: file, line: line)
            XCTAssertEqual(button.label, expectedLabel, "\(identifier) label is incomplete or not localized", file: file, line: line)
        }
    }

    private func assertFooterContainer(
        layout: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(footer.exists, "Missing maccoffee.footer container", file: file, line: line)
        XCTAssertGreaterThan(footer.frame.width, 0, "Footer container has no width", file: file, line: line)
        XCTAssertGreaterThan(footer.frame.height, 0, "Footer container has no height", file: file, line: line)
        XCTAssertTrue(testWindow.frame.contains(footer.frame), "Footer is outside the test window", file: file, line: line)
        let activeLayout = layout == "toolbar" ? footerToolbar : footerList
        XCTAssertTrue(activeLayout.exists, "Missing maccoffee.footer.\(layout) container", file: file, line: line)
        XCTAssertTrue(footer.frame.contains(activeLayout.frame), "Footer \(layout) is outside maccoffee.footer", file: file, line: line)
        XCTAssertFalse(
            testWindow.staticTexts["maccoffee.footer.\(layout)"].exists,
            "The hidden layout marker must not share the real \(layout) group identifier",
            file: file,
            line: line
        )
        XCTAssertTrue(
            testWindow.staticTexts["maccoffee.footer.\(layout).marker"].exists,
            "Missing distinct hidden \(layout) marker",
            file: file,
            line: line
        )
    }

    private func assertSameFooterRow(
        _ actions: [XCUIElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let first = actions.first else { return }
        for action in actions.dropFirst() {
            XCTAssertEqual(first.frame.minY, action.frame.minY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(first.frame.height, action.frame.height, accuracy: 1, file: file, line: line)
        }
    }

    private func footerAction(_ identifier: String) -> XCUIElement {
        testWindow.descendants(matching: .any)["maccoffee.action.\(identifier)"].firstMatch
    }

    private var footer: XCUIElement {
        testWindow.groups["maccoffee.footer"]
    }

    private var modePicker: XCUIElement {
        testWindow.descendants(matching: .any)["maccoffee.mode.picker"].firstMatch
    }

    private var durationPicker: XCUIElement {
        testWindow.descendants(matching: .any)["maccoffee.duration.picker"].firstMatch
    }

    private var footerToolbar: XCUIElement {
        testWindow.groups["maccoffee.footer.toolbar"]
    }

    private var footerList: XCUIElement {
        testWindow.groups["maccoffee.footer.list"]
    }

    private var languagePicker: XCUIElement {
        app.descendants(matching: .any)["maccoffee.settings.language"].firstMatch
    }

    private var fallbackTitle: XCUIElement {
        testWindow.descendants(matching: .any)["maccoffee.mode.fallback.title"].firstMatch
    }

    private func localeIdentifier(for language: String) -> String {
        switch language {
        case "ru": "ru_RU"
        case "de": "de_DE"
        case "fr": "fr_FR"
        case "zh-Hans": "zh_Hans_CN"
        case "ja": "ja_JP"
        case "ko": "ko_KR"
        case "es": "es_ES"
        default: "en_US"
        }
    }

    private func runningAppProcessID() -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.rekurt.maccoffee.direct.debug")
            .first?
            .processIdentifier
    }

    private var testWindow: XCUIElement {
        app.windows["maccoffee.ui-test.window"]
    }

    private func waitForQuitConfirmation(
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let candidates = [
            app.dialogs["maccoffee.quit.confirmation"],
            app.sheets["maccoffee.quit.confirmation"],
            app.windows["maccoffee.quit.confirmation"]
        ]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let confirmation = candidates.first(where: \.exists) {
                return confirmation
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        XCTFail("The native quit confirmation did not appear", file: file, line: line)
        return candidates[0]
    }

    private func sessionMarker() -> String? {
        let marker = testWindow.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "|")
        ).firstMatch
        guard marker.waitForExistence(timeout: 2) else { return nil }
        return marker.value as? String
    }

    private func assertCountdown(_ value: String, matches pattern: String, language: String) {
        XCTAssertNotNil(
            value.range(of: pattern, options: .regularExpression),
            "Countdown '\(value)' does not use the expected outer status and inner units for \(language)"
        )
    }

    private var explicitLanguageExpectations: [LanguageExpectation] {
        [
            .init("ru", "Русский", "Mac Coffee работает", "^Осталось: \\d+ ч \\d+ мин$", "Язык", "Режим", "Не усыплять Mac", "Версия", ["Обычный режим сна macOS", "Предотвращает сон Mac из-за бездействия", "Предотвращает выключение экрана и сон Mac"], ["Настройки…", "О Mac Coffee", "Выйти из Mac Coffee"]),
            .init("en", "English", "Mac Coffee is active", "^\\d+h \\d+m remaining$", "Language", "Mode", "Keep Mac awake", "Version", ["Normal macOS sleep behavior", "Prevents idle system sleep", "Prevents idle display and system sleep"], ["Settings…", "About Mac Coffee", "Quit Mac Coffee"]),
            .init("de", "Deutsch", "Mac Coffee ist aktiv", "^\\d+ Std\\. \\d+ Min\\. verbleibend$", "Sprache", "Modus", "Mac wach halten", "Version", ["Normales macOS-Ruheverhalten", "Verhindert Ruhezustand bei Inaktivität", "Verhindert Ruhezustand von Display und Mac"], ["Einstellungen…", "Über Mac Coffee", "Mac Coffee beenden"]),
            .init("fr", "Français", "Mac Coffee est actif", "^Temps restant : \\d+ h \\d+ min$", "Langue", "Mode", "Garder le Mac éveillé", "Version", ["Comportement de veille normal de macOS", "Empêche la veille du système en cas d’inactivité", "Empêche la veille de l’écran et du système"], ["Réglages…", "À propos de Mac Coffee", "Quitter Mac Coffee"]),
            .init("zh-Hans", "简体中文", "Mac Coffee 正在运行", "^剩余 \\d+ 小时 \\d+ 分钟$", "语言", "模式", "保持 Mac 唤醒", "版本", ["使用 macOS 正常睡眠行为", "防止 Mac 因闲置而睡眠", "防止显示器和 Mac 因闲置而睡眠"], ["设置…", "关于 Mac Coffee", "退出 Mac Coffee"]),
            .init("ja", "日本語", "Mac Coffee は有効です", "^残り \\d+時間\\d+分$", "言語", "モード", "Mac をスリープさせない", "バージョン", ["通常の macOS のスリープ動作", "操作していないときの Mac のスリープを防ぎます", "ディスプレイと Mac のスリープを防ぎます"], ["設定…", "Mac Coffee について", "Mac Coffee を終了"]),
            .init("ko", "한국어", "Mac Coffee가 활성화되어 있습니다", "^\\d+시간 \\d+분 남음$", "언어", "모드", "Mac 깨우기 유지", "버전", ["일반적인 macOS 잠자기 동작", "유휴 상태에서 Mac이 잠자지 않도록 합니다", "디스플레이와 Mac이 잠자지 않도록 합니다"], ["설정…", "Mac Coffee 정보", "Mac Coffee 종료"]),
            .init("es", "Español", "Mac Coffee está activo", "^Tiempo restante: \\d+ h \\d+ min$", "Idioma", "Modo", "Mantener el Mac activo", "Versión", ["Comportamiento de reposo normal de macOS", "Evita que el Mac entre en reposo por inactividad", "Evita que la pantalla y el Mac entren en reposo"], ["Ajustes…", "Acerca de Mac Coffee", "Salir de Mac Coffee"])
        ]
    }
}

private struct LanguageExpectation {
    let languageCode: String
    let nativeName: String
    let activeStatus: String
    let countdownPattern: String
    let settingsTitle: String
    let modeSectionTitle: String
    let modeTitle: String
    let versionPrefix: String
    let modeSubtitles: [String]
    let footerLabels: [String]

    init(
        _ languageCode: String,
        _ nativeName: String,
        _ activeStatus: String,
        _ countdownPattern: String,
        _ settingsTitle: String,
        _ modeSectionTitle: String,
        _ modeTitle: String,
        _ versionPrefix: String,
        _ modeSubtitles: [String],
        _ footerLabels: [String]
    ) {
        self.languageCode = languageCode
        self.nativeName = nativeName
        self.activeStatus = activeStatus
        self.countdownPattern = countdownPattern
        self.settingsTitle = settingsTitle
        self.modeSectionTitle = modeSectionTitle
        self.modeTitle = modeTitle
        self.versionPrefix = versionPrefix
        self.modeSubtitles = modeSubtitles
        self.footerLabels = footerLabels
    }
}

import Foundation
import ImageIO
import XCTest

final class ReleaseAssetTests: XCTestCase {
    private let localeDirectories = [
        "en-US", "ru", "zh-Hans"
    ]
    private let bundleLocalizations = ["de", "en", "es", "fr", "ja", "ko", "ru", "zh-Hans"]
    private let metadataFiles = [
        "description.txt", "keywords.txt", "marketing_url.txt", "name.txt",
        "privacy_url.txt", "promotional_text.txt", "release_notes.txt",
        "subtitle.txt", "support_url.txt"
    ]

    func testDistributionInfoPlistsDeclareEverySupportedLocalization() throws {
        for relativePath in ["Resources/Direct/Info.plist", "Resources/AppStore/Info.plist"] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let declared = try XCTUnwrap(plist["CFBundleLocalizations"] as? [String])
            XCTAssertEqual(Set(declared), Set(bundleLocalizations), relativePath)
        }
    }

    func testEveryLocaleHasCompleteValidAppStoreMetadata() throws {
        let metadataDirectory = repositoryRoot.appendingPathComponent("metadata")
        let shippedDirectories = try FileManager.default.contentsOfDirectory(
            at: metadataDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .map(\.lastPathComponent)
        .sorted()
        XCTAssertEqual(shippedDirectories, localeDirectories)

        for locale in localeDirectories {
            let directory = repositoryRoot.appendingPathComponent("metadata/\(locale)")
            for filename in metadataFiles {
                let value = try text(at: directory.appendingPathComponent(filename))
                XCTAssertFalse(value.isEmpty, "\(locale)/\(filename) must not be empty")
            }

            XCTAssertLessThanOrEqual(try text(at: directory.appendingPathComponent("name.txt")).count, 30)
            XCTAssertLessThanOrEqual(try text(at: directory.appendingPathComponent("subtitle.txt")).count, 30)
            XCTAssertLessThanOrEqual(try text(at: directory.appendingPathComponent("description.txt")).count, 4_000)
            XCTAssertLessThanOrEqual(try text(at: directory.appendingPathComponent("promotional_text.txt")).count, 170)
            XCTAssertLessThanOrEqual(
                try text(at: directory.appendingPathComponent("keywords.txt")).lengthOfBytes(using: .utf8),
                100
            )

            for filename in ["marketing_url.txt", "privacy_url.txt", "support_url.txt"] {
                let value = try text(at: directory.appendingPathComponent(filename))
                XCTAssertEqual(URL(string: value)?.scheme, "https", "\(locale)/\(filename)")
            }
        }
    }

    func testEveryLocaleHasOpaqueAppStoreScreenshots() throws {
        for locale in localeDirectories {
            for filename in ["01-menu-bar.png", "02-settings.png"] {
                let url = repositoryRoot
                    .appendingPathComponent("metadata/\(locale)/screenshots")
                    .appendingPathComponent(filename)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), url.path)
                let properties = try XCTUnwrap(
                    CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                )
                XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1_280, url.path)
                XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 800, url.path)
                XCTAssertNotEqual(properties[kCGImagePropertyHasAlpha] as? Bool, true, url.path)
            }
        }
    }

    func testLocalizedReadmesExistAndPrimaryReadmeEndsWithUpstreamAttribution() throws {
        let readmes = try FileManager.default.contentsOfDirectory(
            at: repositoryRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .map(\.lastPathComponent)
        .filter { $0 == "README.md" || ($0.hasPrefix("README.") && $0.hasSuffix(".md")) }
        .sorted()
        XCTAssertEqual(readmes, ["README.md", "README.ru.md", "README.zh-Hans.md"])

        for filename in readmes {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(filename).path),
                filename
            )
        }

        let readme = try text(at: repositoryRoot.appendingPathComponent("README.md"))
        XCTAssertEqual(
            readme.split(separator: "\n").last.map(String.init),
            "Forked from [Elliotwu-7/Mac-Coffee](https://github.com/Elliotwu-7/Mac-Coffee)."
        )
    }

    func testReleaseRepositoryContainsNoInternalAgentPlanningArtifacts() {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent("docs/superpowers").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent(".superdesign").path
            ),
            "Ignored design workspaces must be removed before the release branch is published"
        )
    }

    func testShippingAppsRouteApplicationMenuQuitThroughTheSharedCoordinator() throws {
        for relativePath in [
            "Sources/Direct/MacCoffeeDirectApp.swift",
            "Sources/AppStore/MacCoffeeAppStoreApp.swift"
        ] {
            let source = try text(at: repositoryRoot.appendingPathComponent(relativePath))
            XCTAssertTrue(
                source.contains("MacCoffeeQuitCommands(") &&
                    source.contains("localization: localization") &&
                    source.contains("quitCoordinator: quitCoordinator"),
                "\(relativePath) must replace the standard application-menu Quit command"
            )
            XCTAssertTrue(
                source.contains("Window(localization.localized(\"about.title\")"),
                "\(relativePath) must update the About title bar with the selected language"
            )
        }

        let commandsSource = try text(
            at: repositoryRoot.appendingPathComponent("Sources/Core/Views/MacCoffeeQuitCommands.swift")
        )
        XCTAssertTrue(commandsSource.contains("@ObservedObject private var localization"))
        XCTAssertTrue(commandsSource.contains("Button(localization.localized(\"action.quit\"))"))

        let coordinatorSource = try text(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Core/State/QuitConfirmationCoordinator.swift"
            )
        )
        XCTAssertFalse(
            coordinatorSource.contains("addLocalMonitorForEvents"),
            "Keyboard-layout handling belongs to the native Commands shortcut"
        )
        XCTAssertFalse(coordinatorSource.contains("isQuitShortcut"))
    }

    func testAboutViewContainsInAppPrivacyAndSupportLinks() throws {
        let source = try text(
            at: repositoryRoot.appendingPathComponent("Sources/Core/Views/AboutView.swift")
        )
        XCTAssertTrue(source.contains("Link(\"about.privacyPolicy\""))
        XCTAssertTrue(source.contains("AboutView.privacyPolicyURL"))
        XCTAssertTrue(source.contains("Link(\"about.support\""))
        XCTAssertTrue(source.contains("AboutView.supportURL"))
        XCTAssertTrue(source.contains("maccoffee.about.support"))
    }

    func testAppStoreScreenshotsEmbedProductionViewsInsteadOfParallelReplicas() throws {
        let source = try text(
            at: repositoryRoot.appendingPathComponent("Tools/Screenshots/main.swift")
        )
        XCTAssertTrue(source.contains("MenuBarPanel("))
        XCTAssertTrue(source.contains("SettingsView(model:"))
        XCTAssertTrue(
            source.contains("NSHostingView"),
            "Native AppKit-backed controls must be rendered in a hosting view, not ImageRenderer"
        )
        XCTAssertFalse(source.contains("ImageRenderer("))
        XCTAssertFalse(source.contains("ScreenshotPanelCard"))
        XCTAssertFalse(source.contains("ScreenshotSettingsCard"))
        XCTAssertFalse(source.contains("ScreenshotModeRow"))
        XCTAssertFalse(source.contains("ScreenshotAction"))
    }

    func testDirectReleaseWorkflowGatesTheTagWithVersionAndTests() throws {
        let source = try text(
            at: repositoryRoot.appendingPathComponent(".github/workflows/release.yml")
        )
        XCTAssertTrue(source.contains("Verify release tag matches product version"))
        XCTAssertTrue(source.contains("-scheme MacCoffeeTests"))
        XCTAssertTrue(source.contains("-scheme MacCoffeeIntegrationTests"))
        XCTAssertTrue(source.contains("./scripts/verify-bundles.sh"))
        XCTAssertTrue(source.contains("git diff --exit-code -- MacCoffee.xcodeproj"))
        let generation = try XCTUnwrap(source.range(of: "xcodegen generate"))
        let tests = try XCTUnwrap(source.range(of: "-scheme MacCoffeeTests"))
        XCTAssertLessThan(
            source.distance(from: source.startIndex, to: generation.lowerBound),
            source.distance(from: source.startIndex, to: tests.lowerBound),
            "The release must regenerate its project before compiling tests"
        )
    }

    func testContinuousIntegrationRunsTheMCPIntegrationSuite() throws {
        let source = try text(
            at: repositoryRoot.appendingPathComponent(".github/workflows/ci.yml")
        )

        XCTAssertTrue(source.contains("-scheme MacCoffeeTests"))
        XCTAssertTrue(source.contains("-scheme MacCoffeeIntegrationTests"))
    }

    func testMCPBrokerUsesTheCanonicalProductVersion() throws {
        let data = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("Resources/MCPBroker/Info.plist")
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")

        let project = try text(at: repositoryRoot.appendingPathComponent("project.yml"))
        let brokerStart = try XCTUnwrap(project.range(of: "  MacCoffeeMCPBroker:"))
        let helperStart = try XCTUnwrap(
            project.range(of: "\n  MacCoffeeMCP:", range: brokerStart.upperBound..<project.endIndex)
        )
        let brokerTarget = String(project[brokerStart.lowerBound..<helperStart.lowerBound])
        XCTAssertTrue(brokerTarget.contains("Debug: Config/Shared.xcconfig"))
        XCTAssertTrue(brokerTarget.contains("Release: Config/Shared.xcconfig"))
    }

    func testMCPBuildConfigurationIsDirectOnly() throws {
        let source = try text(at: repositoryRoot.appendingPathComponent("project.yml"))

        XCTAssertTrue(source.contains("MacCoffeeAppStoreCore:"))
        XCTAssertTrue(source.contains("PRODUCT_NAME: MacCoffeeAppStoreCore"))
        XCTAssertTrue(source.contains("- MCP"))
        XCTAssertTrue(source.contains("- target: MacCoffeeAppStoreCore"))
        XCTAssertTrue(source.contains("- target: MacCoffeeMCP\n        embed: true"))
        XCTAssertTrue(source.contains("destination: wrapper\n          subpath: Contents/Helpers"))
    }

    func testEmbeddedMCPExecutablesEnableHardenedRuntime() throws {
        let project = try text(at: repositoryRoot.appendingPathComponent("project.yml"))
        let releaseScript = try text(
            at: repositoryRoot.appendingPathComponent("scripts/release-direct.sh")
        )

        XCTAssertTrue(
            project.contains(
                "MacCoffeeMCPBroker:\n" +
                    "    type: xpc-service\n" +
                    "    platform: macOS\n" +
                    "    configFiles:\n" +
                    "      Debug: Config/Shared.xcconfig\n" +
                    "      Release: Config/Shared.xcconfig"
            )
        )
        XCTAssertTrue(releaseScript.contains("MacCoffeeMCPBroker.xpc"))
        XCTAssertTrue(releaseScript.contains("does not have Hardened Runtime enabled"))
    }

    func testMCPSettingsLinkTargetsPublishedSecurityPolicy() throws {
        let source = try text(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Direct/MCP/MCPSettingsView.swift"
            )
        )
        XCTAssertTrue(
            source.contains(
                "https://github.com/rekurt/Mac-Coffee/blob/main/docs/SECURITY.md"
            )
        )
    }

    func testBuiltDistributionsKeepMCPArtifactsAndSymbolsDirectOnly() throws {
        let productsDirectory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let directApp = productsDirectory.appendingPathComponent("Mac Coffee.app")
        let appStoreApp = productsDirectory.appendingPathComponent("Mac Coffee App Store Test.app")

        XCTAssertTrue(FileManager.default.fileExists(atPath: directApp.path), directApp.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appStoreApp.path), appStoreApp.path)

        let directHelper = directApp.appendingPathComponent("Contents/Helpers/MacCoffeeMCP")
        let directBroker = directApp.appendingPathComponent(
            "Contents/XPCServices/MacCoffeeMCPBroker.xpc"
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: directHelper.path), directHelper.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directBroker.path), directBroker.path)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: appStoreApp.appendingPathComponent("Contents/Helpers/MacCoffeeMCP").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: appStoreApp.appendingPathComponent(
                    "Contents/XPCServices/MacCoffeeMCPBroker.xpc"
                ).path
            )
        )

        let directCore = directApp.appendingPathComponent(
            "Contents/Frameworks/MacCoffeeCore.framework/Versions/A/MacCoffeeCore"
        )
        let appStoreCore = appStoreApp.appendingPathComponent(
            "Contents/Frameworks/MacCoffeeAppStoreCore.framework/Versions/A/MacCoffeeAppStoreCore"
        )
        XCTAssertTrue(try symbols(in: directCore).contains("MCPControlService"), directCore.path)
        XCTAssertFalse(try symbols(in: appStoreCore).contains("MCP"), appStoreCore.path)
    }

    func testDirectMCPBrokerUsesTheDirectApplicationServiceNamespace() throws {
        let productsDirectory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let directApp = productsDirectory.appendingPathComponent("Mac Coffee.app")
        let brokerInfo = directApp.appendingPathComponent(
            "Contents/XPCServices/MacCoffeeMCPBroker.xpc/Contents/Info.plist"
        )
        let appInfo = directApp.appendingPathComponent("Contents/Info.plist")
        let appData = try Data(contentsOf: appInfo)
        let appPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: appData, format: nil) as? [String: Any]
        )
        let data = try Data(contentsOf: brokerInfo)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let applicationIdentifier = try XCTUnwrap(appPlist["CFBundleIdentifier"] as? String)

        XCTAssertEqual(
            plist["CFBundleIdentifier"] as? String,
            "\(applicationIdentifier).mcp-broker"
        )
    }

    func testLegacyCleanupRestoresTheCompleteLegacyBatterySignature() throws {
        let source = try text(
            at: repositoryRoot.appendingPathComponent("scripts/uninstall-legacy-helper.sh")
        )
        XCTAssertTrue(source.contains("battery_sleep"))
        XCTAssertTrue(source.contains("battery_disablesleep"))
        XCTAssertTrue(source.contains("-b sleep 5 disablesleep 0"))
        XCTAssertTrue(source.contains("com.elliotwu.maccoffee.helper.log"))
    }

    func testLegacyPowerPolicyChangesOnlyTheExactLegacySignature() throws {
        let policy = repositoryRoot.appendingPathComponent("scripts/legacy-power-policy.zsh")

        XCTAssertEqual(try runLegacyPolicy(policy, sleep: "0", disablesleep: "1"), "sleep 5 disablesleep 0")
        XCTAssertEqual(try runLegacyPolicy(policy, sleep: "10", disablesleep: "1"), "")
        XCTAssertEqual(try runLegacyPolicy(policy, sleep: "0", disablesleep: "0"), "")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func symbols(in executable: URL) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-gj", executable.path]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(decoding: error, as: UTF8.self)
        )
        return String(decoding: output, as: UTF8.self)
    }

    private func runLegacyPolicy(_ script: URL, sleep: String, disablesleep: String) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            "source \"$1\"; legacy_battery_restore_arguments \"$2\" \"$3\"",
            "maccoffee-policy-test",
            script.path,
            sleep,
            disablesleep,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
        return String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

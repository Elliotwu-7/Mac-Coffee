import AppKit
import ImageIO
import MacCoffeeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MacCoffeeScreenshotGenerator {
    private static let canvasSize = CGSize(width: 1_280, height: 800)
    private static let locales: [(directory: String, language: SupportedLanguage)] = [
        ("en-US", .english),
        ("ru", .russian),
        ("zh-Hans", .simplifiedChinese)
    ]

    static func run() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ScreenshotError.usage
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .standardizedFileURL
        NSApplication.shared.setActivationPolicy(.prohibited)

        for locale in locales {
            let fixture = try ScreenshotFixture(language: locale.language)
            let output = root
                .appendingPathComponent("metadata", isDirectory: true)
                .appendingPathComponent(locale.directory, isDirectory: true)
                .appendingPathComponent("screenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

            let panel = LocalizedRootView(localization: fixture.localization) {
                PanelScreenshot(
                    model: fixture.model,
                    localization: fixture.localization,
                    updater: fixture.updater,
                    quitCoordinator: fixture.quitCoordinator
                )
            }
            try write(panel, to: output.appendingPathComponent("01-menu-bar.png"))

            let settings = LocalizedRootView(localization: fixture.localization) {
                SettingsScreenshot(
                    model: fixture.model,
                    localization: fixture.localization
                )
            }
            try write(settings, to: output.appendingPathComponent("02-settings.png"))
        }

        try copyRepositoryPreviews(from: root)
        print("Generated 6 localized App Store screenshots and 2 repository previews.")
    }

    private static func write<V: View>(_ view: V, to url: URL) throws {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let hostingView = NSHostingView(
            rootView: view
                .frame(width: canvasSize.width, height: canvasSize.height)
                .preferredColorScheme(.dark)
        )
        hostingView.frame = bounds

        // Picker, Form, Link, and other native AppKit-backed SwiftUI controls do
        // not render reliably through ImageRenderer. Attach the production view
        // hierarchy to a real off-screen window before taking the bitmap snapshot.
        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderBack(nil)
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw ScreenshotError.renderFailed(url.lastPathComponent)
        }
        hostingView.cacheDisplay(in: bounds, to: representation)
        guard let renderedImage = representation.cgImage else {
            throw ScreenshotError.renderFailed(url.lastPathComponent)
        }
        window.orderOut(nil)
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(canvasSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ScreenshotError.bitmapFailed
        }
        context.setFillColor(
            CGColor(red: 0.055, green: 0.067, blue: 0.095, alpha: 1)
        )
        context.fill(CGRect(origin: .zero, size: canvasSize))
        context.draw(renderedImage, in: CGRect(origin: .zero, size: canvasSize))
        guard let opaqueImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else {
            throw ScreenshotError.encodingFailed
        }
        CGImageDestinationAddImage(destination, opaqueImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.encodingFailed
        }
    }

    private static func copyRepositoryPreviews(from root: URL) throws {
        let images = root.appendingPathComponent("docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let copies = [
            ("metadata/en-US/screenshots/01-menu-bar.png", "panel-en.png"),
            ("metadata/ru/screenshots/02-settings.png", "settings-ru.png")
        ]
        for (source, destination) in copies {
            let destinationURL = images.appendingPathComponent(destination)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(
                at: root.appendingPathComponent(source),
                to: destinationURL
            )
        }
    }
}

private struct PanelScreenshot: View {
    @ObservedObject var model: AppModel
    let localization: LocalizationController
    let updater: ScreenshotUpdater
    let quitCoordinator: QuitConfirmationCoordinator

    var body: some View {
        ScreenshotDesktop(model: model) {
            HStack(spacing: 54) {
                ScreenshotCaption(
                    eyebrow: localization.localized("app.name"),
                    title: localization.localized("mode.system"),
                    detail: localization.localized("about.description")
                )
                .frame(width: 520, alignment: .leading)

                VStack(spacing: 0) {
                    WindowChrome(title: localization.localized("app.name"))
                    MenuBarPanel(
                        model: model,
                        updater: updater,
                        quitCoordinator: quitCoordinator,
                        panelWidth: 420
                    )
                    .background(Color(nsColor: .windowBackgroundColor))
                }
                .frame(width: 420)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 32, y: 20)
            }
        }
    }
}

private struct SettingsScreenshot: View {
    @ObservedObject var model: AppModel
    let localization: LocalizationController

    var body: some View {
        ScreenshotDesktop(model: model) {
            VStack(alignment: .leading, spacing: 26) {
                ScreenshotCaption(
                    eyebrow: localization.localized("settings.title"),
                    title: localization.localized("settings.language"),
                    detail: localization.localized("settings.language.help")
                )

                VStack(spacing: 0) {
                    WindowChrome(title: localization.localized("settings.title"))
                    SettingsView(model: model)
                        .frame(width: 860)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
                .frame(width: 860)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 32, y: 20)
            }
        }
    }
}

private struct ScreenshotDesktop<Content: View>: View {
    @ObservedObject var model: AppModel
    let content: Content

    init(model: AppModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.067, blue: 0.095),
                    Color(red: 0.11, green: 0.075, blue: 0.12),
                    Color(red: 0.05, green: 0.10, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.orange.opacity(0.16))
                .frame(width: 520, height: 520)
                .blur(radius: 110)
                .offset(x: 480, y: -250)
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 460, height: 460)
                .blur(radius: 130)
                .offset(x: -520, y: 330)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    MenuBarLabel(model: model)
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                    Text("09:41")
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                .padding(.horizontal, 22)
                .frame(height: 34)
                .background(.black.opacity(0.34))

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(54)
            }
        }
    }
}

private struct ScreenshotCaption: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(eyebrow, systemImage: "cup.and.saucer.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WindowChrome: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red.opacity(0.78)).frame(width: 12, height: 12)
            Circle().fill(Color.yellow.opacity(0.78)).frame(width: 12, height: 12)
            Circle().fill(Color.green.opacity(0.78)).frame(width: 12, height: 12)
            Spacer()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Color.clear.frame(width: 52, height: 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10))
    }
}

@MainActor
private final class ScreenshotFixture {
    let localization: LocalizationController
    let model: AppModel
    let updater: ScreenshotUpdater
    let quitCoordinator: QuitConfirmationCoordinator

    init(language: SupportedLanguage) throws {
        let settings = ScreenshotSettingsStore(selectedLanguage: language)
        let localization = LocalizationController(settings: settings)
        let environment = AppEnvironment(
            powerAssertions: ScreenshotPowerAssertionManager(),
            battery: ScreenshotBatteryMonitor(),
            scheduler: ScreenshotSessionScheduler(),
            settings: settings,
            launchAtLogin: ScreenshotLaunchAtLoginManager(),
            notifications: ScreenshotNotificationSender(),
            lifecycle: ScreenshotLifecycleObserver(),
            localization: localization
        )
        let model = AppModel(environment: environment)
        self.localization = localization
        self.model = model
        let updater = ScreenshotUpdater()
        self.updater = updater
        if let version = ProcessInfo.processInfo.environment["MACCOFFEE_SCREENSHOT_UPDATE_VERSION"] {
            updater.state.present(version: version)
        }
        quitCoordinator = QuitConfirmationCoordinator(model: model)
        try model.setMode(.system)
    }
}

@MainActor
private final class ScreenshotUpdater: UpdaterProviding {
    let state = UpdateStateController()
    var canCheckForUpdates = true

    func checkForUpdates() {}
    func showAvailableUpdate() {}
    func dismissAvailableUpdate() { state.dismiss() }
}

private final class ScreenshotSettingsStore: SettingsStoring {
    var selectedLanguage: SupportedLanguage
    var selectedDuration: SessionDuration = .hours2
    var batteryThreshold = 15
    var launchAtLoginRequested = false
    var notificationAuthorizationRequested = false
    var lastAnnouncedUpdateVersion: String?
    var mcpEnabled = false

    init(selectedLanguage: SupportedLanguage) {
        self.selectedLanguage = selectedLanguage
    }
}

private final class ScreenshotPowerAssertionManager: PowerAssertionManaging {
    private(set) var activeMode: WakeMode = .off

    func transition(to mode: WakeMode) throws {
        activeMode = mode
    }

    func releaseAll() {
        activeMode = .off
    }
}

@MainActor
private final class ScreenshotBatteryMonitor: BatteryMonitoring {
    let currentState = BatteryState(
        powerSource: .battery,
        percentage: 82,
        hasInternalBattery: true
    )
    var onChange: ((BatteryState) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class ScreenshotSessionScheduler: SessionScheduling {
    private(set) var hasScheduledAction = false

    func schedule(
        deadline: Date,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        hasScheduledAction = true
    }

    func cancel() {
        hasScheduledAction = false
    }
}

@MainActor
private final class ScreenshotLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var status: LaunchAtLoginStatus = .disabled

    func setEnabled(_ enabled: Bool) throws {
        status = enabled ? .enabled : .disabled
    }
}

@MainActor
private final class ScreenshotNotificationSender: NotificationSending {
    func requestAuthorizationIfNeeded() {}
    func send(_ event: AppNotificationEvent) {}
}

@MainActor
private final class ScreenshotLifecycleObserver: LifecycleObserving {
    var onWake: (() -> Void)?
    var onClockChange: (() -> Void)?
    var onActivation: (() -> Void)?
    var onTermination: (() -> Void)?

    func start() {}
    func stop() {}
}

private enum ScreenshotError: LocalizedError {
    case usage
    case renderFailed(String)
    case bitmapFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: MacCoffeeScreenshots <repository-root>"
        case let .renderFailed(name):
            "Could not render \(name)."
        case .bitmapFailed:
            "Could not allocate the screenshot bitmap."
        case .encodingFailed:
            "Could not encode a PNG screenshot."
        }
    }
}

do {
    try MainActor.assumeIsolated {
        try MacCoffeeScreenshotGenerator.run()
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}

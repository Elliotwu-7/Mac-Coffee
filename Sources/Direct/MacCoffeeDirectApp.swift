import AppKit
import MacCoffeeCore
import SwiftUI

@main
@MainActor
struct MacCoffeeDirectApp: App {
    @StateObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController
    private let updater: SparkleUpdater
    private let updateNoticeCoordinator: UpdateNoticeCoordinator
    private let mcpEnvironment: DirectMCPEnvironment
    private let quitCoordinator: QuitConfirmationCoordinator
#if DEBUG
    private static var uiTestWindowController: NSWindowController?
#endif

    init() {
        let updater = SparkleUpdater()
        let environment: AppEnvironment
#if DEBUG
        environment = UITestEnvironment.makeIfRequested(updater: updater) ?? .live(updater: updater)
#else
        environment = .live(updater: updater)
#endif
        let model = AppModel(environment: environment)
        guard let mcpSettingsStore = environment.settings as? MCPSettingsStoring else {
            preconditionFailure("Direct settings store must support MCP preferences")
        }
        let mcpEnvironment = DirectMCPEnvironment.live(
            model: model,
            settingsStore: mcpSettingsStore
        )
        environment.termination.register { [weak mcpEnvironment] in
            mcpEnvironment?.prepareForTermination()
        }
        self.updater = updater
        let updateNoticeCoordinator = UpdateNoticeCoordinator(
            state: updater.state,
            settings: environment.settings,
            notifications: environment.notifications
        )
        self.updateNoticeCoordinator = updateNoticeCoordinator
        self.mcpEnvironment = mcpEnvironment
        let quitCoordinator = QuitConfirmationCoordinator(model: model)
        self.quitCoordinator = quitCoordinator
        _model = StateObject(wrappedValue: model)
        _localization = ObservedObject(wrappedValue: environment.localization)
        mcpEnvironment.startIfEnabled()
#if DEBUG
        if let updateVersion = CommandLine.arguments
            .first(where: { $0.hasPrefix("--ui-testing-update-version=") })
            .map({ String($0.split(separator: "=", maxSplits: 1).last ?? "") }),
           !updateVersion.isEmpty {
            updater.state.present(version: updateVersion)
        }
#endif
#if DEBUG
        Self.openUITestWindowIfRequested(
            model: model,
            updater: updater,
            quitCoordinator: quitCoordinator
        )
#endif
    }

    var body: some Scene {
        MenuBarExtra {
            LocalizedRootView(localization: localization) {
                MenuBarPanel(
                    model: model,
                    updater: updater,
                    quitCoordinator: quitCoordinator
                )
            }
        } label: {
            LocalizedRootView(localization: localization) {
                MenuBarLabel(model: model)
            }
        }
        .menuBarExtraStyle(.window)
        .commands {
            MacCoffeeQuitCommands(
                localization: localization,
                quitCoordinator: quitCoordinator
            )
        }

        Settings {
            LocalizedRootView(localization: localization) {
                SettingsView(model: model) {
                    UpdateSettingsView(
                        updater: updater,
                        localization: localization
                    )
                    MCPSettingsView(environment: mcpEnvironment)
                }
            }
        }

        Window(localization.localized("about.title"), id: "maccoffee.about") {
            LocalizedRootView(localization: localization) {
                AboutView(localization: localization)
            }
        }
        .windowResizability(.contentSize)
    }

#if DEBUG
    private static func openUITestWindowIfRequested(
        model: AppModel,
        updater: SparkleUpdater,
        quitCoordinator: QuitConfirmationCoordinator
    ) {
        guard CommandLine.arguments.contains("--ui-testing-window") else { return }
        let windowWidth = uiTestWindowWidth()
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Mac Coffee"
            window.identifier = NSUserInterfaceItemIdentifier("maccoffee.ui-test.window")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: LocalizedRootView(localization: model.environment.localization) {
                    MenuBarPanel(
                        model: model,
                        updater: updater,
                        quitCoordinator: quitCoordinator,
                        panelWidth: windowWidth
                    )
                }
            )
            let contentSize = NSSize(width: windowWidth, height: 680)
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
            window.setContentSize(contentSize)
            centerOnDeterministicUITestScreen(window)
            let controller = NSWindowController(window: window)
            uiTestWindowController = controller
            controller.showWindow(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private static func uiTestWindowWidth() -> CGFloat {
        guard let width = CommandLine.arguments
            .first(where: { $0.hasPrefix("--ui-testing-window-width=") })
            .flatMap({ Double($0.split(separator: "=").last ?? "") }), width > 0
        else {
            return 420
        }
        return CGFloat(min(width, 420))
    }

    private static func centerOnDeterministicUITestScreen(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first
        else { return }
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        ))
    }
#endif
}

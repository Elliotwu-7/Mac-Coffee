import AppKit
import MacCoffeeAppStoreCore
import SwiftUI

@main
@MainActor
struct MacCoffeeAppStoreApp: App {
    @StateObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController
    private let quitCoordinator: QuitConfirmationCoordinator
#if DEBUG
    private static var uiTestWindowController: NSWindowController?
#endif

    init() {
        let model = AppModel(environment: .live())
        let quitCoordinator = QuitConfirmationCoordinator(model: model)
        self.quitCoordinator = quitCoordinator
        _model = StateObject(wrappedValue: model)
        _localization = ObservedObject(wrappedValue: model.environment.localization)
#if DEBUG
        Self.openUITestWindowIfRequested(model: model, quitCoordinator: quitCoordinator)
#endif
    }

    var body: some Scene {
        MenuBarExtra {
            LocalizedRootView(localization: localization) {
                MenuBarPanel(model: model, quitCoordinator: quitCoordinator)
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
                SettingsView(model: model)
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
                        quitCoordinator: quitCoordinator,
                        panelWidth: windowWidth
                    )
                }
            )
            let contentSize = NSSize(width: windowWidth, height: 680)
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
            window.setContentSize(contentSize)
            window.center()
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
#endif
}

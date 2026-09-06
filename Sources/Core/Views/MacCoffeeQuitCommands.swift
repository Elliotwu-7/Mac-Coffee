import SwiftUI

/// Replaces the standard application-menu Quit command with the same
/// confirmation and cleanup path used by the menu-bar panel.
@MainActor
public struct MacCoffeeQuitCommands: Commands {
    @ObservedObject private var localization: LocalizationController
    private let quitCoordinator: QuitConfirmationCoordinator

    public init(
        localization: LocalizationController,
        quitCoordinator: QuitConfirmationCoordinator
    ) {
        _localization = ObservedObject(wrappedValue: localization)
        self.quitCoordinator = quitCoordinator
    }

    public var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(localization.localized("action.quit")) {
                quitCoordinator.requestQuit()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

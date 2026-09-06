import AppKit

/// Owns every user-initiated quit path so cleanup cannot be bypassed by a
/// transient menu-bar window or the default application termination command.
@MainActor
public final class QuitConfirmationCoordinator {
    public typealias Presenter = @MainActor (NSAlert) -> NSApplication.ModalResponse
    public typealias Action = @MainActor () -> Void

    private let localization: LocalizationController
    private let present: Presenter
    private let prepareForTermination: Action
    private let terminate: Action
    private var isPresenting = false
    private var didConfirmTermination = false

    public convenience init(
        model: AppModel,
        application: NSApplication = .shared
    ) {
        self.init(
            localization: model.environment.localization,
            present: { alert in
                application.activate(ignoringOtherApps: true)
                return alert.runModal()
            },
            prepareForTermination: model.prepareForTermination,
            terminate: { application.terminate(nil) }
        )
    }

    init(
        localization: LocalizationController,
        present: @escaping Presenter,
        prepareForTermination: @escaping Action,
        terminate: @escaping Action
    ) {
        self.localization = localization
        self.present = present
        self.prepareForTermination = prepareForTermination
        self.terminate = terminate
    }

    public func requestQuit() {
        guard !isPresenting, !didConfirmTermination else { return }

        isPresenting = true
        let response = present(makeAlert())
        isPresenting = false

        guard response == .alertFirstButtonReturn, !didConfirmTermination else { return }
        didConfirmTermination = true
        prepareForTermination()
        terminate()
    }

    private func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localization.localized("action.quit")
        alert.informativeText = localization.localized("quit.message")
        let confirmButton = alert.addButton(
            withTitle: localization.localized("action.confirmQuit")
        )
        confirmButton.hasDestructiveAction = true
        let cancelButton = alert.addButton(
            withTitle: localization.localized("action.cancel")
        )
        cancelButton.keyEquivalent = "\u{1b}"
        let identifier = "maccoffee.quit.confirmation"
        alert.window.identifier = NSUserInterfaceItemIdentifier(identifier)
        alert.window.setAccessibilityIdentifier(identifier)
        confirmButton.setAccessibilityIdentifier("maccoffee.quit.confirm")
        cancelButton.setAccessibilityIdentifier("maccoffee.quit.cancel")
        return alert
    }
}

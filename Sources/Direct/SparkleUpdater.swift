import Foundation
import MacCoffeeCore
import Sparkle

@MainActor
final class SparkleUpdater: NSObject, UpdaterProviding, @preconcurrency SPUStandardUserDriverDelegate {
    let state = UpdateStateController()
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = feed?.hasPrefix("https://") == true && publicKey?.isEmpty == false
        super.init()
        if isConfigured {
            controller.startUpdater()
        }
    }

    var canCheckForUpdates: Bool {
#if DEBUG
        if CommandLine.arguments.contains("--ui-testing-force-update-capability") {
            return true
        }
#endif
        return isConfigured && controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func showAvailableUpdate() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
    }

    func dismissAvailableUpdate() {
        state.dismiss()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state userState: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !userState.userInitiated else { return }
        state.present(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        state.dismiss()
    }

    func standardUserDriverWillFinishUpdateSession() {
        state.dismiss()
    }
}

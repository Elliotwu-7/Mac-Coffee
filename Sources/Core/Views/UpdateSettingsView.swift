import Foundation
import SwiftUI

public struct UpdateSettingsView: View {
    @ObservedObject private var state: UpdateStateController
    @ObservedObject private var localization: LocalizationController
    private let updater: UpdaterProviding
    private let currentVersion: String

    public init(
        updater: UpdaterProviding,
        localization: LocalizationController,
        bundle: Bundle = .main
    ) {
        self.updater = updater
        _state = ObservedObject(wrappedValue: updater.state)
        _localization = ObservedObject(wrappedValue: localization)
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    public var body: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: localization.format("settings.updates.currentVersion", arguments: currentVersion))
                    Text("settings.updates.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("action.checkUpdates") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                .accessibilityIdentifier("maccoffee.settings.checkUpdates")
            }

            if state.availableRelease != nil {
                Button("update.action.install") {
                    updater.showAvailableUpdate()
                }
                .accessibilityIdentifier("maccoffee.settings.installUpdate")
            }
        } header: {
            Text("settings.updates")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maccoffee.settings.updates")
    }
}

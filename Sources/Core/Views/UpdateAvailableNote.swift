import SwiftUI

struct UpdateAvailableNote: View {
    @ObservedObject private var state: UpdateStateController
    @ObservedObject private var localization: LocalizationController
    private let updater: UpdaterProviding

    init(updater: UpdaterProviding, localization: LocalizationController) {
        self.updater = updater
        _state = ObservedObject(wrappedValue: updater.state)
        _localization = ObservedObject(wrappedValue: localization)
    }

    var body: some View {
        if let release = state.availableRelease {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: localization.format("update.note.title", arguments: release.version))
                        .font(.callout.weight(.semibold))
                    Text("update.note.message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    Button("update.action.install") {
                        updater.showAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("maccoffee.update.install")

                    Button("update.action.later") {
                        updater.dismissAvailableUpdate()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("maccoffee.update.later")
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("maccoffee.update.note")
        }
    }
}

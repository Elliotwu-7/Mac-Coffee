import SwiftUI

public struct ModePicker: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController
    @State private var selection: WakeMode

    public init(model: AppModel) {
        self.model = model
        _localization = ObservedObject(wrappedValue: model.environment.localization)
        _selection = State(initialValue: model.mode)
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            segmentedPicker
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                // Keep the segmented controls at a width that preserves their
                // labels; ViewThatFits selects the native vertical picker below it.
                .frame(minWidth: 340)
                .accessibilityIdentifier("maccoffee.mode.segmented")
                .background(segmentedLayoutMarker)

            VStack(alignment: .leading, spacing: 8) {
                Text("mode.title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("mode.title"))
                    .accessibilityIdentifier("maccoffee.mode.fallback.title")
                fallbackPicker
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                Text(selection.localizedSubtitle(using: localization))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text(verbatim: selection.localizedSubtitle(using: localization)))
                    .accessibilityIdentifier("maccoffee.mode.fallback.subtitle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("maccoffee.mode.fallback")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .disabled(model.isBusy)
        .accessibilityIdentifier("maccoffee.mode.picker")
        .accessibilityValue(Text(verbatim: localization.format(
            "accessibility.modeValue",
            arguments: model.mode.localizedTitle(using: localization)
        )))
        .onChange(of: selection) { mode in
            Task { @MainActor in
                try? model.setMode(mode)
                selection = model.mode
            }
        }
        .onChange(of: model.mode) { mode in
            selection = mode
        }
    }

    @ViewBuilder
    private var segmentedLayoutMarker: some View {
#if DEBUG
        Text(verbatim: "maccoffee.mode.segmented")
            .font(.system(size: 1))
            .lineLimit(1)
            .fixedSize()
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("maccoffee.mode.segmented")
#endif
    }

    private var segmentedPicker: some View {
        Picker("mode.title", selection: $selection) {
            Text("mode.off")
                .tag(WakeMode.off)
                .accessibilityIdentifier("maccoffee.mode.off")
            Text("mode.system")
                .tag(WakeMode.system)
                .accessibilityIdentifier("maccoffee.mode.system")
            Text("mode.display")
                .tag(WakeMode.display)
                .accessibilityIdentifier("maccoffee.mode.display")
        }
    }

    private var fallbackPicker: some View {
        Picker("mode.title", selection: $selection) {
            Label("mode.off", systemImage: "moon.zzz")
                .tag(WakeMode.off)
                .accessibilityIdentifier("maccoffee.mode.off")
            Label("mode.system", systemImage: "bolt.circle")
                .tag(WakeMode.system)
                .accessibilityIdentifier("maccoffee.mode.system")
            Label("mode.display", systemImage: "display")
                .tag(WakeMode.display)
                .accessibilityIdentifier("maccoffee.mode.display")
        }
    }
}

public extension WakeMode {
    @MainActor
    func localizedTitle(using localization: LocalizationController) -> String {
        localization.localized(localizationKey)
    }

    @MainActor
    func localizedSubtitle(using localization: LocalizationController) -> String {
        localization.localized("\(localizationKey).subtitle")
    }

    var localizationKey: String {
        switch self {
        case .off: "mode.off"
        case .system: "mode.system"
        case .display: "mode.display"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "moon.zzz"
        case .system: "bolt.circle"
        case .display: "display"
        }
    }
}

import SwiftUI

public struct DurationPicker: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController
    @State private var selection: SessionDuration

    public init(model: AppModel) {
        self.model = model
        _localization = ObservedObject(wrappedValue: model.environment.localization)
        _selection = State(initialValue: model.selectedDuration)
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            picker
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 340)
            picker
                .frame(maxWidth: .infinity)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("maccoffee.duration.picker")
        .accessibilityValue(Text(verbatim: localization.format(
            "accessibility.durationValue",
            arguments: model.selectedDuration.localizedTitle(using: localization)
        )))
        .onChange(of: selection) { duration in
            Task { @MainActor in
                model.selectDuration(duration)
                selection = model.selectedDuration
            }
        }
        .onChange(of: model.selectedDuration) { duration in
            selection = duration
        }
    }

    private var picker: some View {
        Picker(
            "duration.title",
            selection: $selection
        ) {
            ForEach(SessionDuration.allCases, id: \.self) { duration in
                Text(verbatim: duration.localizedTitle(using: localization))
                    .tag(duration)
                    .accessibilityIdentifier("maccoffee.duration.\(duration.rawValue)")
            }
        }
    }
}

public extension SessionDuration {
    @MainActor
    func localizedTitle(using localization: LocalizationController) -> String {
        localization.localized(localizationKey)
    }

    var localizationKey: String {
        switch self {
        case .minutes30: "duration.minutes30"
        case .hours1: "duration.hours1"
        case .hours2: "duration.hours2"
        case .hours4: "duration.hours4"
        case .hours8: "duration.hours8"
        case .indefinite: "duration.indefinite"
        }
    }
}

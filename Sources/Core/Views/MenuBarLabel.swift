import SwiftUI

public struct MenuBarLabel: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController

    public init(model: AppModel) {
        self.model = model
        _localization = ObservedObject(wrappedValue: model.environment.localization)
    }

    public var body: some View {
        Image(systemName: model.mode.systemImage)
            .symbolVariant(model.mode == .off ? .none : .fill)
            .accessibilityLabel(Text("app.name"))
            .accessibilityValue(Text(verbatim: localization.format(
                "accessibility.modeValue",
                arguments: model.mode.localizedTitle(using: localization)
            )))
    }
}

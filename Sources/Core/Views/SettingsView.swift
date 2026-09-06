import AppKit
import SwiftUI

public struct SettingsView<AdditionalContent: View>: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController
    private let additionalContent: AdditionalContent

    public init(
        model: AppModel,
        @ViewBuilder additionalContent: () -> AdditionalContent
    ) {
        self.model = model
        self.additionalContent = additionalContent()
        _localization = ObservedObject(wrappedValue: model.environment.localization)
    }

    public var body: some View {
        Form {
            Section {
                Picker(
                    "settings.language",
                    selection: Binding(
                        get: { localization.selectedLanguage },
                        set: { localization.select($0) }
                    )
                ) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language.localizedName(using: localization))
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("maccoffee.settings.language")

                Text("settings.language.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("settings.language")
            }

            if model.batteryState.hasInternalBattery {
                Section {
                    HStack {
                        Text("settings.batteryThreshold")
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { model.batteryThreshold },
                                set: { threshold in model.setBatteryThreshold(threshold) }
                            ),
                            in: LowBatteryPolicy.thresholdRange
                        ) {
                            Text(verbatim: localization.format(
                                "settings.batteryThresholdValue",
                                arguments: model.batteryThreshold
                            ))
                                .monospacedDigit()
                        }
                        .accessibilityIdentifier("maccoffee.settings.batteryThreshold")
                    }
                    Text("settings.batteryHelp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(
                    "settings.launchAtLogin",
                    isOn: Binding(
                        get: { model.launchAtLoginStatus == .enabled },
                        set: { try? model.setLaunchAtLogin($0) }
                    )
                )
                .disabled(model.launchAtLoginStatus == .unavailable)
                .accessibilityIdentifier("maccoffee.settings.launchAtLogin")

                if model.launchAtLoginStatus == .requiresApproval {
                    Text("settings.launchRequiresApproval")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.launchAtLoginStatus == .unavailable {
                    Text("settings.launchUnavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            additionalContent
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, idealWidth: 600, minHeight: 420, idealHeight: 620)
        .navigationTitle(Text("settings.title"))
        .onAppear(perform: centerSettingsWindowForUITests)
    }

    private func centerSettingsWindowForUITests() {
        DispatchQueue.main.async {
            let settingsIdentifier = "com_apple_SwiftUI_Settings_window"
            guard let window = NSApplication.shared.windows.first(where: {
                $0.identifier?.rawValue == settingsIdentifier
            }) else { return }
#if DEBUG
            if CommandLine.arguments.contains("--ui-testing-window"),
               let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.screens.first {
                let visibleFrame = screen.visibleFrame
                window.setFrameOrigin(NSPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                ))
            }
#endif
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

public extension SettingsView where AdditionalContent == EmptyView {
    init(model: AppModel) {
        self.init(model: model) { EmptyView() }
    }
}

private extension SupportedLanguage {
    @MainActor
    func localizedName(using localization: LocalizationController) -> String {
        switch self {
        case .system:
            localization.localized("settings.language.system")
        default:
            displayName
        }
    }
}

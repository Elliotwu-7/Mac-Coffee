import SwiftUI

/// Supplies one runtime-selected locale to an entire SwiftUI root.
public struct LocalizedRootView<Content: View>: View {
    @ObservedObject private var localization: LocalizationController
    private let content: Content

    public init(
        localization: LocalizationController,
        @ViewBuilder content: () -> Content
    ) {
        _localization = ObservedObject(wrappedValue: localization)
        self.content = content()
    }

    public var body: some View {
        content.environment(\.locale, localization.locale)
    }
}

public struct MenuBarPanel: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var localization: LocalizationController
    private let updater: UpdaterProviding?
    private let quitCoordinator: QuitConfirmationCoordinator
    private let panelWidth: CGFloat?

    public init(
        model: AppModel,
        updater: UpdaterProviding? = nil,
        quitCoordinator: QuitConfirmationCoordinator,
        panelWidth: CGFloat? = nil
    ) {
        self.model = model
        _localization = ObservedObject(wrappedValue: model.environment.localization)
        self.updater = updater
        self.quitCoordinator = quitCoordinator
        self.panelWidth = panelWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ModePicker(model: model)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text("duration.title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DurationPicker(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusCard

            if let statusMessage = model.statusMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(statusMessage)
                        .font(.caption)
                    Spacer(minLength: 0)
                    Button {
                        model.dismissStatus()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("action.dismiss"))
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("maccoffee.status.banner")
            }

            if let updater {
                UpdateAvailableNote(updater: updater, localization: localization)
            }

            Divider()

            MenuBarFooter(
                quitCoordinator: quitCoordinator,
                panelWidth: panelWidth
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        // A deterministic UI-test host supplies an explicit panel width. Keep all
        // three constraints equal in that case so the hosted AppKit window and
        // SwiftUI content report the same geometry. Production remains flexible.
        .frame(
            minWidth: panelWidth ?? 0,
            idealWidth: panelWidth ?? 420,
            maxWidth: FooterLayoutMetrics.panelMaximumWidth(panelWidth: panelWidth)
        )
        .onAppear { updater?.state.panelDidAppear() }
        .onDisappear { updater?.state.panelDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        model.mode == .off
                            ? Color.secondary.opacity(0.10)
                            : Color.accentColor.opacity(0.13)
                    )
                Image(systemName: model.mode.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolVariant(model.mode == .off ? .none : .fill)
                    .foregroundStyle(model.mode == .off ? Color.secondary : Color.accentColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("app.name")
                    .font(.headline)
                Text(model.mode == .off ? "status.off" : "status.active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(minHeight: 36)
    }

    private var statusCard: some View {
        ViewThatFits(in: .horizontal) {
            horizontalStatus
            compactStatus
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            uiTestSessionMarker
        }
        .accessibilityIdentifier("maccoffee.status.card")
    }

    private var horizontalStatus: some View {
        HStack(spacing: 9) {
            Image(systemName: batterySymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.isBatteryBlocked ? .orange : .secondary)
                .frame(width: 18)

            Text(batteryText)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)

            if model.mode != .off {
                Divider()
                    .frame(height: 16)

                CountdownText(deadline: model.session?.expiresAt, localization: localization)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)
        }
    }

    private var compactStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: batterySymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.isBatteryBlocked ? .orange : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(batteryText)
                    .font(.callout.weight(.medium))
                if model.mode != .off {
                    CountdownText(deadline: model.session?.expiresAt, localization: localization)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var batteryText: String {
        guard model.batteryState.hasInternalBattery else {
            return localization.localized("battery.ac")
        }
        guard let percentage = model.batteryState.percentage else {
            return localization.localized("battery.unknown")
        }
        return localization.format("battery.percent", arguments: percentage)
    }

    private var batterySymbol: String {
        guard model.batteryState.hasInternalBattery else { return "powerplug.fill" }
        return model.batteryState.powerSource == .ac ? "battery.100.bolt" : "battery.50"
    }

    @ViewBuilder
    private var uiTestSessionMarker: some View {
#if DEBUG
        if CommandLine.arguments.contains("--ui-testing-window"), let session = model.session {
            Text(verbatim: "\(session.startedAt.timeIntervalSince1970)|\(session.expiresAt?.timeIntervalSince1970.description ?? "indefinite")")
                .font(.system(size: 1))
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("maccoffee.session.marker")
        }
#endif
    }
}

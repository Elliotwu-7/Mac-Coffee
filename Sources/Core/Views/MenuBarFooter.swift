import AppKit
import SwiftUI

struct MenuBarFooter: View {
    @Environment(\.openWindow) private var openWindow
    private let quitCoordinator: QuitConfirmationCoordinator
    private let panelWidth: CGFloat?

    init(
        quitCoordinator: QuitConfirmationCoordinator,
        panelWidth: CGFloat?
    ) {
        self.quitCoordinator = quitCoordinator
        self.panelWidth = panelWidth
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            actionToolbar
                .frame(minWidth: FooterLayoutMetrics.toolbarMinimumWidth)
            actionList
        }
        .frame(
            maxWidth: FooterLayoutMetrics.footerMaximumWidth(panelWidth: panelWidth),
            alignment: .leading
        )
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maccoffee.footer")
    }

    private var actionToolbar: some View {
        HStack(spacing: 2) {
            settingsAction(.toolbarLabeled)
                .frame(maxWidth: .infinity)
            aboutAction(.toolbarLabeled)
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.secondary.opacity(0.24))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)
                .accessibilityHidden(true)

            quitAction(.toolbarIcon)
        }
        .padding(3)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maccoffee.footer.toolbar")
        .background(footerLayoutMarker("maccoffee.footer.toolbar.marker"))
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            settingsAction(.list)
            listDivider
            aboutAction(.list)
            listDivider
            quitAction(.list)
        }
        .padding(3)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maccoffee.footer.list")
        .background(footerLayoutMarker("maccoffee.footer.list.marker"))
    }

    private var listDivider: some View {
        Divider()
            .padding(.leading, 34)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func settingsAction(_ presentation: FooterActionPresentation) -> some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                FooterActionLabel(
                    title: "action.settings",
                    symbol: "gearshape",
                    presentation: presentation
                )
            }
            .buttonStyle(FooterActionButtonStyle())
            .accessibilityLabel(Text("action.settings"))
            .accessibilityIdentifier("maccoffee.action.settings")
            .help(Text("action.settings"))
        } else {
            Button(action: openLegacySettings) {
                FooterActionLabel(
                    title: "action.settings",
                    symbol: "gearshape",
                    presentation: presentation
                )
            }
            .buttonStyle(FooterActionButtonStyle())
            .accessibilityLabel(Text("action.settings"))
            .accessibilityIdentifier("maccoffee.action.settings")
            .help(Text("action.settings"))
        }
    }

    private func aboutAction(_ presentation: FooterActionPresentation) -> some View {
        Button {
            openWindow(id: "maccoffee.about")
        } label: {
            FooterActionLabel(
                title: "action.about",
                symbol: "info.circle",
                presentation: presentation
            )
        }
        .buttonStyle(FooterActionButtonStyle())
        .accessibilityLabel(Text("action.about"))
        .accessibilityIdentifier("maccoffee.action.about")
        .help(Text("action.about"))
    }

    private func quitAction(_ presentation: FooterActionPresentation) -> some View {
        Button {
            quitCoordinator.requestQuit()
        } label: {
            FooterActionLabel(
                title: "action.quit",
                symbol: "power",
                presentation: presentation,
                isDestructive: true
            )
        }
        .buttonStyle(FooterActionButtonStyle())
        .accessibilityLabel(Text("action.quit"))
        .accessibilityIdentifier("maccoffee.action.quit")
        .help(Text("action.quit"))
    }

    /// Gives UI automation a frame-bearing layout node without changing the
    /// visual size or hit-testing of the footer itself.
    @ViewBuilder
    private func footerLayoutMarker(_ identifier: String) -> some View {
#if DEBUG
        Text(verbatim: identifier)
            .font(.system(size: 1))
            .lineLimit(1)
            .fixedSize()
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier(identifier)
#endif
    }

    private func openLegacySettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

enum FooterLayoutMetrics {
    static let toolbarMinimumWidth: CGFloat = 340
    static let compactActionWidth: CGFloat = 36
    static let minimumActionHeight: CGFloat = 36

    static func panelMaximumWidth(panelWidth: CGFloat?) -> CGFloat {
        panelWidth ?? 420
    }

    /// `nil` preserves the parent proposal so ViewThatFits can select the list
    /// candidate when a production menu-bar panel is constrained by the screen.
    static func footerMaximumWidth(panelWidth: CGFloat?) -> CGFloat? {
        panelWidth
    }
}

private enum FooterActionPresentation {
    case toolbarLabeled
    case toolbarIcon
    case list

    var showsTitle: Bool {
        self != .toolbarIcon
    }

    var expands: Bool {
        self != .toolbarIcon
    }
}

private struct FooterActionLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    let presentation: FooterActionPresentation
    var isDestructive = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 16)

            if presentation.showsTitle {
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: presentation == .toolbarLabeled, vertical: false)
            }

            if presentation == .list {
                Spacer(minLength: 0)
            }
        }
        .frame(
            maxWidth: presentation.expands ? .infinity : nil,
            minHeight: FooterLayoutMetrics.minimumActionHeight
        )
        .frame(width: presentation == .toolbarIcon ? FooterLayoutMetrics.compactActionWidth : nil)
        .padding(.horizontal, presentation == .toolbarIcon ? 0 : 9)
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
        .background(
            Color.secondary.opacity(isHovering ? 0.13 : 0),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

private struct FooterActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

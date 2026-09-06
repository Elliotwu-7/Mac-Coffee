import AppKit
import MacCoffeeCore
import SwiftUI

struct MCPSettingsView: View {
  @ObservedObject private var environment: DirectMCPEnvironment
  @ObservedObject private var settings: MCPSettings
  @ObservedObject private var pairing: MCPPairingCoordinator
  @ObservedObject private var activityStore: MCPActivityStore
  @StateObject private var viewModel: MCPSettingsViewModel
  @State private var isPresentingSetup = false

  init(environment: DirectMCPEnvironment) {
    self.environment = environment
    _settings = ObservedObject(wrappedValue: environment.settings)
    _pairing = ObservedObject(wrappedValue: environment.pairingCoordinator)
    _activityStore = ObservedObject(wrappedValue: environment.controlService.activityStore)
    _viewModel = StateObject(
      wrappedValue: MCPSettingsViewModel(environment: environment)
    )
  }

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        integrationCard

        if settings.isEnabled {
          ForEach(pairing.pendingRequests) { request in
            MCPPairingView(
              request: request,
              approve: { viewModel.approve(request) },
              reject: { viewModel.reject(request) }
            )
          }

          trustedClientsCard
          MCPActivityView(store: activityStore)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("mcp.settings.section")
      .onChange(of: pairing.pendingRequests) { _ in
        viewModel.refreshTrustedClients()
      }
      .onChange(of: activityStore.entries) { _ in
        viewModel.refreshTrustedClients()
      }
      .alert(item: $viewModel.notice) { notice in
        Alert(
          title: Text("mcp.notice.title"),
          message: Text(LocalizedStringKey(notice.localizationKey)),
          dismissButton: .default(Text("common.ok"))
        )
      }
    } header: {
      Text("mcp.settings.title")
    }
  }

  private var integrationCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(
          "mcp.settings.enabled",
          isOn: Binding(
            get: { settings.isEnabled },
            set: {
              environment.setEnabled($0)
              DispatchQueue.main.async {
                NSAccessibility.post(
                  element: NSApplication.shared,
                  notification: .layoutChanged
                )
              }
            }
          )
        )
        .toggleStyle(.switch)
        .accessibilityIdentifier("mcp.settings.enabled")

        Divider()

        LabeledContent("mcp.settings.status.label") {
          Label(statusKey, systemImage: statusSymbol)
            .foregroundStyle(statusColor)
            .accessibilityIdentifier("mcp.settings.status")
        }

        Text("mcp.settings.securityHelp")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button {
          isPresentingSetup = true
        } label: {
          Label("mcp.settings.setup", systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("mcp.settings.setup")

        Link(
          "mcp.settings.securityLink",
          destination: URL(
            string: "https://github.com/rekurt/Mac-Coffee/blob/main/docs/SECURITY.md"
          )!
        )
        .font(.caption)
        .accessibilityIdentifier("mcp.settings.securityLink")
      }
      .padding(4)
      .sheet(isPresented: $isPresentingSetup) {
        MCPSetupWizard(helperURL: mcpHelperURL)
      }
    } label: {
      Label("mcp.settings.integration", systemImage: "point.3.connected.trianglepath.dotted")
    }
  }

  private var mcpHelperURL: URL {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("MacCoffeeMCP", isDirectory: false)
  }

  private var trustedClientsCard: some View {
    GroupBox {
      if viewModel.trustedClients.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "person.crop.circle.badge.questionmark")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("mcp.clients.empty.title")
            .font(.headline)
          Text("mcp.clients.empty.help")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
      } else {
        VStack(spacing: 0) {
          ForEach(viewModel.trustedClients) { client in
            MCPTrustedClientRow(
              client: client,
              revoke: { viewModel.revoke(client) },
              forget: { viewModel.forget(client) }
            )
            if client.id != viewModel.trustedClients.last?.id {
              Divider()
            }
          }
        }
      }
    } label: {
      Label("mcp.clients.title", systemImage: "person.2.badge.key.fill")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mcp.clients")
  }

  private var statusKey: LocalizedStringKey {
    switch environment.connectionState {
    case .disabled: "mcp.status.disabled"
    case .starting: "mcp.status.starting"
    case .ready: "mcp.status.ready"
    case .failed: "mcp.status.failed"
    }
  }

  private var statusSymbol: String {
    switch environment.connectionState {
    case .disabled: "circle"
    case .starting: "ellipsis.circle"
    case .ready: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    switch environment.connectionState {
    case .disabled: .secondary
    case .starting: .blue
    case .ready: .green
    case .failed: .red
    }
  }

}

private struct MCPTrustedClientRow: View {
  enum Confirmation: String, Identifiable {
    case revoke
    case forget

    var id: String { rawValue }
  }

  let client: MCPTrustedClient
  let revoke: () -> Void
  let forget: () -> Void

  @State private var confirmation: Confirmation?

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 12) {
        clientDescription
        Spacer(minLength: 12)
        actionButtons(identifierSuffix: "")
      }
      VStack(alignment: .leading, spacing: 10) {
        clientDescription
        actionButtons(identifierSuffix: ".compact")
      }
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mcp.client.\(client.identifier)")
    .confirmationDialog(
      confirmationTitle,
      isPresented: Binding(
        get: { confirmation != nil },
        set: { if !$0 { confirmation = nil } }
      ),
      titleVisibility: .visible
    ) {
      if confirmation == .revoke {
        Button("mcp.client.revoke", role: .destructive) {
          confirmation = nil
          revoke()
        }
        .accessibilityIdentifier("mcp.client.confirm.revoke.\(client.identifier)")
      } else if confirmation == .forget {
        Button("mcp.client.forget", role: .destructive) {
          confirmation = nil
          forget()
        }
        .accessibilityIdentifier("mcp.client.confirm.forget.\(client.identifier)")
      }
      Button("common.cancel", role: .cancel) { confirmation = nil }
    } message: {
      Text(confirmationMessageKey)
    }
  }

  private var clientDescription: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 7) {
        Text(verbatim: client.displayName)
          .font(.headline)
        verificationBadge
        if client.isRevoked {
          Text("mcp.client.revoked")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.red.opacity(0.12), in: Capsule())
        }
      }
      if let lastSeenAt = client.lastSeenAt {
        HStack(spacing: 3) {
          Text("mcp.client.lastSeen")
          Text(lastSeenAt, style: .relative)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("mcp.client.neverSeen")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var verificationBadge: some View {
    Label {
      Text(
        client.codeIdentity.isSigned
          ? "mcp.verification.verified"
          : "mcp.verification.unverified"
      )
    } icon: {
      Image(
        systemName: client.codeIdentity.isSigned
          ? "checkmark.shield.fill"
          : "exclamationmark.shield.fill"
      )
    }
    .font(.caption)
    .foregroundStyle(client.codeIdentity.isSigned ? .green : .orange)
    .labelStyle(.iconOnly)
    .accessibilityIdentifier("mcp.client.verification.\(client.identifier)")
  }

  @ViewBuilder
  private func actionButtons(identifierSuffix: String) -> some View {
    HStack(spacing: 8) {
      if !client.isRevoked {
        Button("mcp.client.revoke", role: .destructive) {
          confirmation = .revoke
        }
        .accessibilityIdentifier(
          "mcp.client.revoke.\(client.identifier)\(identifierSuffix)"
        )
      }
      Button("mcp.client.forget", role: .destructive) {
        confirmation = .forget
      }
      .accessibilityIdentifier(
        "mcp.client.forget.\(client.identifier)\(identifierSuffix)"
      )
    }
  }

  private var confirmationTitle: LocalizedStringKey {
    confirmation == .forget
      ? "mcp.client.forget.confirm.title"
      : "mcp.client.revoke.confirm.title"
  }

  private var confirmationMessageKey: LocalizedStringKey {
    confirmation == .forget
      ? "mcp.client.forget.confirm.message"
      : "mcp.client.revoke.confirm.message"
  }
}

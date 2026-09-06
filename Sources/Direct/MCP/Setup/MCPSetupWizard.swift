import AppKit
import SwiftUI

struct MCPSetupWizard: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: MCPSetupWizardViewModel
  @State private var isConfirmingInstallation = false

  init(helperURL: URL) {
    _viewModel = StateObject(
      wrappedValue: MCPSetupWizardViewModel(helperURL: helperURL)
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          clientPicker
          securityNotice
          planContent
        }
        .padding(24)
      }
      Divider()
      footer
    }
    .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 620)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mcp.setup.wizard")
    .confirmationDialog(
      "mcp.setup.confirm.title",
      isPresented: $isConfirmingInstallation,
      titleVisibility: .visible
    ) {
      Button("mcp.setup.confirm.install") {
        viewModel.installConfirmed()
      }
      .accessibilityIdentifier("mcp.setup.confirm.install")
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text("mcp.setup.confirm.message")
    }
    .alert(item: $viewModel.notice) { notice in
      Alert(
        title: Text("mcp.setup.notice.title"),
        message: Text(LocalizedStringKey(notice.localizationKey)),
        dismissButton: .default(Text("common.ok"))
      )
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 38, height: 38)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 4) {
        Text("mcp.setup.title")
          .font(.title2.bold())
        Text("mcp.setup.subtitle")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 20)
    }
    .padding(24)
  }

  private var clientPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("mcp.setup.client.title")
        .font(.headline)
      Picker(
        "mcp.setup.client.title",
        selection: Binding(
          get: { viewModel.selectedClient },
          set: { viewModel.select($0) }
        )
      ) {
        ForEach(MCPClientKind.allCases) { client in
          Label(LocalizedStringKey(client.localizationKey), systemImage: client.systemImage)
            .tag(client)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .accessibilityIdentifier("mcp.setup.client")
    }
  }

  private var securityNotice: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "lock.shield.fill")
        .foregroundStyle(.green)
      Text("mcp.setup.securityHelp")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  @ViewBuilder
  private var planContent: some View {
    if let plan = viewModel.plan {
      VStack(alignment: .leading, spacing: 14) {
        if let configurationURL = plan.configurationURL {
          detailRow(
            title: "mcp.setup.configurationPath",
            value: configurationURL.path,
            copyValue: configurationURL.path,
            identifier: "mcp.setup.path"
          )
        }
        detailRow(
          title: "mcp.setup.helperPath",
          value: plan.helperURL.path,
          copyValue: plan.helperURL.path,
          identifier: "mcp.setup.helper"
        )

        switch plan.disposition {
        case .installable:
          installablePlan(plan)
        case .unchanged:
          statusCard(
            symbol: "checkmark.circle.fill",
            color: .green,
            title: "mcp.setup.unchanged.title",
            message: "mcp.setup.unchanged.message"
          )
        case .manual:
          manualPlan(plan)
        }

        if let result = viewModel.installationResult {
          installedCard(result)
        }
      }
    } else {
      statusCard(
        symbol: "exclamationmark.triangle.fill",
        color: .orange,
        title: "mcp.setup.unavailable.title",
        message: "mcp.setup.unavailable.message"
      )
    }
  }

  private func installablePlan(_ plan: ConfigurationChangePlan) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("mcp.setup.diff.title", systemImage: "doc.text.magnifyingglass")
        .font(.headline)
      Text("mcp.setup.diff.help")
        .font(.caption)
        .foregroundStyle(.secondary)
      codeBlock(plan.proposedDiff, identifier: "mcp.setup.diff")
    }
  }

  private func manualPlan(_ plan: ConfigurationChangePlan) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      statusCard(
        symbol: viewModel.selectedClient == .genericStdio
          ? "terminal.fill"
          : "exclamationmark.triangle.fill",
        color: viewModel.selectedClient == .genericStdio ? .blue : .orange,
        title: viewModel.selectedClient == .genericStdio
          ? "mcp.setup.manual.generic.title"
          : "mcp.setup.manual.conflict.title",
        message: viewModel.selectedClient == .genericStdio
          ? "mcp.setup.manual.generic.message"
          : "mcp.setup.manual.conflict.message"
      )
      codeBlock(plan.manualInstructions, identifier: "mcp.setup.manual")
      Button {
        copy(plan.manualInstructions)
      } label: {
        Label("mcp.setup.copy", systemImage: "doc.on.doc")
      }
      .accessibilityIdentifier("mcp.setup.copy.manual")
    }
  }

  private func installedCard(_ result: MCPConfigurationInstallationResult) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("mcp.setup.installed.title", systemImage: "checkmark.seal.fill")
        .font(.headline)
        .foregroundStyle(.green)
      Text("mcp.setup.installed.message")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let backupURL = result.backupURL {
        Text(backupURL.path)
          .font(.caption.monospaced())
          .textSelection(.enabled)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityIdentifier("mcp.setup.installed")
  }

  private func detailRow(
    title: LocalizedStringKey,
    value: String,
    copyValue: String,
    identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Text(verbatim: value)
          .font(.caption.monospaced())
          .lineLimit(2)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          copy(copyValue)
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("mcp.setup.copy"))
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityIdentifier(identifier)
  }

  private func codeBlock(_ value: String, identifier: String) -> some View {
    ScrollView([.horizontal, .vertical]) {
      Text(verbatim: value)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
    }
    .frame(minHeight: 110, maxHeight: 220)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(.separator.opacity(0.7))
    }
    .accessibilityIdentifier(identifier)
  }

  private func statusCard(
    symbol: String,
    color: Color,
    title: LocalizedStringKey,
    message: LocalizedStringKey
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(color)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  private var footer: some View {
    HStack(spacing: 10) {
      Text("mcp.setup.restartHelp")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 16)
      Button("common.close") { dismiss() }
        .keyboardShortcut(.cancelAction)
      if viewModel.plan?.disposition == .installable {
        Button("mcp.setup.install") {
          isConfirmingInstallation = true
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("mcp.setup.install")
      }
    }
    .padding(20)
  }

  private func copy(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
  }
}

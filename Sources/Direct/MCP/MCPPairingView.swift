import MacCoffeeCore
import SwiftUI

struct MCPPairingView: View {
  let request: MCPPairingRequest
  let approve: () -> Void
  let reject: () -> Void

  @State private var isApprovalConfirmationPresented = false

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(systemName: verificationSymbol)
            .foregroundStyle(verificationColor)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: request.presentation.displayName)
              .font(.headline)
            Text(reasonKey)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          verificationBadge
        }

        identitySummary

        if request.requiresUnverifiedApprovalWarning {
          Label("mcp.pairing.unverifiedWarning", systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("mcp.pairing.warning")
        }

        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            Spacer()
            actionButtons(identifierSuffix: "")
          }
          VStack(alignment: .trailing, spacing: 8) {
            actionButtons(identifierSuffix: ".compact")
          }
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .padding(4)
    } label: {
      Label("mcp.pairing.request", systemImage: "person.badge.key.fill")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mcp.pairing.request.\(request.presentation.clientIdentifier)")
    .confirmationDialog(
      "mcp.pairing.confirm.title",
      isPresented: $isApprovalConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("mcp.pairing.approve") { approve() }
        .accessibilityIdentifier(
          "mcp.pairing.confirm.approve.\(request.presentation.clientIdentifier)"
        )
      Button("common.cancel", role: .cancel) {}
    } message: {
      Text(confirmationMessageKey)
    }
  }

  @ViewBuilder
  private func actionButtons(identifierSuffix: String) -> some View {
    Button("mcp.pairing.reject", role: .destructive, action: reject)
      .accessibilityIdentifier(
        "mcp.pairing.reject.\(request.presentation.clientIdentifier)\(identifierSuffix)"
      )
    Button("mcp.pairing.approve") {
      isApprovalConfirmationPresented = true
    }
    .buttonStyle(.borderedProminent)
    .accessibilityIdentifier(
      "mcp.pairing.approve.\(request.presentation.clientIdentifier)\(identifierSuffix)"
    )
  }

  @ViewBuilder
  private var identitySummary: some View {
    if request.presentation.parentIdentity.isSigned {
      LabeledContent("mcp.pairing.identity") {
        VStack(alignment: .trailing, spacing: 2) {
          Text(verbatim: signedIdentityName)
          if let teamIdentifier = request.presentation.parentIdentity.teamIdentifier {
            Text(verbatim: teamIdentifier)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
        }
      }
    } else {
      LabeledContent("mcp.pairing.identity") {
        Text("mcp.verification.unverified")
          .foregroundStyle(.orange)
      }
    }
  }

  private var verificationBadge: some View {
    Label(verificationKey, systemImage: verificationSymbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(verificationColor)
      .labelStyle(.titleOnly)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(verificationColor.opacity(0.12), in: Capsule())
  }

  private var signedIdentityName: String {
    request.presentation.parentIdentity.signingIdentifier
      ?? request.presentation.parentIdentity.bundleIdentifier
      ?? request.presentation.displayName
  }

  private var reasonKey: LocalizedStringKey {
    switch request.reason {
    case .firstPairing:
      "mcp.pairing.reason.first"
    case .identityChanged:
      "mcp.pairing.reason.changed"
    }
  }

  private var confirmationMessageKey: LocalizedStringKey {
    if request.requiresUnverifiedApprovalWarning {
      return "mcp.pairing.confirm.unverified"
    }
    if request.reason == .identityChanged {
      return "mcp.pairing.confirm.changed"
    }
    return "mcp.pairing.confirm.verified"
  }

  private var verificationKey: LocalizedStringKey {
    request.presentation.parentIdentity.isSigned
      ? "mcp.verification.verified"
      : "mcp.verification.unverified"
  }

  private var verificationSymbol: String {
    request.presentation.parentIdentity.isSigned
      ? "checkmark.shield.fill"
      : "exclamationmark.shield.fill"
  }

  private var verificationColor: Color {
    request.presentation.parentIdentity.isSigned ? .green : .orange
  }
}

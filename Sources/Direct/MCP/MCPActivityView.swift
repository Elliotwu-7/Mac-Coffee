import MacCoffeeCore
import SwiftUI

struct MCPActivityView: View {
  @ObservedObject private var store: MCPActivityStore
  @State private var isExpanded = false

  init(store: MCPActivityStore) {
    self.store = store
  }

  var body: some View {
    GroupBox {
      DisclosureGroup(isExpanded: $isExpanded) {
        if store.entries.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text("mcp.activity.empty.title")
              .font(.headline)
            Text("mcp.activity.empty.help")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, minHeight: 100)
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(Array(store.entries.suffix(50).reversed())) { entry in
                activityRow(entry)
                if entry.id != store.entries.suffix(50).first?.id {
                  Divider()
                }
              }
            }
          }
          .frame(maxHeight: 240)
        }
      } label: {
        HStack {
          Label("mcp.activity.title", systemImage: "clock.arrow.circlepath")
          Spacer()
          Text(verbatim: "\(store.entries.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("mcp.activity.count")
        }
      }
      .accessibilityIdentifier("mcp.activity.disclosure")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mcp.activity")
  }

  private func activityRow(_ entry: MCPActivityEvent) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        outcomeIcon(entry)
        activityDescription(entry)
        Spacer(minLength: 8)
        activityMetadata(entry)
      }
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          outcomeIcon(entry)
          activityDescription(entry)
        }
        activityMetadata(entry)
      }
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mcp.activity.entry.\(entry.sequence)")
  }

  private func activityDescription(_ entry: MCPActivityEvent) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(actionKey(for: entry.action))
        .font(.callout.weight(.medium))
      Text(verbatim: entry.client.displayName)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func activityMetadata(_ entry: MCPActivityEvent) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      if let date = parsedDate(entry.timestamp) {
        Text(date, format: .dateTime.hour().minute().second())
          .monospacedDigit()
      } else {
        Text(verbatim: entry.timestamp)
      }
      HStack(spacing: 4) {
        if entry.replayed {
          Text("mcp.activity.replayed")
        }
        if let code = entry.outcome.errorCode {
          Text(verbatim: code.rawValue)
        }
      }
      .font(.caption2.monospaced())
      .foregroundStyle(.secondary)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func outcomeIcon(_ entry: MCPActivityEvent) -> some View {
    Image(systemName: entry.outcome.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
      .foregroundStyle(entry.outcome.succeeded ? .green : .red)
      .accessibilityLabel(
        entry.outcome.succeeded
          ? "mcp.activity.outcome.success"
          : "mcp.activity.outcome.failure"
      )
  }

  private func parsedDate(_ value: String) -> Date? {
    try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
  }

  private func actionKey(for action: MCPActivityAction) -> LocalizedStringKey {
    switch action {
    case .getStatus: "mcp.activity.action.getStatus"
    case .setSession: "mcp.activity.action.setSession"
    case .stopSession: "mcp.activity.action.stopSession"
    case .setBatteryThreshold: "mcp.activity.action.setBatteryThreshold"
    case .setLaunchAtLogin: "mcp.activity.action.setLaunchAtLogin"
    case .setLanguage: "mcp.activity.action.setLanguage"
    case .readStatus: "mcp.activity.action.readStatus"
    case .readCapabilities: "mcp.activity.action.readCapabilities"
    case .readActivity: "mcp.activity.action.readActivity"
    case .subscribeStatus: "mcp.activity.action.subscribeStatus"
    case .unsubscribeStatus: "mcp.activity.action.unsubscribeStatus"
    }
  }
}

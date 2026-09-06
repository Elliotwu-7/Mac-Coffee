import Foundation

enum MCPClientKind: String, CaseIterable, Identifiable, Sendable {
  case codex
  case claudeDesktop
  case genericStdio

  var id: String { rawValue }

  var localizationKey: String {
    switch self {
    case .codex: "mcp.setup.client.codex"
    case .claudeDesktop: "mcp.setup.client.claude"
    case .genericStdio: "mcp.setup.client.generic"
    }
  }

  var systemImage: String {
    switch self {
    case .codex: "terminal"
    case .claudeDesktop: "bubble.left.and.bubble.right"
    case .genericStdio: "chevron.left.forwardslash.chevron.right"
    }
  }
}

import Foundation

@MainActor
final class MCPSetupWizardViewModel: ObservableObject {
  enum Notice: String, Identifiable {
    case planningFailed
    case installationFailed

    var id: String { rawValue }

    var localizationKey: String {
      switch self {
      case .planningFailed: "mcp.setup.notice.planningFailed"
      case .installationFailed: "mcp.setup.notice.installationFailed"
      }
    }
  }

  @Published private(set) var selectedClient: MCPClientKind = .codex
  @Published private(set) var plan: ConfigurationChangePlan?
  @Published private(set) var installationResult: MCPConfigurationInstallationResult?
  @Published var notice: Notice?

  let helperURL: URL

  private let codexPlanner: CodexConfigurationPlanner
  private let claudePlanner: ClaudeConfigurationPlanner
  private let installer: AtomicConfigurationInstaller

  init(
    helperURL: URL,
    codexPlanner: CodexConfigurationPlanner = CodexConfigurationPlanner(),
    claudePlanner: ClaudeConfigurationPlanner = ClaudeConfigurationPlanner(),
    installer: AtomicConfigurationInstaller = AtomicConfigurationInstaller()
  ) {
    self.helperURL = helperURL.standardizedFileURL
    self.codexPlanner = codexPlanner
    self.claudePlanner = claudePlanner
    self.installer = installer
    reloadPlan()
  }

  func select(_ client: MCPClientKind) {
    guard client != selectedClient else { return }
    selectedClient = client
    installationResult = nil
    reloadPlan()
  }

  func reloadPlan() {
    do {
      switch selectedClient {
      case .codex:
        plan = try codexPlanner.plan(helperURL: helperURL)
      case .claudeDesktop:
        plan = try claudePlanner.plan(helperURL: helperURL)
      case .genericStdio:
        plan = .generic(helperURL: helperURL)
      }
    } catch {
      plan = nil
      notice = .planningFailed
    }
  }

  func installConfirmed() {
    guard let plan, plan.disposition == .installable else {
      notice = .installationFailed
      return
    }
    do {
      installationResult = try installer.install(
        plan: plan,
        confirmedHash: plan.confirmationHash
      )
      reloadPlan()
    } catch {
      notice = .installationFailed
      reloadPlan()
    }
  }
}

import CryptoKit
import Foundation

enum ConfigurationPlanDisposition: String, Equatable, Sendable {
  case installable
  case unchanged
  case manual
}

enum ConfigurationValidation: String, Equatable, Sendable {
  case valid
  case invalid
}

struct ConfigurationChangePlan: Identifiable, Equatable, Sendable {
  let clientKind: MCPClientKind
  let configurationURL: URL?
  let helperURL: URL
  let targetExisted: Bool
  let before: String
  let after: String?
  let proposedDiff: String
  let disposition: ConfigurationPlanDisposition
  let validation: ConfigurationValidation
  let manualInstructions: String
  let confirmationHash: String

  var id: String { confirmationHash }

  init(
    clientKind: MCPClientKind,
    configurationURL: URL?,
    helperURL: URL,
    targetExisted: Bool,
    before: String,
    after: String?,
    proposedDiff: String,
    disposition: ConfigurationPlanDisposition,
    validation: ConfigurationValidation,
    manualInstructions: String
  ) {
    self.clientKind = clientKind
    self.configurationURL = configurationURL
    self.helperURL = helperURL
    self.targetExisted = targetExisted
    self.before = before
    self.after = after
    self.proposedDiff = proposedDiff
    self.disposition = disposition
    self.validation = validation
    self.manualInstructions = manualInstructions
    confirmationHash = Self.hash(
      clientKind: clientKind,
      configurationURL: configurationURL,
      helperURL: helperURL,
      targetExisted: targetExisted,
      before: before,
      after: after,
      disposition: disposition,
      validation: validation
    )
  }

  static func generic(helperURL: URL) -> ConfigurationChangePlan {
    ConfigurationChangePlan(
      clientKind: .genericStdio,
      configurationURL: nil,
      helperURL: helperURL,
      targetExisted: false,
      before: "",
      after: nil,
      proposedDiff: "",
      disposition: .manual,
      validation: .valid,
      manualInstructions: helperURL.standardizedFileURL.path
    )
  }

  private static func hash(
    clientKind: MCPClientKind,
    configurationURL: URL?,
    helperURL: URL,
    targetExisted: Bool,
    before: String,
    after: String?,
    disposition: ConfigurationPlanDisposition,
    validation: ConfigurationValidation
  ) -> String {
    let components = [
      "maccoffee-configuration-plan-v1",
      clientKind.rawValue,
      configurationURL?.standardizedFileURL.path ?? "",
      helperURL.standardizedFileURL.path,
      targetExisted ? "1" : "0",
      before,
      after ?? "",
      disposition.rawValue,
      validation.rawValue,
    ]
    let digest = SHA256.hash(data: Data(components.joined(separator: "\u{0}").utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

enum MCPConfigurationPlanning {
  static func readExistingContents(at url: URL, provided: String?) throws -> (Bool, String) {
    if let provided {
      return (FileManager.default.fileExists(atPath: url.path), provided)
    }
    guard FileManager.default.fileExists(atPath: url.path) else { return (false, "") }
    return (true, try String(contentsOf: url, encoding: .utf8))
  }

  static func unifiedDiff(before: String, after: String, path: String) -> String {
    guard before != after else { return "" }
    let oldLines = splitLines(before)
    let newLines = splitLines(after)
    var lines = [
      "--- \(path)",
      "+++ \(path)",
      "@@ -\(oldLines.isEmpty ? "0,0" : "1,\(oldLines.count)") +\(newLines.isEmpty ? "0,0" : "1,\(newLines.count)") @@",
    ]
    lines.append(contentsOf: oldLines.map { "-\($0)" })
    lines.append(contentsOf: newLines.map { "+\($0)" })
    return lines.joined(separator: "\n") + "\n"
  }

  private static func splitLines(_ value: String) -> [String] {
    guard !value.isEmpty else { return [] }
    var lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if value.hasSuffix("\n") { lines.removeLast() }
    return lines
  }
}

enum ConfigurationPlanValidator {
  static func validate(contents: String, plan: ConfigurationChangePlan) -> Bool {
    switch plan.clientKind {
    case .codex:
      CodexConfigurationPlanner.validate(contents: contents, helperURL: plan.helperURL)
    case .claudeDesktop:
      ClaudeConfigurationPlanner.validate(contents: contents, helperURL: plan.helperURL)
    case .genericStdio:
      false
    }
  }
}

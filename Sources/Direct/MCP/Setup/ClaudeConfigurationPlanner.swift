import Foundation

struct ClaudeConfigurationPlanner {
  static let serverKey = "mac-coffee"

  func plan(
    configurationURL: URL = defaultConfigurationURL,
    helperURL: URL,
    existingContents: String? = nil
  ) throws -> ConfigurationChangePlan {
    let (targetExisted, before) = try MCPConfigurationPlanning.readExistingContents(
      at: configurationURL,
      provided: existingContents
    )
    let instructions = Self.manualInstructions(helperURL: helperURL)
    guard var root = Self.parseRoot(before), !Self.hasDuplicateJSONKeys(before) else {
      return manualPlan(
        configurationURL: configurationURL,
        helperURL: helperURL,
        targetExisted: targetExisted,
        before: before,
        instructions: instructions
      )
    }

    var servers = root["mcpServers"] as? [String: Any] ?? [:]
    if let existingValue = servers[Self.serverKey] {
      guard let existing = existingValue as? [String: Any],
        Self.matches(server: existing, helperURL: helperURL)
      else {
        return manualPlan(
          configurationURL: configurationURL,
          helperURL: helperURL,
          targetExisted: targetExisted,
          before: before,
          instructions: instructions
        )
      }
      return ConfigurationChangePlan(
        clientKind: .claudeDesktop,
        configurationURL: configurationURL,
        helperURL: helperURL,
        targetExisted: targetExisted,
        before: before,
        after: before,
        proposedDiff: "",
        disposition: .unchanged,
        validation: .valid,
        manualInstructions: instructions
      )
    }

    servers[Self.serverKey] = [
      "command": helperURL.standardizedFileURL.path,
      "args": [String](),
    ]
    root["mcpServers"] = servers
    let data = try JSONSerialization.data(
      withJSONObject: root,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    let after = String(decoding: data, as: UTF8.self) + "\n"
    let validation: ConfigurationValidation = Self.validate(contents: after, helperURL: helperURL)
      ? .valid
      : .invalid
    return ConfigurationChangePlan(
      clientKind: .claudeDesktop,
      configurationURL: configurationURL,
      helperURL: helperURL,
      targetExisted: targetExisted,
      before: before,
      after: after,
      proposedDiff: MCPConfigurationPlanning.unifiedDiff(
        before: before,
        after: after,
        path: configurationURL.path
      ),
      disposition: validation == .valid ? .installable : .manual,
      validation: validation,
      manualInstructions: instructions
    )
  }

  static func validate(contents: String, helperURL: URL) -> Bool {
    guard let root = parseRoot(contents),
      !hasDuplicateJSONKeys(contents),
      let servers = root["mcpServers"] as? [String: Any],
      let server = servers[serverKey] as? [String: Any]
    else { return false }
    return matches(server: server, helperURL: helperURL)
  }

  private static var defaultConfigurationURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
      .appendingPathComponent("claude_desktop_config.json")
  }

  private static func parseRoot(_ contents: String) -> [String: Any]? {
    if contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
    guard let data = contents.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    if let value = root["mcpServers"], !(value is [String: Any]) { return nil }
    return root
  }

  private static func hasDuplicateJSONKeys(_ contents: String) -> Bool {
    if contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
    var detector = JSONDuplicateKeyDetector(contents: contents)
    return (try? detector.hasDuplicateKeys()) ?? true
  }

  private static func matches(server: [String: Any], helperURL: URL) -> Bool {
    guard server["command"] as? String == helperURL.standardizedFileURL.path else { return false }
    guard let value = server["args"] else { return true }
    guard let args = value as? [Any] else { return false }
    return args.isEmpty
  }

  private static func manualInstructions(helperURL: URL) -> String {
    let object: [String: Any] = [
      "mcpServers": [
        serverKey: [
          "command": helperURL.standardizedFileURL.path,
          "args": [String](),
        ]
      ]
    ]
    guard let data = try? JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) else { return helperURL.standardizedFileURL.path }
    return String(decoding: data, as: UTF8.self)
  }

  private func manualPlan(
    configurationURL: URL,
    helperURL: URL,
    targetExisted: Bool,
    before: String,
    instructions: String
  ) -> ConfigurationChangePlan {
    ConfigurationChangePlan(
      clientKind: .claudeDesktop,
      configurationURL: configurationURL,
      helperURL: helperURL,
      targetExisted: targetExisted,
      before: before,
      after: nil,
      proposedDiff: "",
      disposition: .manual,
      validation: .invalid,
      manualInstructions: instructions
    )
  }
}

private struct JSONDuplicateKeyDetector {
  private enum ParseError: Error {
    case invalidJSON
  }

  private let bytes: [UInt8]
  private var index = 0

  init(contents: String) {
    bytes = Array(contents.utf8)
  }

  mutating func hasDuplicateKeys() throws -> Bool {
    skipWhitespace()
    let duplicate = try parseValue()
    if duplicate { return true }
    skipWhitespace()
    guard index == bytes.count else { throw ParseError.invalidJSON }
    return false
  }

  private mutating func parseValue() throws -> Bool {
    skipWhitespace()
    guard index < bytes.count else { throw ParseError.invalidJSON }
    switch bytes[index] {
    case 0x7B:
      return try parseObject()
    case 0x5B:
      return try parseArray()
    case 0x22:
      _ = try parseString()
      return false
    default:
      let start = index
      while index < bytes.count, !isValueDelimiter(bytes[index]) {
        index += 1
      }
      guard index > start else { throw ParseError.invalidJSON }
      return false
    }
  }

  private mutating func parseObject() throws -> Bool {
    index += 1
    skipWhitespace()
    if consume(0x7D) { return false }
    var keys: Set<String> = []

    while true {
      skipWhitespace()
      let key = try parseString()
      guard keys.insert(key).inserted else { return true }
      skipWhitespace()
      guard consume(0x3A) else { throw ParseError.invalidJSON }
      if try parseValue() { return true }
      skipWhitespace()
      if consume(0x7D) { return false }
      guard consume(0x2C) else { throw ParseError.invalidJSON }
    }
  }

  private mutating func parseArray() throws -> Bool {
    index += 1
    skipWhitespace()
    if consume(0x5D) { return false }

    while true {
      if try parseValue() { return true }
      skipWhitespace()
      if consume(0x5D) { return false }
      guard consume(0x2C) else { throw ParseError.invalidJSON }
    }
  }

  private mutating func parseString() throws -> String {
    guard index < bytes.count, bytes[index] == 0x22 else {
      throw ParseError.invalidJSON
    }
    let start = index
    index += 1
    while index < bytes.count {
      if bytes[index] == 0x5C {
        index += 2
        guard index <= bytes.count else { throw ParseError.invalidJSON }
      } else if bytes[index] == 0x22 {
        index += 1
        let literal = String(decoding: bytes[start..<index], as: UTF8.self)
        guard
          let data = "[\(literal)]".data(using: .utf8),
          let values = try? JSONSerialization.jsonObject(with: data) as? [String],
          let value = values.first
        else { throw ParseError.invalidJSON }
        return value
      } else {
        index += 1
      }
    }
    throw ParseError.invalidJSON
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
      index += 1
    }
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private func isValueDelimiter(_ byte: UInt8) -> Bool {
    byte == 0x2C || byte == 0x5D || byte == 0x7D
      || byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }
}

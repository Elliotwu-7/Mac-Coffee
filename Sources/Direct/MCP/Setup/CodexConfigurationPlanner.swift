import Foundation

struct CodexConfigurationPlanner {
  static let tableHeader = "[mcp_servers.mac_coffee]"

  func plan(
    configurationURL: URL = defaultConfigurationURL,
    helperURL: URL,
    existingContents: String? = nil
  ) throws -> ConfigurationChangePlan {
    let (targetExisted, before) = try MCPConfigurationPlanning.readExistingContents(
      at: configurationURL,
      provided: existingContents
    )
    let manualInstructions = Self.managedBlock(helperURL: helperURL)

    guard Self.isConservativelyValidTOML(before) else {
      return manualPlan(
        configurationURL: configurationURL,
        helperURL: helperURL,
        targetExisted: targetExisted,
        before: before,
        instructions: manualInstructions
      )
    }

    guard !Self.containsNonCanonicalMacCoffeeDeclaration(before) else {
      return manualPlan(
        configurationURL: configurationURL,
        helperURL: helperURL,
        targetExisted: targetExisted,
        before: before,
        instructions: manualInstructions
      )
    }

    let matchingHeaders = before.components(separatedBy: .newlines)
      .filter { $0.trimmingCharacters(in: .whitespaces) == Self.tableHeader }
    if !matchingHeaders.isEmpty {
      guard matchingHeaders.count == 1,
        Self.containsMatchingManagedEntry(contents: before, helperURL: helperURL)
      else {
        return manualPlan(
          configurationURL: configurationURL,
          helperURL: helperURL,
          targetExisted: targetExisted,
          before: before,
          instructions: manualInstructions
        )
      }
      return ConfigurationChangePlan(
        clientKind: .codex,
        configurationURL: configurationURL,
        helperURL: helperURL,
        targetExisted: targetExisted,
        before: before,
        after: before,
        proposedDiff: "",
        disposition: .unchanged,
        validation: .valid,
        manualInstructions: manualInstructions
      )
    }

    var after = before
    if !after.isEmpty {
      if !after.hasSuffix("\n") { after.append("\n") }
      after.append("\n")
    }
    after.append(manualInstructions)
    let validation: ConfigurationValidation = Self.validate(contents: after, helperURL: helperURL)
      ? .valid
      : .invalid
    return ConfigurationChangePlan(
      clientKind: .codex,
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
      manualInstructions: manualInstructions
    )
  }

  static func validate(contents: String, helperURL: URL) -> Bool {
    isConservativelyValidTOML(contents)
      && !containsNonCanonicalMacCoffeeDeclaration(contents)
      && containsMatchingManagedEntry(contents: contents, helperURL: helperURL)
  }

  private static var defaultConfigurationURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("config.toml")
  }

  private static func managedBlock(helperURL: URL) -> String {
    """
    \(tableHeader)
    command = "\(tomlEscaped(helperURL.standardizedFileURL.path))"
    """ + "\n"
  }

  private static func tomlEscaped(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  private static func containsMatchingManagedEntry(contents: String, helperURL: URL) -> Bool {
    let lines = contents.components(separatedBy: .newlines)
    guard let start = lines.firstIndex(where: {
      $0.trimmingCharacters(in: .whitespaces) == tableHeader
    }) else { return false }
    let end = lines[(start + 1)...].firstIndex(where: {
      $0.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }) ?? lines.endIndex
    let expected = "\"\(tomlEscaped(helperURL.standardizedFileURL.path))\""
    var commandValues: [String] = []
    for line in lines[(start + 1)..<end] {
      let content = removingComment(from: line).trimmingCharacters(in: .whitespaces)
      guard let separator = assignmentSeparator(in: content),
        let keyPath = parseKeyPath(String(content[..<separator]))
      else { continue }
      guard keyPath.first == "command" else { continue }
      guard keyPath == ["command"] else { return false }
      let value = content[content.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      commandValues.append(value)
    }
    return commandValues == [expected]
  }

  private static func containsNonCanonicalMacCoffeeDeclaration(_ contents: String) -> Bool {
    let managedPath = ["mcp_servers", "mac_coffee"]
    var tablePath: [String] = []
    for rawLine in contents.components(separatedBy: .newlines) {
      let line = removingComment(from: rawLine).trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }
      if line.hasPrefix("[") && line.hasSuffix("]") {
        let isArray = line.hasPrefix("[[") && line.hasSuffix("]]")
        let startOffset = isArray ? 2 : 1
        let endOffset = isArray ? 2 : 1
        let start = line.index(line.startIndex, offsetBy: startOffset)
        let end = line.index(line.endIndex, offsetBy: -endOffset)
        guard let parsed = parseKeyPath(String(line[start..<end])) else { return true }
        tablePath = parsed
        if tablePath.starts(with: managedPath), line != tableHeader {
          return true
        }
        continue
      }
      guard let separator = assignmentSeparator(in: line) else { continue }
      guard let keyPath = parseKeyPath(String(line[..<separator])) else { return true }
      let fullPath = tablePath + keyPath
      if fullPath == ["mcp_servers"]
        || (fullPath.starts(with: managedPath) && tablePath != managedPath)
      {
        return true
      }
    }
    return false
  }

  private static func assignmentSeparator(in line: String) -> String.Index? {
    var quote: Character?
    var escaped = false
    for index in line.indices {
      let character = line[index]
      if escaped {
        escaped = false
      } else if character == "\\" && quote == "\"" {
        escaped = true
      } else if character == "\"" || character == "'" {
        if quote == character {
          quote = nil
        } else if quote == nil {
          quote = character
        }
      } else if character == "=" && quote == nil {
        return index
      }
    }
    return nil
  }

  private static func parseKeyPath(_ value: String) -> [String]? {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    var escaped = false

    func appendCurrent() -> Bool {
      guard let key = parseKeySegment(current) else { return false }
      parts.append(key)
      current = ""
      return true
    }

    for character in value {
      if escaped {
        current.append(character)
        escaped = false
      } else if character == "\\" && quote == "\"" {
        current.append(character)
        escaped = true
      } else if character == "\"" || character == "'" {
        current.append(character)
        if quote == character {
          quote = nil
        } else if quote == nil {
          quote = character
        }
      } else if character == "." && quote == nil {
        guard appendCurrent() else { return nil }
      } else {
        current.append(character)
      }
    }
    guard quote == nil, !escaped, appendCurrent() else { return nil }
    return parts
  }

  private static func parseKeySegment(_ value: String) -> String? {
    let key = value.trimmingCharacters(in: .whitespaces)
    guard let first = key.first else { return nil }
    if first == "'" {
      guard key.count >= 2, key.last == "'" else { return nil }
      let inner = key.dropFirst().dropLast()
      guard !inner.contains("'") else { return nil }
      return String(inner)
    }
    if first == "\"" {
      guard key.count >= 2, key.last == "\"" else { return nil }
      return decodeBasicKey(String(key.dropFirst().dropLast()))
    }
    guard key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    return key
  }

  private static func decodeBasicKey(_ value: String) -> String? {
    var decoded = ""
    var index = value.startIndex
    while index < value.endIndex {
      let character = value[index]
      guard character == "\\" else {
        decoded.append(character)
        index = value.index(after: index)
        continue
      }

      let escapeIndex = value.index(after: index)
      guard escapeIndex < value.endIndex else { return nil }
      let escape = value[escapeIndex]
      switch escape {
      case "b": decoded.append("\u{8}")
      case "t": decoded.append("\t")
      case "n": decoded.append("\n")
      case "f": decoded.append("\u{c}")
      case "r": decoded.append("\r")
      case "\"": decoded.append("\"")
      case "\\": decoded.append("\\")
      case "u", "U":
        let digitCount = escape == "u" ? 4 : 8
        var cursor = value.index(after: escapeIndex)
        var digits = ""
        for _ in 0 ..< digitCount {
          guard cursor < value.endIndex, value[cursor].isHexDigit else { return nil }
          digits.append(value[cursor])
          cursor = value.index(after: cursor)
        }
        guard let scalarValue = UInt32(digits, radix: 16),
          let scalar = Unicode.Scalar(scalarValue)
        else { return nil }
        decoded.append(Character(String(scalar)))
        index = cursor
        continue
      default:
        return nil
      }
      index = value.index(after: escapeIndex)
    }
    return decoded
  }

  private static func isConservativelyValidTOML(_ contents: String) -> Bool {
    guard !contents.contains("\"\"\""), !contents.contains("'''") else { return false }
    var arrayDepth = 0
    var inlineTableDepth = 0
    var tablePath: [String] = []
    var tableInstanceIdentifier = ""
    var nextArrayTableInstance = 0
    var assignmentPaths = Set<String>()
    var assignmentsByScope: [String: [[String]]] = [:]
    var assignedValuePaths: [[String]] = []
    var declaredTables = Set<String>()
    var declaredTablePaths: [[String]] = []
    for rawLine in contents.components(separatedBy: .newlines) {
      let uncommentedLine = removingComment(from: rawLine)
      guard hasOnlyValidBasicStringEscapes(in: uncommentedLine) else { return false }
      let line = uncommentedLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }
      if line.hasPrefix("[") && arrayDepth == 0 && inlineTableDepth == 0 {
        let isArray = line.hasPrefix("[[") && line.hasSuffix("]]")
        let isTable = isArray || (!line.hasPrefix("[[") && line.hasSuffix("]"))
        guard isTable else { return false }
        let offset = isArray ? 2 : 1
        let start = line.index(line.startIndex, offsetBy: offset)
        let end = line.index(line.endIndex, offsetBy: -offset)
        guard let parsedTablePath = parseKeyPath(String(line[start..<end])) else { return false }
        guard !assignedValuePaths.contains(where: {
          parsedTablePath.starts(with: $0) || $0.starts(with: parsedTablePath)
        }) else {
          return false
        }
        tablePath = parsedTablePath
        if isArray {
          nextArrayTableInstance += 1
          tableInstanceIdentifier = "#array:\(nextArrayTableInstance)"
        } else {
          tableInstanceIdentifier = ""
          guard declaredTables.insert(pathIdentifier(tablePath)).inserted else { return false }
        }
        declaredTablePaths.append(tablePath)
        continue
      }
      if arrayDepth == 0 && inlineTableDepth == 0 {
        guard let separator = assignmentSeparator(in: line) else { return false }
        let key = String(line[..<separator])
        let value = String(line[line.index(after: separator)...])
          .trimmingCharacters(in: .whitespaces)
        guard let keyPath = parseKeyPath(key), isConservativelyValidValue(value) else {
          return false
        }
        let fullPath = tablePath + keyPath
        guard !declaredTablePaths.contains(where: { $0.starts(with: fullPath) }) else {
          return false
        }
        let scopeIdentifier = pathIdentifier(tablePath) + tableInstanceIdentifier
        let scopedAssignments = assignmentsByScope[scopeIdentifier, default: []]
        guard !scopedAssignments.contains(where: {
          fullPath.starts(with: $0) || $0.starts(with: fullPath)
        }) else { return false }
        assignmentsByScope[scopeIdentifier, default: []].append(fullPath)
        assignedValuePaths.append(fullPath)
        let assignmentIdentifier = pathIdentifier(fullPath) + tableInstanceIdentifier
        guard assignmentPaths.insert(assignmentIdentifier).inserted else { return false }
      }
      var quote: Character?
      var escaped = false
      for character in line {
        if escaped {
          escaped = false
        } else if character == "\\" && quote == "\"" {
          escaped = true
        } else if character == quote {
          quote = nil
        } else if quote == nil && (character == "\"" || character == "'") {
          quote = character
        } else if quote == nil && character == "[" {
          arrayDepth += 1
        } else if quote == nil && character == "]" {
          arrayDepth -= 1
          if arrayDepth < 0 { return false }
        } else if quote == nil && character == "{" {
          inlineTableDepth += 1
        } else if quote == nil && character == "}" {
          inlineTableDepth -= 1
          if inlineTableDepth < 0 { return false }
        }
      }
      if quote != nil || escaped || inlineTableDepth != 0 { return false }
    }
    return arrayDepth == 0 && inlineTableDepth == 0
  }

  private static func pathIdentifier(_ path: [String]) -> String {
    path.map { "\($0.utf8.count):\($0)" }.joined()
  }

  private static func hasOnlyValidBasicStringEscapes(in value: String) -> Bool {
    var quote: Character?
    var index = value.startIndex

    while index < value.endIndex {
      let character = value[index]
      if quote == "'" {
        if character == "'" { quote = nil }
        index = value.index(after: index)
        continue
      }
      if quote != "\"" {
        if character == "\"" || character == "'" { quote = character }
        index = value.index(after: index)
        continue
      }
      if character == "\"" {
        quote = nil
        index = value.index(after: index)
        continue
      }
      guard character == "\\" else {
        index = value.index(after: index)
        continue
      }

      let escapeIndex = value.index(after: index)
      guard escapeIndex < value.endIndex else { return false }
      let escape = value[escapeIndex]
      if ["b", "t", "n", "f", "r", "\"", "\\"].contains(escape) {
        index = value.index(after: escapeIndex)
        continue
      }
      guard escape == "u" || escape == "U" else { return false }

      let digitCount = escape == "u" ? 4 : 8
      var cursor = value.index(after: escapeIndex)
      var digits = ""
      for _ in 0 ..< digitCount {
        guard cursor < value.endIndex, value[cursor].isHexDigit else { return false }
        digits.append(value[cursor])
        cursor = value.index(after: cursor)
      }
      guard let scalarValue = UInt32(digits, radix: 16),
        Unicode.Scalar(scalarValue) != nil
      else { return false }
      index = cursor
    }

    return true
  }

  private static func isConservativelyValidValue(_ value: String) -> Bool {
    guard let first = value.first else { return false }
    if first == "\"" || first == "'" {
      return quotedValueConsumesEntireString(value, quote: first)
    }
    if first == "[" || first == "{" { return false }
    if value == "true" || value == "false" || value == "inf" || value == "nan" {
      return true
    }
    if value == "+inf" || value == "-inf" || value == "+nan" || value == "-nan" {
      return true
    }
    return isConservativelyValidNumericValue(value)
  }

  private static func isConservativelyValidNumericValue(_ value: String) -> Bool {
    let patterns = [
      #"^[+-]?(?:0|[1-9](?:_?[0-9])*)$"#,
      #"^0x[0-9A-Fa-f](?:_?[0-9A-Fa-f])*$"#,
      #"^0o[0-7](?:_?[0-7])*$"#,
      #"^0b[01](?:_?[01])*$"#,
      #"^[+-]?(?:0|[1-9](?:_?[0-9])*)(?:(?:\.[0-9](?:_?[0-9])*)(?:[eE][+-]?[0-9](?:_?[0-9])*)?|(?:[eE][+-]?[0-9](?:_?[0-9])*))$"#,
    ]
    return patterns.contains { pattern in
      value.range(of: pattern, options: .regularExpression) != nil
    }
  }

  private static func quotedValueConsumesEntireString(
    _ value: String,
    quote: Character
  ) -> Bool {
    var escaped = false
    for index in value.indices.dropFirst() {
      let character = value[index]
      if escaped {
        escaped = false
      } else if character == "\\" && quote == "\"" {
        escaped = true
      } else if character == quote {
        return value.index(after: index) == value.endIndex
      }
    }
    return false
  }

  private static func removingComment(from line: String) -> String {
    var quote: Character?
    var escaped = false
    for index in line.indices {
      let character = line[index]
      if escaped {
        escaped = false
      } else if character == "\\" && quote == "\"" {
        escaped = true
      } else if character == quote {
        quote = nil
      } else if quote == nil && (character == "\"" || character == "'") {
        quote = character
      } else if character == "#" && quote == nil {
        return String(line[..<index])
      }
    }
    return line
  }

  private func manualPlan(
    configurationURL: URL,
    helperURL: URL,
    targetExisted: Bool,
    before: String,
    instructions: String
  ) -> ConfigurationChangePlan {
    ConfigurationChangePlan(
      clientKind: .codex,
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

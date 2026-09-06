import Foundation
import XCTest

final class MCPConfigurationTests: XCTestCase {
  func testCodexPlannerCreatesExactInstallableBlockForEmptyConfiguration() throws {
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/Users/test/.codex/config.toml"),
      helperURL: helperURL
    )

    XCTAssertEqual(plan.clientKind, .codex)
    XCTAssertEqual(plan.disposition, .installable)
    XCTAssertEqual(
      plan.after,
      "[mcp_servers.mac_coffee]\ncommand = \"/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP\"\n"
    )
    XCTAssertTrue(plan.proposedDiff.contains("+[mcp_servers.mac_coffee]"))
    XCTAssertTrue(plan.proposedDiff.contains("+command = \"/Applications/Mac Coffee.app"))
    XCTAssertEqual(plan.validation, .valid)
  }

  func testCodexPlannerPreservesExistingCommentsAndUnrelatedTablesByteForByte() throws {
    let before = try fixture("codex-existing.toml")
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .installable)
    XCTAssertTrue(try XCTUnwrap(plan.after).hasPrefix(before))
    XCTAssertEqual(try XCTUnwrap(plan.after).components(separatedBy: "# Keep this comment").count, 2)
    XCTAssertEqual(try XCTUnwrap(plan.after).components(separatedBy: "[mcp_servers.other]").count, 2)
  }

  func testCodexPlannerDoesNotDuplicateAnExistingMatchingEntry() throws {
    let before = """
      [mcp_servers.mac_coffee]
      command = "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP"
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .unchanged)
    XCTAssertEqual(plan.before, before)
    XCTAssertEqual(plan.after, before)
    XCTAssertTrue(plan.proposedDiff.isEmpty)
  }

  func testCodexPlannerRejectsDuplicateCommandKeysInManagedTable() throws {
    let before = """
      [mcp_servers.mac_coffee]
      command = "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP"
      "command" = "/usr/local/bin/other"
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerRejectsDuplicateTableDeclarations() throws {
    let before = """
      [tool]
      first = 1
      [tool]
      second = 2
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerRejectsInvalidBareKeys() throws {
    for before in ["retry count = 2\n", "[invalid table]\nvalue = 1\n"] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: before
      )

      XCTAssertEqual(plan.disposition, .manual)
      XCTAssertEqual(plan.validation, .invalid)
      XCTAssertNil(plan.after)
    }
  }

  func testCodexPlannerRejectsValueAndTablePathConflicts() throws {
    for before in [
      "tool = 1\n[tool]\nvalue = 2\n",
      "tool.name = \"value\"\n[tool.name]\nvalue = 2\n",
      "fruit.apple.color = \"red\"\n[fruit.apple]\nkind = \"gala\"\n",
    ] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: before
      )

      XCTAssertEqual(plan.disposition, .manual)
      XCTAssertEqual(plan.validation, .invalid)
      XCTAssertNil(plan.after)
    }
  }

  func testCodexPlannerAcceptsAndCanonicalizesQuotedKeys() throws {
    let before = #""retry\u005fcount" = 2"# + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .installable)
    XCTAssertEqual(plan.validation, .valid)
  }

  func testCodexPlannerRejectsEquivalentDottedKeyDeclaration() throws {
    let before = """
      mcp_servers.mac_coffee = { command = "/usr/local/bin/existing" }
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerRejectsNestedDottedKeyDeclaration() throws {
    let before = """
      mcp_servers.mac_coffee.command = "/usr/local/bin/existing"
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerRejectsEquivalentKeyInsideParentTable() throws {
    let before = """
      [mcp_servers]
      mac_coffee = { command = "/usr/local/bin/existing" }
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerFallsBackToManualInstructionsForMalformedOrConflictingTOML() throws {
    for contents in [try fixture("codex-malformed.toml"), try fixture("codex-conflict.toml")] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: contents
      )
      XCTAssertEqual(plan.disposition, .manual)
      XCTAssertNil(plan.after)
      XCTAssertFalse(plan.manualInstructions.isEmpty)
    }
  }

  func testCodexPlannerRejectsUnterminatedLiteralString() throws {
    let before = "foo = 'unterminated\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerRejectsInvalidBasicStringEscapes() throws {
    for value in [#""\q""#, #""\u12G4""#, #""\u123""#, #""\U00110000""#] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: "path = \(value)\n"
      )

      XCTAssertEqual(plan.disposition, .manual, "Accepted invalid escape: \(value)")
      XCTAssertEqual(plan.validation, .invalid)
      XCTAssertNil(plan.after)
    }
  }

  func testCodexPlannerAcceptsValidBasicStringEscapes() throws {
    let before = #"path = "tab\tquote\"slash\\unicode\u2764long\U0001F600""# + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .installable)
    XCTAssertEqual(plan.validation, .valid)
  }

  func testCodexPlannerRejectsUnterminatedInlineTable() throws {
    let before = "client = { command = \"foo\"\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testCodexPlannerRejectsAssignmentsWithoutValidValues() throws {
    for before in ["foo =\n", "foo = definitely-not-toml\n"] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: before
      )

      XCTAssertEqual(plan.disposition, .manual)
      XCTAssertEqual(plan.validation, .invalid)
      XCTAssertNil(plan.after)
    }
  }

  func testCodexPlannerRejectsMalformedNumericValues() throws {
    for value in ["1 2", "+", "01", "1__2", "1.", ".5"] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: "retry_count = \(value)\n"
      )

      XCTAssertEqual(plan.disposition, .manual, "Accepted malformed value: \(value)")
      XCTAssertEqual(plan.validation, .invalid)
      XCTAssertNil(plan.after)
    }
  }

  func testCodexPlannerAcceptsWellFormedNumericValues() throws {
    let before = """
      decimal = -42
      grouped = 1_000
      hexadecimal = 0xDEAD_BEEF
      decimal_float = 3.14
      exponent = 5e+22
      """ + "\n"

    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .installable)
    XCTAssertEqual(plan.validation, .valid)
  }

  func testCodexPlannerFallsBackForUnvalidatedStructuredValues() throws {
    for value in ["[1,,2]", "{ command = }", "[1, 2]", "{ command = \"foo\" }"] {
      let plan = try CodexConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/config.toml"),
        helperURL: helperURL,
        existingContents: "value = \(value)\n"
      )

      XCTAssertEqual(plan.disposition, .manual)
      XCTAssertEqual(plan.validation, .invalid)
      XCTAssertNil(plan.after)
    }
  }

  func testClaudePlannerMergesServerWithoutDroppingUnrelatedEntries() throws {
    let before = try fixture("claude-existing.json")
    let plan = try ClaudeConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/claude_desktop_config.json"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.clientKind, .claudeDesktop)
    XCTAssertEqual(plan.disposition, .installable)
    XCTAssertEqual(plan.validation, .valid)
    let data = try XCTUnwrap(plan.after).data(using: .utf8)!
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
    XCTAssertNotNil(servers["filesystem"])
    let macCoffee = try XCTUnwrap(servers["mac-coffee"] as? [String: Any])
    XCTAssertEqual(macCoffee["command"] as? String, helperURL.path)
    XCTAssertEqual(macCoffee["args"] as? [String], [])
    XCTAssertEqual((root["preferences"] as? [String: Any])?["theme"] as? String, "dark")
  }

  func testClaudePlannerRejectsMalformedAndDuplicateServerJSONWithoutAWritePlan() throws {
    for fixtureName in ["claude-malformed.json", "claude-duplicate.json"] {
      let plan = try ClaudeConfigurationPlanner().plan(
        configurationURL: URL(fileURLWithPath: "/tmp/claude_desktop_config.json"),
        helperURL: helperURL,
        existingContents: try fixture(fixtureName)
      )
      XCTAssertEqual(plan.disposition, .manual)
      XCTAssertNil(plan.after)
      XCTAssertEqual(plan.validation, .invalid)
    }
  }

  func testClaudePlannerRejectsDuplicateMCPServersContainers() throws {
    let before = """
      {
        "mcpServers": {
          "filesystem": { "command": "/usr/bin/filesystem" }
        },
        "mcpServers": {
          "other": { "command": "/usr/bin/other" }
        }
      }
      """

    let plan = try ClaudeConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/claude_desktop_config.json"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testClaudePlannerDoesNotOverwriteAConflictingMacCoffeeServer() throws {
    let before = """
      {
        "mcpServers": {
          "mac-coffee": {
            "command": "/usr/local/bin/different-server"
          }
        }
      }
      """

    let plan = try ClaudeConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/claude_desktop_config.json"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testClaudePlannerRejectsNonArrayArgs() throws {
    let before = """
      {
        "mcpServers": {
          "mac-coffee": {
            "command": "\(helperURL.path)",
            "args": "--flag"
          }
        }
      }
      """

    let plan = try ClaudeConfigurationPlanner().plan(
      configurationURL: URL(fileURLWithPath: "/tmp/claude_desktop_config.json"),
      helperURL: helperURL,
      existingContents: before
    )

    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertEqual(plan.validation, .invalid)
    XCTAssertNil(plan.after)
  }

  func testGenericPlanUsesAbsoluteEnvironmentFreeCommandAndContainsNoSecretMaterial() {
    let plan = ConfigurationChangePlan.generic(helperURL: helperURL)

    XCTAssertEqual(plan.clientKind, .genericStdio)
    XCTAssertEqual(plan.disposition, .manual)
    XCTAssertTrue(plan.manualInstructions.contains(helperURL.path))
    XCTAssertFalse(plan.manualInstructions.lowercased().contains("token"))
    XCTAssertFalse(plan.manualInstructions.lowercased().contains("secret"))
    XCTAssertFalse(plan.manualInstructions.contains("$"))
  }

  func testInstallerRequiresExactConfirmationHashAndCurrentReviewedContents() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("config.toml")
    try "# reviewed\n".write(to: target, atomically: true, encoding: .utf8)
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: target,
      helperURL: helperURL,
      existingContents: "# reviewed\n"
    )
    let installer = AtomicConfigurationInstaller()

    XCTAssertThrowsError(try installer.install(plan: plan, confirmedHash: "wrong")) {
      XCTAssertEqual($0 as? MCPConfigurationInstallationError, .confirmationMismatch)
    }
    try "# changed after review\n".write(to: target, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try installer.install(plan: plan, confirmedHash: plan.confirmationHash)) {
      XCTAssertEqual($0 as? MCPConfigurationInstallationError, .stalePlan)
    }
  }

  func testInstallerCreatesTimestampedBackupValidatesAndAtomicallyReplacesConfiguration() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("config.toml")
    let before = "# keep\n"
    try before.write(to: target, atomically: true, encoding: .utf8)
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: target,
      helperURL: helperURL,
      existingContents: before
    )
    let now = Date(timeIntervalSince1970: 1_787_932_800)
    let installer = AtomicConfigurationInstaller(now: { now }, uniqueSuffix: { "fixture" })

    let result = try installer.install(plan: plan, confirmedHash: plan.confirmationHash)

    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), plan.after)
    let backup = try XCTUnwrap(result.backupURL)
    XCTAssertTrue(backup.lastPathComponent.hasPrefix("config.toml.maccoffee-backup-"))
    XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), before)
    XCTAssertEqual(result.installedURL, target)
  }

  func testInstallerRefusesSymlinkAndNonWritableConfiguration() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = directory.appendingPathComponent("real.toml")
    let link = directory.appendingPathComponent("config.toml")
    try "".write(to: real, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let symlinkPlan = try CodexConfigurationPlanner().plan(
      configurationURL: link,
      helperURL: helperURL,
      existingContents: ""
    )

    XCTAssertThrowsError(
      try AtomicConfigurationInstaller().install(
        plan: symlinkPlan,
        confirmedHash: symlinkPlan.confirmationHash
      )
    ) {
      XCTAssertEqual($0 as? MCPConfigurationInstallationError, .symbolicLinkRefused)
    }

    try FileManager.default.removeItem(at: link)
    let locked = directory.appendingPathComponent("locked.toml")
    try "".write(to: locked, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: locked.path)
    let lockedPlan = try CodexConfigurationPlanner().plan(
      configurationURL: locked,
      helperURL: helperURL,
      existingContents: ""
    )
    XCTAssertThrowsError(
      try AtomicConfigurationInstaller().install(
        plan: lockedPlan,
        confirmedHash: lockedPlan.confirmationHash
      )
    ) {
      XCTAssertEqual($0 as? MCPConfigurationInstallationError, .notWritable)
    }
  }

  func testInstallerLeavesOriginalUntouchedWhenReplacementPreparationFails() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("config.toml")
    let before = "# original\n"
    try before.write(to: target, atomically: true, encoding: .utf8)
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: target,
      helperURL: helperURL,
      existingContents: before
    )
    let installer = AtomicConfigurationInstaller(
      beforeReplacement: { throw FixtureError.simulatedFailure }
    )

    XCTAssertThrowsError(try installer.install(plan: plan, confirmedHash: plan.confirmationHash))
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), before)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.contains(".maccoffee-") && $0.hasSuffix(".tmp") }
    XCTAssertTrue(leftovers.isEmpty)
  }

  func testInstallerRejectsConcurrentEditImmediatelyBeforeReplacement() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("config.toml")
    let reviewed = "# reviewed\n"
    let concurrent = "# concurrently changed\n"
    try reviewed.write(to: target, atomically: true, encoding: .utf8)
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: target,
      helperURL: helperURL,
      existingContents: reviewed
    )
    let installer = AtomicConfigurationInstaller(
      beforeReplacement: {
        try concurrent.write(to: target, atomically: true, encoding: .utf8)
      }
    )

    XCTAssertThrowsError(
      try installer.install(plan: plan, confirmedHash: plan.confirmationHash)
    ) {
      XCTAssertEqual($0 as? MCPConfigurationInstallationError, .stalePlan)
    }
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), concurrent)
  }

  func testInstallerDoesNotRollbackAConcurrentEditAfterReplacement() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("config.toml")
    let reviewed = "# reviewed\n"
    let concurrent = "# concurrently changed after replacement\n"
    try reviewed.write(to: target, atomically: true, encoding: .utf8)
    let plan = try CodexConfigurationPlanner().plan(
      configurationURL: target,
      helperURL: helperURL,
      existingContents: reviewed
    )
    let installer = AtomicConfigurationInstaller(
      afterReplacement: {
        try concurrent.write(to: target, atomically: true, encoding: .utf8)
      }
    )

    XCTAssertThrowsError(
      try installer.install(plan: plan, confirmedHash: plan.confirmationHash)
    ) {
      XCTAssertEqual($0 as? MCPConfigurationInstallationError, .validationFailed)
    }
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), concurrent)
  }

  private let helperURL = URL(
    fileURLWithPath: "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP"
  )

  private func fixture(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/MCPConfigs")
      .appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacCoffeeMCPConfigTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}

private enum FixtureError: Error {
  case simulatedFailure
}

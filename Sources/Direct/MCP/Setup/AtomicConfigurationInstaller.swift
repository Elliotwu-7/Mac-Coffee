import Foundation

enum MCPConfigurationInstallationError: Error, Equatable {
  case confirmationMismatch
  case planNotInstallable
  case stalePlan
  case symbolicLinkRefused
  case notWritable
  case validationFailed
}

struct MCPConfigurationInstallationResult: Equatable {
  let installedURL: URL
  let backupURL: URL?
}

struct AtomicConfigurationInstaller {
  private let now: () -> Date
  private let uniqueSuffix: () -> String
  private let beforeReplacement: () throws -> Void
  private let afterReplacement: () throws -> Void

  init(
    now: @escaping () -> Date = Date.init,
    uniqueSuffix: @escaping () -> String = { UUID().uuidString },
    beforeReplacement: @escaping () throws -> Void = {},
    afterReplacement: @escaping () throws -> Void = {}
  ) {
    self.now = now
    self.uniqueSuffix = uniqueSuffix
    self.beforeReplacement = beforeReplacement
    self.afterReplacement = afterReplacement
  }

  func install(
    plan: ConfigurationChangePlan,
    confirmedHash: String
  ) throws -> MCPConfigurationInstallationResult {
    guard confirmedHash == plan.confirmationHash else {
      throw MCPConfigurationInstallationError.confirmationMismatch
    }
    guard plan.disposition == .installable, plan.validation == .valid,
      let destination = plan.configurationURL,
      let after = plan.after
    else {
      throw MCPConfigurationInstallationError.planNotInstallable
    }

    let fileManager = FileManager.default
    let destinationExists = fileManager.fileExists(atPath: destination.path)
    guard destinationExists == plan.targetExisted else {
      throw MCPConfigurationInstallationError.stalePlan
    }
    if destinationExists {
      let attributes = try fileManager.attributesOfItem(atPath: destination.path)
      if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
        throw MCPConfigurationInstallationError.symbolicLinkRefused
      }
      if let permissions = attributes[.posixPermissions] as? NSNumber,
        permissions.intValue & 0o222 == 0
      {
        throw MCPConfigurationInstallationError.notWritable
      }
      let current = try String(contentsOf: destination, encoding: .utf8)
      guard current == plan.before else {
        throw MCPConfigurationInstallationError.stalePlan
      }
    } else if !plan.before.isEmpty {
      throw MCPConfigurationInstallationError.stalePlan
    }

    let parent = destination.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    if let permissions = try? fileManager.attributesOfItem(atPath: parent.path)[.posixPermissions]
      as? NSNumber,
      permissions.intValue & 0o222 == 0
    {
      throw MCPConfigurationInstallationError.notWritable
    }

    let temporary = parent.appendingPathComponent(
      ".\(destination.lastPathComponent).maccoffee-\(uniqueSuffix()).tmp"
    )
    defer { try? fileManager.removeItem(at: temporary) }
    try Data(after.utf8).write(to: temporary, options: .withoutOverwriting)
    try fileManager.setAttributes(
      [.posixPermissions: destinationExists ? permissions(at: destination) : 0o600],
      ofItemAtPath: temporary.path
    )
    let temporaryContents = try String(contentsOf: temporary, encoding: .utf8)
    guard ConfigurationPlanValidator.validate(contents: temporaryContents, plan: plan) else {
      throw MCPConfigurationInstallationError.validationFailed
    }

    var coordinationError: NSError?
    var replacementResult: Result<URL?, Error>?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    let coordinatedURL = destinationExists ? destination : parent
    let coordinationOptions: NSFileCoordinator.WritingOptions =
      destinationExists ? .forReplacing : .forMerging
    coordinator.coordinate(
      writingItemAt: coordinatedURL,
      options: coordinationOptions,
      error: &coordinationError
    ) { _ in
      replacementResult = Result {
        try beforeReplacement()
        let stillExists = fileManager.fileExists(atPath: destination.path)
        guard stillExists == plan.targetExisted else {
          throw MCPConfigurationInstallationError.stalePlan
        }
        if stillExists {
          let current = try String(contentsOf: destination, encoding: .utf8)
          guard current == plan.before else {
            throw MCPConfigurationInstallationError.stalePlan
          }
          let candidate = backupURL(for: destination)
          try fileManager.copyItem(at: destination, to: candidate)
          _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: temporary,
            backupItemName: nil,
            options: []
          )
          try afterReplacement()
          let installed = try String(contentsOf: destination, encoding: .utf8)
          guard installed == after,
            ConfigurationPlanValidator.validate(contents: installed, plan: plan)
          else {
            if installed == after {
              _ = try? fileManager.replaceItemAt(destination, withItemAt: candidate)
            }
            throw MCPConfigurationInstallationError.validationFailed
          }
          return candidate
        }
        guard plan.before.isEmpty else { throw MCPConfigurationInstallationError.stalePlan }
        try fileManager.moveItem(at: temporary, to: destination)
        try afterReplacement()
        let installed = try String(contentsOf: destination, encoding: .utf8)
        guard installed == after,
          ConfigurationPlanValidator.validate(contents: installed, plan: plan)
        else {
          if installed == after { try? fileManager.removeItem(at: destination) }
          throw MCPConfigurationInstallationError.validationFailed
        }
        return nil
      }
    }
    if let coordinationError { throw coordinationError }
    guard let replacementResult else {
      throw MCPConfigurationInstallationError.stalePlan
    }
    let createdBackupURL = try replacementResult.get()
    return MCPConfigurationInstallationResult(
      installedURL: destination,
      backupURL: createdBackupURL
    )
  }

  private func permissions(at url: URL) -> Int {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
  }

  private func backupURL(for destination: URL) -> URL {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let baseName = "\(destination.lastPathComponent).maccoffee-backup-\(formatter.string(from: now()))"
    let parent = destination.deletingLastPathComponent()
    let candidate = parent.appendingPathComponent(baseName)
    guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
    return parent.appendingPathComponent("\(baseName)-\(uniqueSuffix())")
  }
}

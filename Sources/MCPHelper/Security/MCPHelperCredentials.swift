import CryptoKit
import Foundation
import MacCoffeeCore

final class MCPHelperCredentials: MCPXPCClientCredentialProviding, @unchecked Sendable {
  private struct ResolvedCredentials {
    let keyStore: KeychainClientKeyStore
    let presentation: MCPAuthenticationPresentation
  }

  private let parentIdentity: @Sendable () throws -> MCPCodeIdentity
  private let lock = NSLock()
  private var resolved: ResolvedCredentials?

  convenience init() {
    self.init(parentIdentity: { try ParentProcessIdentity.capture() })
  }

  convenience init(parentIdentity: MCPCodeIdentity) {
    self.init(parentIdentity: { parentIdentity })
  }

  private init(
    parentIdentity: @escaping @Sendable () throws -> MCPCodeIdentity
  ) {
    self.parentIdentity = parentIdentity
  }

  func authenticationPresentation() throws -> MCPAuthenticationPresentation {
    try resolve().presentation
  }

  func sign(_ transcript: Data) throws -> Data {
    try resolve().keyStore.sign(transcript)
  }

  private func resolve() throws -> ResolvedCredentials {
    lock.lock()
    defer { lock.unlock() }
    if let resolved { return resolved }

    let parentIdentity = try parentIdentity()
    let identifier = Self.clientIdentifier(for: parentIdentity)
    let keyStore = KeychainClientKeyStore(clientIdentifier: identifier)
    let resolved = ResolvedCredentials(
      keyStore: keyStore,
      presentation: MCPAuthenticationPresentation(
        clientIdentifier: identifier,
        displayName: Self.displayName(for: parentIdentity),
        publicKey: try keyStore.publicKey(),
        parentIdentity: parentIdentity
      )
    )
    self.resolved = resolved
    return resolved
  }

  private static func clientIdentifier(for identity: MCPCodeIdentity) -> String {
    let material: String
    if identity.isSigned {
      material = [
        "signed",
        identity.teamIdentifier ?? "",
        identity.signingIdentifier ?? "",
        identity.bundleIdentifier ?? "",
      ].joined(separator: "\u{1F}")
    } else {
      material = [
        "unsigned",
        identity.executablePath,
        identity.codeDirectoryHash ?? "",
      ].joined(separator: "\u{1F}")
    }
    let digest = SHA256.hash(data: Data(material.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "maccoffee-client-\(digest)"
  }

  private static func displayName(for identity: MCPCodeIdentity) -> String {
    if let bundleIdentifier = identity.bundleIdentifier, !bundleIdentifier.isEmpty {
      return bundleIdentifier
    }
    let name = URL(fileURLWithPath: identity.executablePath).lastPathComponent
    return name.isEmpty ? "Local MCP client" : name
  }
}

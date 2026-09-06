import Darwin
import Foundation
import Security

public final class MCPBrokerPeerValidator: @unchecked Sendable {
  private static let pathBufferSize = 4_096

  private let appBundleURL: URL
  private let expectedTeamIdentifier: String?

  public init(bundle: Bundle = .main) {
    appBundleURL =
      Self.containingAppBundle(for: bundle.bundleURL)
      ?? bundle.bundleURL
    expectedTeamIdentifier = Self.signingTeamIdentifier(for: bundle.executableURL)
  }

  public func role(for connection: NSXPCConnection) -> MCPBrokerPeerRole? {
    guard connection.effectiveUserIdentifier == getuid(),
      let executableURL = Self.executableURL(
        processIdentifier: connection.processIdentifier
      )
    else {
      return nil
    }

    let canonical = executableURL.resolvingSymlinksInPath().standardizedFileURL
    let appExecutable =
      appBundleURL
      .appendingPathComponent("Contents/MacOS/Mac Coffee")
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let helperExecutable =
      appBundleURL
      .appendingPathComponent("Contents/Helpers/MacCoffeeMCP")
      .resolvingSymlinksInPath()
      .standardizedFileURL

    let role: MCPBrokerPeerRole
    if canonical == appExecutable {
      role = .app
    } else if canonical == helperExecutable {
      role = .helper
    } else {
      return nil
    }

    guard
      Self.hasValidSignature(
        canonical,
        expectedTeamIdentifier: expectedTeamIdentifier
      )
    else {
      return nil
    }
    return role
  }

  private static func containingAppBundle(for url: URL) -> URL? {
    var candidate = url.standardizedFileURL
    while candidate.path != "/" {
      if candidate.pathExtension == "app" { return candidate }
      candidate.deleteLastPathComponent()
    }
    return nil
  }

  private static func executableURL(processIdentifier: pid_t) -> URL? {
    guard processIdentifier > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: pathBufferSize)
    let length = proc_pidpath(
      processIdentifier,
      &buffer,
      UInt32(buffer.count)
    )
    guard length > 0 else {
      return nil
    }
    let bytes = buffer.prefix(Int(length)).map(UInt8.init(bitPattern:))
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
  }

  private static func hasValidSignature(
    _ executableURL: URL,
    expectedTeamIdentifier: String?
  ) -> Bool {
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(
        executableURL as CFURL,
        SecCSFlags(),
        &code
      ) == errSecSuccess,
      let code,
      SecStaticCodeCheckValidity(
        code,
        SecCSFlags(rawValue: kSecCSStrictValidate),
        nil
      ) == errSecSuccess
    else {
      return false
    }

    guard let expectedTeamIdentifier else {
      return true
    }
    return signingTeamIdentifier(for: executableURL) == expectedTeamIdentifier
  }

  private static func signingTeamIdentifier(for executableURL: URL?) -> String? {
    guard let executableURL else { return nil }
    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(
        executableURL as CFURL,
        SecCSFlags(),
        &code
      ) == errSecSuccess,
      let code
    else {
      return nil
    }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &information
      ) == errSecSuccess,
      let dictionary = information as? [String: Any]
    else {
      return nil
    }
    return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
  }
}

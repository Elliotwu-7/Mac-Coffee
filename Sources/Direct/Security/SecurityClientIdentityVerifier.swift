import CryptoKit
import Foundation
import MacCoffeeCore
import Security

public enum SecurityRandomNonceGeneratorError: Error, Equatable {
    case invalidByteCount
    case securityFramework(OSStatus)
}

public final class SecurityRandomNonceGenerator: MCPNonceGenerating {
    public init() {}

    public func nextNonce(byteCount: Int) throws -> Data {
        guard (1...4_096).contains(byteCount) else {
            throw SecurityRandomNonceGeneratorError.invalidByteCount
        }
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
        }
        guard status == errSecSuccess else {
            data.resetBytes(in: data.indices)
            throw SecurityRandomNonceGeneratorError.securityFramework(status)
        }
        return data
    }
}

public enum SecurityClientIdentityVerifierError: Error, Equatable {
    case invalidExecutablePath
    case unreadableExecutable
    case securityFramework(OSStatus)
}

public final class SecurityClientIdentityVerifier: MCPExecutableIdentityVerifying {
    public init() {}

    public func identity(forExecutableAt path: String) throws -> MCPCodeIdentity {
        guard path.hasPrefix("/") else {
            throw SecurityClientIdentityVerifierError.invalidExecutablePath
        }
        let executableURL = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: executableURL.path,
                isDirectory: &isDirectory
            ),
            !isDirectory.boolValue
        else {
            throw SecurityClientIdentityVerifierError.invalidExecutablePath
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            executableURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            throw SecurityClientIdentityVerifierError.securityFramework(createStatus)
        }

        let validityStatus = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(),
            nil
        )
        let hasValidSignature = validityStatus == errSecSuccess
        let signingInfo = hasValidSignature ? copySigningInformation(staticCode) : nil
        let fileHash = try sha256(of: executableURL)
        let signingIdentifier = signingInfo?[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = signingInfo?[kSecCodeInfoTeamIdentifier as String] as? String
        let isVerifiedSignature = hasValidSignature
            && teamIdentifier?.isEmpty == false
            && signingIdentifier?.isEmpty == false
        let codeDirectoryHash = isVerifiedSignature
            ? (signingInfo?[kSecCodeInfoUnique as String] as? Data)?.hexadecimalString ?? fileHash
            : fileHash

        return MCPCodeIdentity(
            executablePath: executableURL.path,
            bundleIdentifier: containingBundleIdentifier(for: executableURL),
            teamIdentifier: teamIdentifier,
            signingIdentifier: signingIdentifier,
            codeDirectoryHash: codeDirectoryHash,
            isSigned: isVerifiedSignature
        )
    }

    private func copySigningInformation(
        _ staticCode: SecStaticCode
    ) -> [String: Any]? {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard status == errSecSuccess else { return nil }
        return information as? [String: Any]
    }

    private func sha256(of url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw SecurityClientIdentityVerifierError.unreadableExecutable
        }
        return Data(SHA256.hash(data: data)).hexadecimalString
    }

    private func containingBundleIdentifier(for executableURL: URL) -> String? {
        var candidate = executableURL.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return Bundle(url: candidate)?.bundleIdentifier
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import MacCoffeeCore

final class MCPSecurityAdapterTests: XCTestCase {
    func testSecurityNonceGeneratorReturnsFreshRequestedLength() throws {
        let generator = SecurityRandomNonceGenerator()

        let first = try generator.nextNonce(byteCount: 32)
        let second = try generator.nextNonce(byteCount: 32)

        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(second.count, 32)
        XCTAssertNotEqual(first, second)
    }

    func testP256ClientKeyPersistsAndSignsVerifiableTranscripts() throws {
        let credentials = FakeMCPCredentialStore()
        let first = KeychainClientKeyStore(
            credentials: credentials,
            clientIdentifier: "codex-client"
        )
        let message = Data("maccoffee-authentication-transcript".utf8)

        let publicKey = try first.publicKey()
        let signature = try first.sign(message)
        let recreated = KeychainClientKeyStore(
            credentials: credentials,
            clientIdentifier: "codex-client"
        )

        XCTAssertEqual(try recreated.publicKey(), publicKey)
        XCTAssertTrue(
            MCPP256SignatureVerifier().verify(
                signature: signature,
                message: message,
                publicKey: publicKey
            )
        )
        XCTAssertFalse(
            MCPP256SignatureVerifier().verify(
                signature: signature,
                message: Data("different-transcript".utf8),
                publicKey: publicKey
            )
        )
        XCTAssertEqual(credentials.writeCount, 1)
    }

    func testExportedClientIdentityContainsNoPrivateKeyMaterial() throws {
        let credentials = FakeMCPCredentialStore()
        let keyStore = KeychainClientKeyStore(
            credentials: credentials,
            clientIdentifier: "codex-client"
        )
        let identity = try keyStore.publicIdentity(displayName: "Codex")
        let encoded = try JSONEncoder().encode(identity)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let storedPrivateKey = try XCTUnwrap(
            credentials.values[KeychainClientKeyStore.privateKeyCredentialKey(for: "codex-client")]
        )

        XCTAssertEqual(Set(object.keys), ["clientIdentifier", "displayName", "publicKey"])
        XCTAssertFalse(encoded.contains(storedPrivateKey))
        XCTAssertNil(object["privateKey"])
        XCTAssertNil(object["pairingSecret"])
    }

    func testPrivateKeyKeychainQueryIsDeviceOnlyAndNeverSynchronizes() {
        let query = KeychainClientKeyStore.makeAddQuery(
            service: "com.rekurt.maccoffee.mcp.client-key",
            account: "client-key",
            data: Data([1, 2, 3])
        )

        XCTAssertEqual(query[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain] as? Bool, true)
        XCTAssertEqual(
            query[kSecAttrAccessible] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    func testSystemSignatureVerifierRejectsMalformedKeyAndSignature() {
        let verifier = MCPP256SignatureVerifier()

        XCTAssertFalse(
            verifier.verify(
                signature: Data([1, 2, 3]),
                message: Data([4, 5, 6]),
                publicKey: Data([7, 8, 9])
            )
        )
    }

    func testTeamSignedExecutableIdentityIsVerifiedFromItsRealPath() throws {
        let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? "/Applications/Xcode.app/Contents/Developer"
        let xcodeExecutable = URL(fileURLWithPath: developerDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("MacOS/Xcode")
        let verifier = SecurityClientIdentityVerifier()
        let identity = try verifier.identity(forExecutableAt: xcodeExecutable.path)

        XCTAssertTrue(identity.executablePath.hasPrefix("/"))
        XCTAssertTrue(identity.isSigned)
        XCTAssertNotNil(identity.teamIdentifier)
        XCTAssertNotNil(identity.signingIdentifier)
        XCTAssertNotNil(identity.codeDirectoryHash)
    }

    func testAdHocSignedExecutableIdentityUsesFileHashAndRequiresApproval() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executableURL = temporaryDirectory.appendingPathComponent("echo")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/echo"),
            to: executableURL
        )
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", executableURL.path]
        try codesign.run()
        codesign.waitUntilExit()
        XCTAssertEqual(codesign.terminationStatus, 0)

        let identity = try SecurityClientIdentityVerifier()
            .identity(forExecutableAt: executableURL.path)
        let fileData = try Data(contentsOf: executableURL, options: .mappedIfSafe)
        let fileHash = Data(SHA256.hash(data: fileData))
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertFalse(identity.isSigned)
        XCTAssertNil(identity.teamIdentifier)
        XCTAssertEqual(identity.codeDirectoryHash, fileHash)
    }

    func testParentProcessCaptureReturnsIdentityForRequestedPID() throws {
        let identity = try ParentProcessIdentity.capture(processIdentifier: getpid())

        XCTAssertTrue(identity.executablePath.hasPrefix("/"))
        XCTAssertNotNil(identity.codeDirectoryHash)
    }
}

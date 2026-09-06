import Foundation
import Security
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPTrustStoreTests: XCTestCase {
    func testTrustedClientArchivePersistsAcrossStoreRecreation() throws {
        let credentials = FakeMCPCredentialStore()
        let firstStore = MCPTrustStore(credentials: credentials)
        let client = makeClient(identifier: "client-1", displayName: "Codex")

        try firstStore.trust(client)
        let recreated = MCPTrustStore(credentials: credentials)

        XCTAssertEqual(try recreated.clients(), [client])
        XCTAssertEqual(try recreated.client(identifier: "client-1"), client)
        XCTAssertNil(try recreated.client(identifier: "missing"))
    }

    func testTrustUpdateLastSeenAndRevocationPersist() throws {
        let credentials = FakeMCPCredentialStore()
        let store = MCPTrustStore(credentials: credentials)
        let original = makeClient(identifier: "client-1", displayName: "Codex")
        let renamed = makeClient(identifier: "client-1", displayName: "Codex CLI")
        let seenAt = Date(timeIntervalSince1970: 2_000)
        let revokedAt = Date(timeIntervalSince1970: 3_000)

        try store.trust(original)
        try store.trust(renamed)
        XCTAssertEqual(try store.client(identifier: "client-1")?.displayName, "Codex CLI")

        XCTAssertTrue(try store.markSeen(identifier: "client-1", at: seenAt))
        XCTAssertEqual(try store.client(identifier: "client-1")?.lastSeenAt, seenAt)
        XCTAssertTrue(try store.revoke(identifier: "client-1", at: revokedAt))
        let revoked = try XCTUnwrap(store.client(identifier: "client-1"))
        XCTAssertEqual(revoked.revokedAt, revokedAt)
        XCTAssertTrue(revoked.isRevoked)

        XCTAssertFalse(try store.markSeen(identifier: "missing", at: seenAt))
        XCTAssertFalse(try store.revoke(identifier: "missing", at: revokedAt))
    }

    func testForgetAndForgetAllDeleteOnlyRequestedTrust() throws {
        let credentials = FakeMCPCredentialStore()
        let store = MCPTrustStore(credentials: credentials)
        try store.trust(makeClient(identifier: "client-1", displayName: "Codex"))
        try store.trust(makeClient(identifier: "client-2", displayName: "Claude Desktop"))

        XCTAssertTrue(try store.forget(identifier: "client-1"))
        XCTAssertEqual(try store.clients().map(\.identifier), ["client-2"])
        XCTAssertFalse(try store.forget(identifier: "missing"))

        try store.forgetAll()
        XCTAssertTrue(try store.clients().isEmpty)
        XCTAssertEqual(credentials.removedKeys, [MCPTrustStore.credentialKey])
    }

    func testCorruptOrUnsupportedArchiveNeverProducesTrustedClients() throws {
        let credentials = FakeMCPCredentialStore()
        credentials.values[MCPTrustStore.credentialKey] = Data("not-json".utf8)
        let corrupt = MCPTrustStore(credentials: credentials)

        XCTAssertThrowsError(try corrupt.clients()) { error in
            XCTAssertEqual(error as? MCPTrustStoreError, .corruptArchive)
        }

        credentials.values[MCPTrustStore.credentialKey] = try JSONSerialization.data(
            withJSONObject: ["schemaVersion": 999, "clients": []]
        )
        let unsupported = MCPTrustStore(credentials: credentials)
        XCTAssertThrowsError(try unsupported.clients()) { error in
            XCTAssertEqual(error as? MCPTrustStoreError, .unsupportedArchiveVersion)
        }
    }

    func testInvalidTrustRecordsAreRejectedBeforeCredentialWrite() {
        let credentials = FakeMCPCredentialStore()
        let store = MCPTrustStore(credentials: credentials)
        let invalid = MCPTrustedClient(
            identifier: "",
            displayName: "Invalid",
            publicKey: Data(),
            codeIdentity: makeIdentity(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil,
            revokedAt: nil
        )

        XCTAssertThrowsError(try store.trust(invalid)) { error in
            XCTAssertEqual(error as? MCPTrustStoreError, .invalidClientRecord)
        }
        XCTAssertEqual(credentials.writeCount, 0)
    }

    func testKeychainQueriesAreNonSynchronizingAndDeviceOnly() {
        let add = KeychainMCPCredentialStore.makeAddQuery(
            service: "com.rekurt.maccoffee.mcp",
            key: "trust",
            data: Data([1, 2, 3])
        )
        let lookup = KeychainMCPCredentialStore.makeLookupQuery(
            service: "com.rekurt.maccoffee.mcp",
            key: "trust"
        )
        let deletion = KeychainMCPCredentialStore.makeDeleteQuery(
            service: "com.rekurt.maccoffee.mcp",
            key: "trust"
        )

        XCTAssertEqual(add[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(lookup[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(deletion[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(
            add[kSecAttrAccessible] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(add[kSecUseDataProtectionKeychain] as? Bool, true)
    }

    private func makeClient(
        identifier: String,
        displayName: String
    ) -> MCPTrustedClient {
        MCPTrustedClient(
            identifier: identifier,
            displayName: displayName,
            publicKey: Data([1, 2, 3, 4]),
            codeIdentity: makeIdentity(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil,
            revokedAt: nil
        )
    }

    private func makeIdentity() -> MCPCodeIdentity {
        MCPCodeIdentity(
            executablePath: "/Applications/Codex.app/Contents/MacOS/Codex",
            bundleIdentifier: "com.openai.codex",
            teamIdentifier: "OPENAI",
            signingIdentifier: "com.openai.codex",
            codeDirectoryHash: "0123456789abcdef",
            isSigned: true
        )
    }
}

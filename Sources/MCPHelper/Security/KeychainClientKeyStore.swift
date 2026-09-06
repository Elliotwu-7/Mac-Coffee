import CryptoKit
import Foundation
import MacCoffeeCore
import Security

public enum KeychainClientKeyStoreError: Error, Equatable {
    case invalidClientIdentifier
    case invalidStoredPrivateKey
    case keychain(OSStatus)
}

public final class KeychainClientKeyStore {
    public static let service = "com.rekurt.maccoffee.mcp.client-key"

    private let credentials: MCPCredentialStoring
    private let clientIdentifier: String
    private let lock = NSLock()

    public convenience init(clientIdentifier: String) {
        self.init(
            credentials: ClientPrivateKeyCredentialStore(service: Self.service),
            clientIdentifier: clientIdentifier
        )
    }

    public init(
        credentials: MCPCredentialStoring,
        clientIdentifier: String
    ) {
        self.credentials = credentials
        self.clientIdentifier = clientIdentifier
    }

    public func publicKey() throws -> Data {
        try withPrivateKey { $0.publicKey.x963Representation }
    }

    public func sign(_ message: Data) throws -> Data {
        try withPrivateKey {
            try $0.signature(for: message).derRepresentation
        }
    }

    public func publicIdentity(displayName: String) throws -> MCPClientPublicIdentity {
        MCPClientPublicIdentity(
            clientIdentifier: clientIdentifier,
            displayName: displayName,
            publicKey: try publicKey()
        )
    }

    public static func privateKeyCredentialKey(for clientIdentifier: String) -> String {
        "p256-signing-key.\(clientIdentifier)"
    }

    static func makeAddQuery(
        service: String,
        account: String,
        data: Data
    ) -> [CFString: Any] {
        ClientPrivateKeyCredentialStore.makeAddQuery(
            service: service,
            account: account,
            data: data
        )
    }

    private func withPrivateKey<T>(
        _ body: (P256.Signing.PrivateKey) throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard
            !clientIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            clientIdentifier.count <= 256
        else {
            throw KeychainClientKeyStoreError.invalidClientIdentifier
        }
        return try body(loadOrCreatePrivateKey())
    }

    private func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
        let credentialKey = Self.privateKeyCredentialKey(for: clientIdentifier)
        if var stored = try credentials.data(for: credentialKey) {
            defer { stored.resetBytes(in: stored.indices) }
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: stored) else {
                throw KeychainClientKeyStoreError.invalidStoredPrivateKey
            }
            return key
        }

        let key = P256.Signing.PrivateKey()
        var rawRepresentation = key.rawRepresentation
        defer { rawRepresentation.resetBytes(in: rawRepresentation.indices) }
        try credentials.setData(rawRepresentation, for: credentialKey)
        return key
    }
}

private final class ClientPrivateKeyCredentialStore: MCPCredentialStoring {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func data(for key: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            Self.makeLookupQuery(service: service, account: key) as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainClientKeyStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw KeychainClientKeyStoreError.invalidStoredPrivateKey
        }
        return data
    }

    func setData(_ data: Data, for key: String) throws {
        let status = SecItemAdd(
            Self.makeAddQuery(
                service: service,
                account: key,
                data: data
            ) as CFDictionary,
            nil
        )
        if status == errSecSuccess { return }
        guard status == errSecDuplicateItem else {
            throw KeychainClientKeyStoreError.keychain(status)
        }
        let updateStatus = SecItemUpdate(
            Self.baseQuery(service: service, account: key) as CFDictionary,
            [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainClientKeyStoreError.keychain(updateStatus)
        }
    }

    func removeData(for key: String) throws {
        let status = SecItemDelete(
            Self.baseQuery(service: service, account: key) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainClientKeyStoreError.keychain(status)
        }
    }

    static func makeAddQuery(
        service: String,
        account: String,
        data: Data
    ) -> [CFString: Any] {
        var query = baseQuery(service: service, account: account)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData] = data
        return query
    }

    private static func makeLookupQuery(
        service: String,
        account: String
    ) -> [CFString: Any] {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        return query
    }

    private static func baseQuery(
        service: String,
        account: String
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain: kCFBooleanTrue as Any
        ]
    }
}

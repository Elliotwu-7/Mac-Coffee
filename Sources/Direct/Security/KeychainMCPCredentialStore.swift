import Foundation
import MacCoffeeCore
import Security

enum KeychainMCPCredentialStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidItem
}

public final class KeychainMCPCredentialStore: MCPCredentialStoring {
    private let service: String

    public init(service: String = "com.rekurt.maccoffee.mcp") {
        self.service = service
    }

    public func data(for key: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            Self.makeLookupQuery(service: service, key: key) as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainMCPCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainMCPCredentialStoreError.invalidItem
        }
        return data
    }

    public func setData(_ data: Data, for key: String) throws {
        let status = SecItemAdd(
            Self.makeAddQuery(service: service, key: key, data: data) as CFDictionary,
            nil
        )
        guard status == errSecDuplicateItem else {
            guard status == errSecSuccess else {
                throw KeychainMCPCredentialStoreError.unexpectedStatus(status)
            }
            return
        }

        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            Self.makeDeleteQuery(service: service, key: key) as CFDictionary,
            update as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainMCPCredentialStoreError.unexpectedStatus(updateStatus)
        }
    }

    public func removeData(for key: String) throws {
        let status = SecItemDelete(
            Self.makeDeleteQuery(service: service, key: key) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainMCPCredentialStoreError.unexpectedStatus(status)
        }
    }

    static func makeAddQuery(
        service: String,
        key: String,
        data: Data
    ) -> [CFString: Any] {
        var query = baseQuery(service: service, key: key)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData] = data
        return query
    }

    static func makeLookupQuery(service: String, key: String) -> [CFString: Any] {
        var query = baseQuery(service: service, key: key)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        return query
    }

    static func makeDeleteQuery(service: String, key: String) -> [CFString: Any] {
        baseQuery(service: service, key: key)
    }

    private static func baseQuery(service: String, key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain: kCFBooleanTrue as Any
        ]
    }
}

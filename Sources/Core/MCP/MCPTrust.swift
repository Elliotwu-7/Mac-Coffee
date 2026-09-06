import Foundation

public struct MCPCodeIdentity: Codable, Equatable, Sendable {
    public let executablePath: String
    public let bundleIdentifier: String?
    public let teamIdentifier: String?
    public let signingIdentifier: String?
    public let codeDirectoryHash: String?
    public let isSigned: Bool

    public init(
        executablePath: String,
        bundleIdentifier: String?,
        teamIdentifier: String?,
        signingIdentifier: String?,
        codeDirectoryHash: String?,
        isSigned: Bool
    ) {
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
        self.codeDirectoryHash = codeDirectoryHash
        self.isSigned = isSigned
    }
}

public struct MCPTrustedClient: Codable, Equatable, Identifiable, Sendable {
    public var id: String { identifier }
    public var isRevoked: Bool { revokedAt != nil }

    public let identifier: String
    public let displayName: String
    public let publicKey: Data
    public let codeIdentity: MCPCodeIdentity
    public let createdAt: Date
    public let lastSeenAt: Date?
    public let revokedAt: Date?

    public init(
        identifier: String,
        displayName: String,
        publicKey: Data,
        codeIdentity: MCPCodeIdentity,
        createdAt: Date,
        lastSeenAt: Date?,
        revokedAt: Date?
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.publicKey = publicKey
        self.codeIdentity = codeIdentity
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.revokedAt = revokedAt
    }

    fileprivate func replacing(lastSeenAt: Date?) -> MCPTrustedClient {
        MCPTrustedClient(
            identifier: identifier,
            displayName: displayName,
            publicKey: publicKey,
            codeIdentity: codeIdentity,
            createdAt: createdAt,
            lastSeenAt: lastSeenAt,
            revokedAt: revokedAt
        )
    }

    fileprivate func replacing(revokedAt: Date?) -> MCPTrustedClient {
        MCPTrustedClient(
            identifier: identifier,
            displayName: displayName,
            publicKey: publicKey,
            codeIdentity: codeIdentity,
            createdAt: createdAt,
            lastSeenAt: lastSeenAt,
            revokedAt: revokedAt
        )
    }
}

public enum MCPTrustStoreError: Error, Equatable, Sendable {
    case corruptArchive
    case unsupportedArchiveVersion
    case invalidClientRecord
}

@MainActor
public final class MCPTrustStore {
    public static let credentialKey = "trusted-clients-v1"

    private struct Archive: Codable {
        let schemaVersion: Int
        var clients: [MCPTrustedClient]
    }

    private static let archiveVersion = 1
    private let credentials: MCPCredentialStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(credentials: MCPCredentialStoring) {
        self.credentials = credentials
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public func clients() throws -> [MCPTrustedClient] {
        try load().clients
    }

    public func client(identifier: String) throws -> MCPTrustedClient? {
        try load().clients.first { $0.identifier == identifier }
    }

    public func trust(_ client: MCPTrustedClient) throws {
        guard isValid(client) else {
            throw MCPTrustStoreError.invalidClientRecord
        }
        var archive = try load()
        if let index = archive.clients.firstIndex(where: { $0.identifier == client.identifier }) {
            archive.clients[index] = client
        } else {
            archive.clients.append(client)
        }
        try save(archive)
    }

    @discardableResult
    public func markSeen(identifier: String, at date: Date) throws -> Bool {
        var archive = try load()
        guard let index = archive.clients.firstIndex(where: { $0.identifier == identifier }) else {
            return false
        }
        archive.clients[index] = archive.clients[index].replacing(lastSeenAt: date)
        try save(archive)
        return true
    }

    @discardableResult
    public func revoke(identifier: String, at date: Date) throws -> Bool {
        var archive = try load()
        guard let index = archive.clients.firstIndex(where: { $0.identifier == identifier }) else {
            return false
        }
        archive.clients[index] = archive.clients[index].replacing(revokedAt: date)
        try save(archive)
        return true
    }

    @discardableResult
    public func forget(identifier: String) throws -> Bool {
        var archive = try load()
        let originalCount = archive.clients.count
        archive.clients.removeAll { $0.identifier == identifier }
        guard archive.clients.count != originalCount else { return false }
        try save(archive)
        return true
    }

    public func forgetAll() throws {
        try credentials.removeData(for: Self.credentialKey)
    }

    private func load() throws -> Archive {
        guard let data = try credentials.data(for: Self.credentialKey) else {
            return Archive(schemaVersion: Self.archiveVersion, clients: [])
        }
        let archive: Archive
        do {
            archive = try decoder.decode(Archive.self, from: data)
        } catch {
            throw MCPTrustStoreError.corruptArchive
        }
        guard archive.schemaVersion == Self.archiveVersion else {
            throw MCPTrustStoreError.unsupportedArchiveVersion
        }
        guard archive.clients.allSatisfy(isValid) else {
            throw MCPTrustStoreError.corruptArchive
        }
        return archive
    }

    private func save(_ archive: Archive) throws {
        try credentials.setData(try encoder.encode(archive), for: Self.credentialKey)
    }

    private func isValid(_ client: MCPTrustedClient) -> Bool {
        let identifier = client.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = client.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !identifier.isEmpty
            && identifier.count <= 256
            && !displayName.isEmpty
            && displayName.count <= 128
            && !client.publicKey.isEmpty
            && client.codeIdentity.executablePath.hasPrefix("/")
    }
}

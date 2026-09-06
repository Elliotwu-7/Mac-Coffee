import Darwin
import Foundation
import ServiceManagement

@MainActor
public final class SMAppLaunchAtLoginManager: LaunchAtLoginManaging {
    private let serviceStatus: () -> SMAppService.Status
    private let registerService: () throws -> Void
    private let unregisterService: () throws -> Void
    private let legacyAgent: LegacyLaunchAgentManager

    public init() {
        let service = SMAppService.mainApp
        serviceStatus = { service.status }
        registerService = { try service.register() }
        unregisterService = { try service.unregister() }
        legacyAgent = .system
    }

    init(
        serviceStatus: @escaping () -> SMAppService.Status,
        registerService: @escaping () throws -> Void,
        unregisterService: @escaping () throws -> Void,
        legacyAgent: LegacyLaunchAgentManager
    ) {
        self.serviceStatus = serviceStatus
        self.registerService = registerService
        self.unregisterService = unregisterService
        self.legacyAgent = legacyAgent
    }

    public var status: LaunchAtLoginStatus {
        if legacyAgent.isInstalled { return .enabled }
        return switch serviceStatus() {
        case .enabled:
            .enabled
        case .notRegistered:
            .disabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .disabled
        @unknown default:
            .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if serviceStatus() != .enabled {
                try registerService()
            }
            try legacyAgent.removeIfPresent()
            return
        }

        var operationError: (any Error)?
        if serviceStatus() != .notRegistered {
            do {
                try unregisterService()
            } catch {
                operationError = error
            }
        }
        do {
            try legacyAgent.removeIfPresent()
        } catch {
            if operationError == nil { operationError = error }
        }
        if let operationError { throw operationError }
    }
}

@MainActor
struct LegacyLaunchAgentManager {
    let plistURL: URL
    let fileExists: (URL) -> Bool
    let bootout: (URL) -> Void
    let removeItem: (URL) throws -> Void

    static let system = LegacyLaunchAgentManager(
        plistURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.elliotwu.maccoffee.plist"),
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        bootout: { url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootout", "gui/\(getuid())", url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
        },
        removeItem: { try FileManager.default.removeItem(at: $0) }
    )

    var isInstalled: Bool {
        fileExists(plistURL)
    }

    func removeIfPresent() throws {
        guard isInstalled else { return }
        bootout(plistURL)
        try removeItem(plistURL)
    }
}

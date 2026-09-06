import Foundation

public struct MCPAppState: Equatable, Sendable {
    public let mode: WakeMode
    public let session: WakeSession?
    public let selectedDuration: SessionDuration
    public let batteryState: BatteryState
    public let batteryThreshold: Int
    public let isBatteryBlocked: Bool
    public let launchAtLoginStatus: LaunchAtLoginStatus
    public let statusNotice: AppStatusNotice?
    public let isBusy: Bool

    public init(
        mode: WakeMode,
        session: WakeSession?,
        selectedDuration: SessionDuration,
        batteryState: BatteryState,
        batteryThreshold: Int,
        isBatteryBlocked: Bool,
        launchAtLoginStatus: LaunchAtLoginStatus,
        statusNotice: AppStatusNotice?,
        isBusy: Bool
    ) {
        self.mode = mode
        self.session = session
        self.selectedDuration = selectedDuration
        self.batteryState = batteryState
        self.batteryThreshold = batteryThreshold
        self.isBatteryBlocked = isBatteryBlocked
        self.launchAtLoginStatus = launchAtLoginStatus
        self.statusNotice = statusNotice
        self.isBusy = isBusy
    }

}

@MainActor
public extension AppModel {
    var mcpAppState: MCPAppState {
        MCPAppState(
            mode: mode,
            session: session,
            selectedDuration: selectedDuration,
            batteryState: batteryState,
            batteryThreshold: batteryThreshold,
            isBatteryBlocked: isBatteryBlocked,
            launchAtLoginStatus: launchAtLoginStatus,
            statusNotice: statusNotice,
            isBusy: isBusy
        )
    }
}

@MainActor
public final class MCPSnapshotFactory {
    private let localization: LocalizationController
    private let now: () -> Date
    private let dateFormatter: ISO8601DateFormatter
    private var sequence: UInt64 = 0

    public init(
        localization: LocalizationController,
        now: @escaping () -> Date = Date.init
    ) {
        self.localization = localization
        self.now = now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter = formatter
    }

    public func makeStatus(
        from model: AppModel,
        requestID: String? = nil
    ) -> MCPEnvelope<MCPStatusSnapshot> {
        makeStatus(from: model.mcpAppState, requestID: requestID)
    }

    public func makeStatus(
        from state: MCPAppState,
        requestID: String? = nil
    ) -> MCPEnvelope<MCPStatusSnapshot> {
        sequence = sequence == .max ? 1 : sequence + 1
        let snapshot = MCPStatusSnapshot(
            mode: state.mode,
            session: state.session.map(makeSession),
            selectedDuration: state.selectedDuration,
            battery: MCPBatterySnapshot(
                powerSource: state.batteryState.powerSource,
                percentage: state.batteryState.percentage,
                hasInternalBattery: state.batteryState.hasInternalBattery,
                threshold: state.batteryThreshold,
                blocked: state.isBatteryBlocked
            ),
            launchAtLogin: makeLaunchAtLogin(state.launchAtLoginStatus),
            language: MCPLanguageSnapshot(
                selected: localization.selectedLanguage.rawValue,
                effective: localization.locale.identifier
            ),
            busy: state.isBusy,
            notice: state.statusNotice.map(makeNotice)
        )
        return MCPEnvelope(
            sequence: sequence,
            timestamp: format(now()),
            requestID: requestID,
            data: snapshot,
            displayText: localization.localized(statusKey(for: state.mode))
        )
    }

    private func makeSession(_ session: WakeSession) -> MCPSessionSnapshot {
        MCPSessionSnapshot(
            mode: session.mode,
            duration: session.duration,
            startedAt: format(session.startedAt),
            expiresAt: session.expiresAt.map(format)
        )
    }

    private func makeLaunchAtLogin(_ status: LaunchAtLoginStatus) -> MCPLaunchAtLoginState {
        switch status {
        case .enabled: .enabled
        case .disabled: .disabled
        case .requiresApproval: .requiresApproval
        case .unavailable: .unavailable
        }
    }

    private func makeNotice(_ notice: AppStatusNotice) -> MCPNoticeSnapshot {
        let code: MCPNoticeCode
        switch notice {
        case .batteryBlocked: code = .batteryBlocked
        case .timerCompleted: code = .timerCompleted
        case .powerAssertionFailed: code = .powerAssertionFailed
        case .launchAtLoginFailed: code = .launchAtLoginFailed
        }
        return MCPNoticeSnapshot(
            code: code,
            displayText: notice.localized(using: localization)
        )
    }

    private func statusKey(for mode: WakeMode) -> String {
        switch mode {
        case .off: "mcp.status.off"
        case .system: "mcp.status.system"
        case .display: "mcp.status.display"
        }
    }

    private func format(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

import Combine
import Foundation

public enum AppModelError: LocalizedError {
    case batteryBlocked
    case invalidWakeMode

    public var errorDescription: String? {
        switch self {
        case .batteryBlocked:
            String(localized: "battery.blocked", bundle: .main)
        case .invalidWakeMode:
            String(localized: "error.generic", bundle: .main)
        }
    }
}

public enum AppStatusNotice: Equatable, Sendable {
    case batteryBlocked
    case timerCompleted
    case powerAssertionFailed
    case launchAtLoginFailed

    @MainActor
    func localized(using localization: LocalizationController) -> String {
        let key: String
        switch self {
        case .batteryBlocked:
            key = "battery.blocked"
        case .timerCompleted:
            key = "notification.timerCompleted"
        case .powerAssertionFailed:
            key = "error.powerAssertion"
        case .launchAtLoginFailed:
            key = "error.launchAtLogin"
        }
        return localization.localized(key)
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var mode: WakeMode = .off
    @Published public private(set) var session: WakeSession?
    @Published public private(set) var selectedDuration: SessionDuration
    @Published public private(set) var batteryState: BatteryState
    @Published public private(set) var batteryThreshold: Int
    @Published public private(set) var isBatteryBlocked: Bool
    @Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published public private(set) var statusNotice: AppStatusNotice?
    @Published public private(set) var isBusy = false
    private var requiresPowerAssertionRetry = false

    public var statusMessage: String? {
        statusNotice.map { $0.localized(using: environment.localization) }
    }

    public let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        selectedDuration = environment.settings.selectedDuration
        let initialThreshold = min(
            LowBatteryPolicy.thresholdRange.upperBound,
            max(LowBatteryPolicy.thresholdRange.lowerBound, environment.settings.batteryThreshold)
        )
        batteryThreshold = initialThreshold
        batteryState = environment.battery.currentState
        isBatteryBlocked = LowBatteryPolicy.nextBlockedState(
            currentlyBlocked: false,
            battery: environment.battery.currentState,
            threshold: initialThreshold
        )
        launchAtLoginStatus = environment.launchAtLogin.status

        configurePlatformEvents()
        environment.battery.start()
        environment.lifecycle.start()
    }

    public func setMode(_ requestedMode: WakeMode) throws {
        guard requestedMode != mode || requiresPowerAssertionRetry else { return }
        if requestedMode != .off, isBatteryBlocked {
            let error = AppModelError.batteryBlocked
            statusNotice = .batteryBlocked
            throw error
        }

        let previousMode = mode
        let previousSession = session
        isBusy = true
        defer { isBusy = false }

        do {
            try environment.powerAssertions.transition(to: requestedMode)
        } catch {
            requiresPowerAssertionRetry = true
            commitConfirmedMode(
                environment.powerAssertions.activeMode,
                previousMode: previousMode,
                previousSession: previousSession
            )
            statusNotice = .powerAssertionFailed
            throw error
        }

        requiresPowerAssertionRetry = false
        commitConfirmedMode(
            requestedMode,
            previousMode: previousMode,
            previousSession: previousSession
        )
        statusNotice = nil
        if previousMode == .off, requestedMode != .off {
            environment.notifications.requestAuthorizationIfNeeded()
        }
    }

    public func selectDuration(_ duration: SessionDuration) {
        selectedDuration = duration
        environment.settings.selectedDuration = duration

        guard mode != .off else { return }
        let newSession = WakeSession(mode: mode, startedAt: environment.now(), duration: duration)
        session = newSession
        schedule(newSession)
    }

    public func applySession(mode requestedMode: WakeMode, duration: SessionDuration) throws {
        guard requestedMode != .off else {
            throw AppModelError.invalidWakeMode
        }

        let hadActiveSession = mode != .off
        if requestedMode != mode {
            try setMode(requestedMode)
        }
        if hadActiveSession || duration != selectedDuration {
            selectDuration(duration)
        }
    }

    public func stopSession() throws {
        try setMode(.off)
    }

    public func setBatteryThreshold(_ threshold: Int) {
        let clamped = min(
            LowBatteryPolicy.thresholdRange.upperBound,
            max(LowBatteryPolicy.thresholdRange.lowerBound, threshold)
        )
        batteryThreshold = clamped
        environment.settings.batteryThreshold = clamped
        handleBatteryChange(batteryState)
    }

    public func setLaunchAtLogin(_ enabled: Bool) throws {
        do {
            try environment.launchAtLogin.setEnabled(enabled)
            environment.settings.launchAtLoginRequested = enabled
            launchAtLoginStatus = environment.launchAtLogin.status
            statusNotice = nil
        } catch {
            launchAtLoginStatus = environment.launchAtLogin.status
            statusNotice = .launchAtLoginFailed
            throw error
        }
    }

    public func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = environment.launchAtLogin.status
    }

    public func revalidateDeadline() {
        guard let session, let deadline = session.expiresAt else { return }
        if deadline <= environment.now() {
            stop(reason: .timerCompleted)
        } else {
            schedule(session)
        }
    }

    public func dismissStatus() {
        statusNotice = nil
    }

    public func prepareForTermination() {
        environment.termination.prepare()
        environment.scheduler.cancel()
        environment.battery.stop()
        environment.lifecycle.stop()
        environment.powerAssertions.releaseAll()
        requiresPowerAssertionRetry = false
        mode = .off
        session = nil
        isBusy = false
    }

    private func configurePlatformEvents() {
        environment.battery.onChange = { [weak self] state in
            self?.handleBatteryChange(state)
        }
        environment.lifecycle.onWake = { [weak self] in self?.revalidateDeadline() }
        environment.lifecycle.onClockChange = { [weak self] in self?.revalidateDeadline() }
        environment.lifecycle.onActivation = { [weak self] in
            self?.environment.localization.refreshSystemLocale()
            self?.revalidateDeadline()
            self?.refreshLaunchAtLoginStatus()
        }
        environment.lifecycle.onTermination = { [weak self] in self?.prepareForTermination() }
    }

    private func handleBatteryChange(_ state: BatteryState) {
        batteryState = state
        isBatteryBlocked = LowBatteryPolicy.nextBlockedState(
            currentlyBlocked: isBatteryBlocked,
            battery: state,
            threshold: batteryThreshold
        )

        if isBatteryBlocked, mode != .off {
            stop(reason: .lowBatteryStopped)
        }
    }

    private func commitConfirmedMode(
        _ confirmedMode: WakeMode,
        previousMode: WakeMode,
        previousSession: WakeSession?
    ) {
        mode = confirmedMode
        guard confirmedMode != .off else {
            environment.scheduler.cancel()
            session = nil
            return
        }

        if previousMode == .off || previousSession == nil {
            let newSession = WakeSession(
                mode: confirmedMode,
                startedAt: environment.now(),
                duration: selectedDuration
            )
            session = newSession
            schedule(newSession)
        } else if let previousSession {
            let replacement = WakeSession(
                mode: confirmedMode,
                startedAt: previousSession.startedAt,
                duration: previousSession.duration,
                expiresAt: previousSession.expiresAt
            )
            session = replacement
            schedule(replacement)
        }
    }

    private func schedule(_ session: WakeSession) {
        guard let deadline = session.expiresAt else {
            environment.scheduler.cancel()
            return
        }
        environment.scheduler.schedule(deadline: deadline) { [weak self] in
            self?.revalidateDeadlineAfterScheduledWake(deadline: deadline)
        }
    }

    private func revalidateDeadlineAfterScheduledWake(deadline: Date) {
        guard session?.expiresAt == deadline else { return }
        revalidateDeadline()
    }

    private func stop(reason: AppNotificationEvent) {
        let previousSession = session
        do {
            try environment.powerAssertions.transition(to: .off)
            requiresPowerAssertionRetry = false
            mode = .off
            session = nil
            environment.scheduler.cancel()
            environment.notifications.send(reason)
            if reason == .lowBatteryStopped {
                statusNotice = .batteryBlocked
            } else if reason == .timerCompleted {
                statusNotice = .timerCompleted
            }
        } catch {
            requiresPowerAssertionRetry = true
            reconcileAfterFailedStop(previousSession: previousSession)
            statusNotice = .powerAssertionFailed
        }
    }

    private func reconcileAfterFailedStop(previousSession: WakeSession?) {
        let confirmedMode = environment.powerAssertions.activeMode
        mode = confirmedMode
        environment.scheduler.cancel()

        guard confirmedMode != .off, let previousSession else {
            session = nil
            return
        }
        session = WakeSession(
            mode: confirmedMode,
            startedAt: previousSession.startedAt,
            duration: previousSession.duration,
            expiresAt: previousSession.expiresAt
        )
    }
}

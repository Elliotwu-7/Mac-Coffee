import Foundation
@testable import MacCoffeeCore

enum FakeServiceError: Error {
    case failed
}

final class InMemorySettingsPreferences: SettingsPreferences {
    private var values: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func integer(forKey defaultName: String) -> Int {
        (values[defaultName] as? NSNumber)?.intValue ?? 0
    }

    func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

final class FakeSettingsStore: MCPSettingsStoring {
    var selectedLanguage: SupportedLanguage
    var selectedDuration: SessionDuration
    var batteryThreshold: Int
    var launchAtLoginRequested: Bool
    var notificationAuthorizationRequested: Bool
    var lastAnnouncedUpdateVersion: String?
    var mcpEnabled: Bool

    init(
        selectedLanguage: SupportedLanguage = .system,
        savedDuration: SessionDuration = .hours1,
        batteryThreshold: Int = 15,
        launchAtLoginRequested: Bool = false,
        notificationAuthorizationRequested: Bool = false,
        lastAnnouncedUpdateVersion: String? = nil,
        mcpEnabled: Bool = false
    ) {
        self.selectedLanguage = selectedLanguage
        self.selectedDuration = savedDuration
        self.batteryThreshold = batteryThreshold
        self.launchAtLoginRequested = launchAtLoginRequested
        self.notificationAuthorizationRequested = notificationAuthorizationRequested
        self.lastAnnouncedUpdateVersion = lastAnnouncedUpdateVersion
        self.mcpEnabled = mcpEnabled
    }
}

final class FakeMCPCredentialStore: MCPCredentialStoring {
    var values: [String: Data] = [:]
    private(set) var writeCount = 0
    private(set) var removedKeys: [String] = []

    func data(for key: String) throws -> Data? {
        values[key]
    }

    func setData(_ data: Data, for key: String) throws {
        writeCount += 1
        values[key] = data
    }

    func removeData(for key: String) throws {
        removedKeys.append(key)
        values.removeValue(forKey: key)
    }
}

final class FakePowerAssertionManager: PowerAssertionManaging {
    private(set) var activeMode: WakeMode = .off
    var failNextTransition = false
    var failEveryTransition = false
    var confirmedModeOnFailure: WakeMode?
    var onReleaseAll: (() -> Void)?
    private(set) var transitions: [WakeMode] = []
    private(set) var releaseAllCalled = false

    func transition(to mode: WakeMode) throws {
        transitions.append(mode)
        if failEveryTransition || failNextTransition {
            failNextTransition = false
            if let confirmedModeOnFailure {
                activeMode = confirmedModeOnFailure
                self.confirmedModeOnFailure = nil
            }
            throw FakeServiceError.failed
        }
        activeMode = mode
    }

    func releaseAll() {
        onReleaseAll?()
        releaseAllCalled = true
        activeMode = .off
    }
}

@MainActor
final class FakeBatteryMonitor: BatteryMonitoring {
    private(set) var currentState: BatteryState
    var onChange: ((BatteryState) -> Void)?
    private(set) var started = false

    init(state: BatteryState = .acDesktop) {
        currentState = state
    }

    func start() { started = true }
    func stop() { started = false }

    func emit(_ state: BatteryState) {
        currentState = state
        onChange?(state)
    }
}

@MainActor
final class FakeSessionScheduler: SessionScheduling {
    private(set) var deadline: Date?
    private(set) var scheduleCount = 0
    private var action: (@MainActor @Sendable () -> Void)?
    var hasScheduledAction: Bool { action != nil }

    func schedule(deadline: Date, action: @escaping @MainActor @Sendable () -> Void) {
        scheduleCount += 1
        self.deadline = deadline
        self.action = action
    }

    func cancel() {
        deadline = nil
        action = nil
    }

    func fire() {
        let pending = action
        cancel()
        pending?()
    }
}

@MainActor
final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var status: LaunchAtLoginStatus = .disabled
    var shouldFail = false

    func setEnabled(_ enabled: Bool) throws {
        if shouldFail { throw FakeServiceError.failed }
        status = enabled ? .enabled : .disabled
    }
}

@MainActor
final class FakeNotificationSender: NotificationSending {
    private(set) var authorizationRequests = 0
    private(set) var events: [AppNotificationEvent] = []

    func requestAuthorizationIfNeeded() { authorizationRequests += 1 }
    func send(_ event: AppNotificationEvent) { events.append(event) }
}

@MainActor
final class FakeLifecycleObserver: LifecycleObserving {
    var onWake: (() -> Void)?
    var onClockChange: (() -> Void)?
    var onActivation: (() -> Void)?
    var onTermination: (() -> Void)?
    private(set) var started = false

    func start() { started = true }
    func stop() { started = false }
}

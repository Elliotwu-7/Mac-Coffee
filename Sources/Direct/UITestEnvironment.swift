#if DEBUG
import Foundation
import MacCoffeeCore

@MainActor
enum UITestEnvironment {
    static func makeIfRequested(updater: UpdaterProviding) -> AppEnvironment? {
        guard CommandLine.arguments.contains("--ui-testing-window") else { return nil }
        let percentage = CommandLine.arguments
            .first(where: { $0.hasPrefix("--ui-battery-percentage=") })
            .flatMap { Int($0.split(separator: "=").last ?? "") } ?? 80
        let battery = UITestBatteryMonitor(state: BatteryState(
            powerSource: .battery,
            percentage: percentage,
            hasInternalBattery: true
        ))
        let settings = UITestSettingsStore()
        settings.mcpEnabled = CommandLine.arguments.contains("--ui-mcp-enabled")
        if let threshold = CommandLine.arguments
            .first(where: { $0.hasPrefix("--ui-battery-threshold=") })
            .flatMap({ Int($0.split(separator: "=").last ?? "") }) {
            settings.batteryThreshold = threshold
        }

        return AppEnvironment(
            powerAssertions: UITestPowerAssertionManager(),
            battery: battery,
            scheduler: TaskSessionScheduler(),
            settings: settings,
            launchAtLogin: UITestLaunchAtLoginManager(),
            notifications: UITestNotificationSender(),
            lifecycle: UITestLifecycleObserver(),
            updater: updater
        )
    }
}

private final class UITestSettingsStore: MCPSettingsStoring {
    var selectedLanguage: SupportedLanguage = .system
    var selectedDuration: SessionDuration = .hours1
    var batteryThreshold = 15
    var launchAtLoginRequested = false
    var notificationAuthorizationRequested = false
    var lastAnnouncedUpdateVersion: String?
    var mcpEnabled = false
}

private final class UITestPowerAssertionManager: PowerAssertionManaging {
    private(set) var activeMode: WakeMode = .off
    func transition(to mode: WakeMode) throws { activeMode = mode }
    func releaseAll() { activeMode = .off }
}

@MainActor
private final class UITestBatteryMonitor: BatteryMonitoring {
    private(set) var currentState: BatteryState
    var onChange: ((BatteryState) -> Void)?
    init(state: BatteryState) { currentState = state }
    func start() { onChange?(currentState) }
    func stop() {}
}

@MainActor
private final class UITestLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var status: LaunchAtLoginStatus = .disabled
    func setEnabled(_ enabled: Bool) throws { status = enabled ? .enabled : .disabled }
}

@MainActor
private final class UITestNotificationSender: NotificationSending {
    func requestAuthorizationIfNeeded() {}
    func send(_ event: AppNotificationEvent) {}
}

@MainActor
private final class UITestLifecycleObserver: LifecycleObserving {
    var onWake: (() -> Void)?
    var onClockChange: (() -> Void)?
    var onActivation: (() -> Void)?
    var onTermination: (() -> Void)?
    func start() {}
    func stop() {}
}
#endif

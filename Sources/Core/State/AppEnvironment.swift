import Foundation

@MainActor
public final class TerminationPreparationCoordinator {
    public typealias Action = @MainActor () -> Void

    private var actions: [Action] = []
    private var didPrepare = false

    public init() {}

    public func register(_ action: @escaping Action) {
        if didPrepare {
            action()
        } else {
            actions.append(action)
        }
    }

    public func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        let pending = actions
        actions.removeAll()
        pending.forEach { $0() }
    }
}

@MainActor
public struct AppEnvironment {
    public let powerAssertions: PowerAssertionManaging
    public let battery: BatteryMonitoring
    public let scheduler: SessionScheduling
    public let settings: SettingsStoring
    public let localization: LocalizationController
    public let launchAtLogin: LaunchAtLoginManaging
    public let notifications: NotificationSending
    public let lifecycle: LifecycleObserving
    public let termination: TerminationPreparationCoordinator
    public let updater: UpdaterProviding?
    public let now: () -> Date

    public init(
        powerAssertions: PowerAssertionManaging,
        battery: BatteryMonitoring,
        scheduler: SessionScheduling,
        settings: SettingsStoring,
        launchAtLogin: LaunchAtLoginManaging,
        notifications: NotificationSending,
        lifecycle: LifecycleObserving,
        termination: TerminationPreparationCoordinator = TerminationPreparationCoordinator(),
        localization: LocalizationController? = nil,
        updater: UpdaterProviding? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.powerAssertions = powerAssertions
        self.battery = battery
        self.scheduler = scheduler
        self.settings = settings
        self.localization = localization ?? LocalizationController(settings: settings)
        self.launchAtLogin = launchAtLogin
        self.notifications = notifications
        self.lifecycle = lifecycle
        self.termination = termination
        self.updater = updater
        self.now = now
    }

    public static func live(updater: UpdaterProviding? = nil) -> AppEnvironment {
        let settings = UserDefaultsSettingsStore()
        let localization = LocalizationController(settings: settings)
        return AppEnvironment(
            powerAssertions: IOKitPowerAssertionManager(),
            battery: IOKitBatteryMonitor(),
            scheduler: TaskSessionScheduler(),
            settings: settings,
            launchAtLogin: SMAppLaunchAtLoginManager(),
            notifications: UserNotificationSender(settings: settings, localization: localization),
            lifecycle: AppLifecycleObserver(),
            localization: localization,
            updater: updater
        )
    }
}

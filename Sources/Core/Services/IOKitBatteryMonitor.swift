import CoreFoundation
import Foundation
import IOKit.ps

@MainActor
public final class IOKitBatteryMonitor: BatteryMonitoring {
    public private(set) var currentState: BatteryState = .acDesktop
    public var onChange: ((BatteryState) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    public init() {}

    public func start() {
        guard runLoopSource == nil else { return }
        refreshAndPublish()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanagedSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let monitor = Unmanaged<IOKitBatteryMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.refreshAndPublish()
            }
        }, context) else {
            return
        }

        let source = unmanagedSource.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    public func stop() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        self.runLoopSource = nil
    }

    nonisolated static func parse(description: [String: Any]) -> BatteryState {
        let isInternal = description[kIOPSTransportTypeKey] as? String == kIOPSInternalType
        let stateValue = description[kIOPSPowerSourceStateKey] as? String
        let powerSource: PowerSource
        switch stateValue {
        case kIOPSBatteryPowerValue:
            powerSource = .battery
        case kIOPSACPowerValue:
            powerSource = .ac
        default:
            powerSource = .unknown
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int
        let maximum = description[kIOPSMaxCapacityKey] as? Int
        let percentage: Int?
        if let current, let maximum, maximum > 0 {
            percentage = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
        } else {
            percentage = nil
        }

        return BatteryState(
            powerSource: powerSource,
            percentage: percentage,
            hasInternalBattery: isInternal
        )
    }

    private func refreshAndPublish() {
        let newState = Self.readCurrentState(previous: currentState)
        currentState = newState
        onChange?(newState)
    }

    nonisolated static func stateAfterReadFailure(previous: BatteryState) -> BatteryState {
        BatteryState(
            powerSource: .unknown,
            percentage: nil,
            hasInternalBattery: previous.hasInternalBattery
        )
    }

    private static func readCurrentState(previous: BatteryState) -> BatteryState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return stateAfterReadFailure(previous: previous)
        }

        for source in sourceList {
            guard let rawDescription = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue(),
                  let description = rawDescription as? [String: Any]
            else {
                continue
            }
            let parsed = parse(description: description)
            if parsed.hasInternalBattery {
                return parsed
            }
        }

        return .acDesktop
    }
}

import Foundation
import IOKit.pwr_mgt
import OSLog

public enum PowerAssertionError: LocalizedError, Equatable {
    case createFailed(IOReturn)
    case releaseFailed(IOPMAssertionID, IOReturn)

    public var errorDescription: String? {
        String(localized: "error.powerAssertion", bundle: .main)
    }
}

protocol PowerAssertionDriving: AnyObject {
    func create(type: CFString, name: CFString) throws -> IOPMAssertionID
    func release(id: IOPMAssertionID) throws
}

private final class SystemPowerAssertionDriver: PowerAssertionDriving {
    private let logger = Logger(subsystem: "com.rekurt.maccoffee", category: "PowerAssertion")

    func create(type: CFString, name: CFString) throws -> IOPMAssertionID {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            logger.error("IOPMAssertionCreateWithName failed with IOKit code \(result, privacy: .public)")
            throw PowerAssertionError.createFailed(result)
        }
        return assertionID
    }

    func release(id: IOPMAssertionID) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else {
            logger.error(
                "IOPMAssertionRelease failed for ID \(id, privacy: .public), IOKit code \(result, privacy: .public)"
            )
            throw PowerAssertionError.releaseFailed(id, result)
        }
    }
}

public final class IOKitPowerAssertionManager: PowerAssertionManaging {
    private struct ActiveAssertion {
        let mode: WakeMode
        let id: IOPMAssertionID
    }

    private static let assertionName = "Mac Coffee active wake session"

    private let driver: PowerAssertionDriving
    private var activeAssertion: ActiveAssertion?
    private var pendingReleaseAssertions: [ActiveAssertion] = []

    public var activeMode: WakeMode {
        activeAssertion?.mode ?? pendingReleaseAssertions.first?.mode ?? .off
    }

    public convenience init() {
        self.init(driver: SystemPowerAssertionDriver())
    }

    init(driver: PowerAssertionDriving) {
        self.driver = driver
    }

    deinit {
        releaseAll()
    }

    public func transition(to mode: WakeMode) throws {
        if mode == .off {
            try transitionToOff()
            return
        }

        try releasePendingAssertions()
        guard mode != activeAssertion?.mode else { return }

        let newID = try driver.create(
            type: assertionType(for: mode),
            name: Self.assertionName as CFString
        )
        let previous = activeAssertion
        activeAssertion = ActiveAssertion(mode: mode, id: newID)

        guard let previous else { return }
        do {
            try driver.release(id: previous.id)
        } catch {
            trackForRelease(previous)
            throw error
        }
    }

    public func releaseAll() {
        _ = releaseTrackedAssertions()
    }

    private func transitionToOff() throws {
        if let firstError = releaseTrackedAssertions() {
            throw firstError
        }
    }

    private func releasePendingAssertions() throws {
        var failures: [ActiveAssertion] = []
        var firstError: Error?

        for assertion in pendingReleaseAssertions {
            do {
                try driver.release(id: assertion.id)
            } catch {
                failures.append(assertion)
                firstError = firstError ?? error
            }
        }
        pendingReleaseAssertions = failures

        if let firstError {
            throw firstError
        }
    }

    private func releaseTrackedAssertions() -> Error? {
        var assertions = pendingReleaseAssertions
        if let activeAssertion,
           !assertions.contains(where: { $0.id == activeAssertion.id }) {
            assertions.append(activeAssertion)
        }

        var pendingFailures: [ActiveAssertion] = []
        var firstError: Error?
        for assertion in assertions {
            do {
                try driver.release(id: assertion.id)
                if activeAssertion?.id == assertion.id {
                    activeAssertion = nil
                }
            } catch {
                firstError = firstError ?? error
                if activeAssertion?.id != assertion.id {
                    pendingFailures.append(assertion)
                }
            }
        }
        pendingReleaseAssertions = pendingFailures
        return firstError
    }

    private func assertionType(for mode: WakeMode) -> CFString {
        switch mode {
        case .system:
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        case .display:
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        case .off:
            preconditionFailure("Off has no assertion type")
        }
    }

    private func trackForRelease(_ assertion: ActiveAssertion) {
        if !pendingReleaseAssertions.contains(where: { $0.id == assertion.id }) {
            pendingReleaseAssertions.append(assertion)
        }
    }
}

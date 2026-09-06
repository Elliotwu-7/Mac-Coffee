@preconcurrency import AppKit
import Foundation

@MainActor
public final class AppLifecycleObserver: LifecycleObserving {
    public var onWake: (() -> Void)?
    public var onClockChange: (() -> Void)?
    public var onActivation: (() -> Void)?
    public var onTermination: (() -> Void)?

    private var defaultTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        guard defaultTokens.isEmpty, workspaceTokens.isEmpty else { return }

        let center = NotificationCenter.default
        defaultTokens.append(center.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClockChange?() }
        })
        defaultTokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onActivation?() }
        })
        defaultTokens.append(center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTermination?() }
        })

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        })
    }

    public func stop() {
        let center = NotificationCenter.default
        defaultTokens.forEach(center.removeObserver)
        defaultTokens.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspaceCenter.removeObserver)
        workspaceTokens.removeAll()
    }
}

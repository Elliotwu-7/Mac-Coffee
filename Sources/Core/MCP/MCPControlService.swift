import Foundation

@MainActor
public final class MCPControlService: MCPControlServicing {
    private let model: AppModel
    private let snapshotFactory: MCPSnapshotFactory
    private let requestCache: MCPRequestCache
    public let activityStore: MCPActivityStore
    public let statusPublisher: MCPStatusPublisher

    public init(
        model: AppModel,
        activityStore: MCPActivityStore? = nil,
        requestCache: MCPRequestCache? = nil,
        debounceScheduler: MCPDebounceScheduling? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.model = model
        let snapshotFactory = MCPSnapshotFactory(
            localization: model.environment.localization,
            now: now
        )
        let activityStore = activityStore ?? MCPActivityStore(now: now)
        let requestCache = requestCache ?? MCPRequestCache()
        self.snapshotFactory = snapshotFactory
        self.activityStore = activityStore
        self.requestCache = requestCache
        statusPublisher = MCPStatusPublisher(
            model: model,
            snapshotFactory: snapshotFactory,
            activityStore: activityStore,
            debounceScheduler: debounceScheduler ?? MCPTaskDebounceScheduler()
        )
    }

    public func execute(
        _ command: MCPCommand,
        client: MCPClientContext
    ) throws -> MCPEnvelope<MCPStatusSnapshot> {
        do {
            _ = try MCPCommand.validatedOptionalRequestID(command.requestID)
        } catch let error as MCPServiceError {
            activityStore.record(
                client: client,
                command: command,
                outcome: .failure(error.code),
                replayed: false
            )
            throw error
        }

        if let requestID = command.requestID {
            do {
                if let cached = try requestCache.result(
                    clientIdentifier: client.identifier,
                    requestID: requestID,
                    command: command
                ) {
                    activityStore.record(
                        client: client,
                        command: command,
                        outcome: cached.activityOutcome,
                        replayed: true
                    )
                    return try resolve(cached)
                }
            } catch let error as MCPServiceError {
                activityStore.record(
                    client: client,
                    command: command,
                    outcome: .failure(error.code),
                    replayed: false
                )
                throw error
            }
        }

        let result = perform(command)
        if let requestID = command.requestID, case .success = result {
            requestCache.insert(
                result,
                command: command,
                clientIdentifier: client.identifier,
                requestID: requestID
            )
        }
        activityStore.record(
            client: client,
            command: command,
            outcome: result.activityOutcome,
            replayed: false
        )
        return try resolve(result)
    }

    public func readStatus(
        client: MCPClientContext
    ) -> MCPEnvelope<MCPStatusSnapshot> {
        activityStore.record(
            client: client,
            action: .readStatus,
            outcome: .success,
            replayed: false
        )
        return snapshotFactory.makeStatus(from: model)
    }

    public func readActivity(
        client: MCPClientContext
    ) -> MCPActivitySnapshot {
        activityStore.record(
            client: client,
            action: .readActivity,
            outcome: .success,
            replayed: false
        )
        return MCPActivitySnapshot(entries: activityStore.entries)
    }

    private func perform(_ command: MCPCommand) -> MCPCachedCommandResult {
        do {
            return .success(try executeUncached(command))
        } catch let error as MCPServiceError {
            return .failure(error)
        } catch {
            return .failure(MCPServiceError(code: .internalError))
        }
    }

    private func executeUncached(
        _ command: MCPCommand
    ) throws -> MCPEnvelope<MCPStatusSnapshot> {
        if model.isBusy, command.isMutating {
            throw MCPServiceError(code: .appBusy)
        }

        do {
            switch command {
            case .getStatus:
                break

            case let .setSession(mode, duration, _):
                guard mode != .off else {
                    throw MCPServiceError.invalidArgument(field: "mode")
                }
                try model.applySession(mode: mode, duration: duration)

            case .stopSession:
                try model.stopSession()

            case let .setBatteryThreshold(percent, _):
                guard LowBatteryPolicy.thresholdRange.contains(percent) else {
                    throw MCPServiceError.invalidArgument(field: "percent")
                }
                model.setBatteryThreshold(percent)

            case let .setLaunchAtLogin(enabled, _):
                try model.setLaunchAtLogin(enabled)

            case let .setLanguage(language, _):
                model.environment.localization.select(language)
            }
        } catch let error as MCPServiceError {
            throw error
        } catch let error as AppModelError {
            switch error {
            case .batteryBlocked:
                throw MCPServiceError(code: .batteryBlocked)
            case .invalidWakeMode:
                throw MCPServiceError.invalidArgument(field: "mode")
            }
        } catch {
            if model.statusNotice == .powerAssertionFailed {
                throw MCPServiceError(code: .assertionFailed)
            }
            throw MCPServiceError(code: .internalError)
        }

        return snapshotFactory.makeStatus(
            from: model,
            requestID: command.requestID
        )
    }

    private func resolve(
        _ result: MCPCachedCommandResult
    ) throws -> MCPEnvelope<MCPStatusSnapshot> {
        switch result {
        case let .success(snapshot):
            snapshot
        case let .failure(error):
            throw error
        }
    }
}

private extension MCPCommand {
    var isMutating: Bool {
        if case .getStatus = self { return false }
        return true
    }
}

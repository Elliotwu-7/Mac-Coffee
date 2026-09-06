import Foundation
import XCTest
@testable import MacCoffeeCore

@MainActor
final class MCPRuntimeBehaviorTests: XCTestCase {
    func testActivityStoreKeepsTheNewestTwoHundredEntriesInFIFOOrder() {
        let store = MCPActivityStore(
            capacity: 200,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let client = MCPClientContext(identifier: "client-1", displayName: "Codex")

        for index in 1 ... 201 {
            store.record(
                client: client,
                action: .getStatus,
                input: .empty,
                requestID: "request-\(index)",
                outcome: .success,
                replayed: false
            )
        }

        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(store.entries.first?.sequence, 2)
        XCTAssertEqual(store.entries.first?.requestID, "request-2")
        XCTAssertEqual(store.entries.last?.sequence, 201)
        XCTAssertEqual(store.entries.last?.requestID, "request-201")
    }

    func testActivityIsCurrentRunOnlyAndSerializesOnlyTypedSanitizedInput() throws {
        let store = MCPActivityStore(capacity: 200)
        let client = MCPClientContext(identifier: "client-1", displayName: "Claude Desktop")

        store.record(
            client: client,
            command: .setSession(
                mode: .display,
                duration: .hours4,
                requestID: "request-1"
            ),
            outcome: .failure(.assertionFailed),
            replayed: false
        )

        let event = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(
            event.input,
            MCPActivityInputSummary(mode: .display, duration: .hours4)
        )
        let encoded = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for forbiddenField in ["privateKey", "signature", "nonce", "rawConfig", "internalError"] {
            XCTAssertFalse(json.contains(forbiddenField))
        }

        let replacementRun = MCPActivityStore(capacity: 200)
        XCTAssertTrue(replacementRun.entries.isEmpty)
    }

    func testRequestCacheIsBoundedFIFOAndCurrentRunOnly() throws {
        let cache = MCPRequestCache(capacity: 2)
        let command = MCPCommand.stopSession(requestID: "request")
        let first = MCPCachedCommandResult.failure(MCPServiceError(code: .appBusy))
        let second = MCPCachedCommandResult.failure(MCPServiceError(code: .batteryBlocked))
        let third = MCPCachedCommandResult.failure(MCPServiceError(code: .assertionFailed))

        cache.insert(first, command: command, clientIdentifier: "client", requestID: "one")
        cache.insert(second, command: command, clientIdentifier: "client", requestID: "two")
        cache.insert(third, command: command, clientIdentifier: "client", requestID: "three")

        XCTAssertNil(try cache.result(clientIdentifier: "client", requestID: "one", command: command))
        XCTAssertEqual(
            try cache.result(clientIdentifier: "client", requestID: "two", command: command),
            second
        )
        XCTAssertEqual(
            try cache.result(clientIdentifier: "client", requestID: "three", command: command),
            third
        )
        XCTAssertNil(try MCPRequestCache(capacity: 2).result(
            clientIdentifier: "client",
            requestID: "three",
            command: command
        ))
    }

    func testDuplicateRequestIDReturnsOriginalResultWithoutRepeatingSideEffects() throws {
        let harness = MCPRuntimeHarness()
        let first = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: "same-request"),
            client: harness.client
        )

        let replay = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: "same-request"),
            client: harness.client
        )

        XCTAssertEqual(replay, first)
        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertEqual(harness.model.selectedDuration, .hours1)
        XCTAssertEqual(harness.power.transitions, [.system])
        XCTAssertEqual(harness.activity.entries.count, 2)
        XCTAssertFalse(harness.activity.entries[0].replayed)
        XCTAssertTrue(harness.activity.entries[1].replayed)
    }

    func testReusedRequestIDWithDifferentCommandIsRejected() throws {
        let harness = MCPRuntimeHarness()
        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: "reused-request"),
            client: harness.client
        )

        XCTAssertThrowsError(try harness.service.execute(
            .stopSession(requestID: "reused-request"),
            client: harness.client
        )) { error in
            XCTAssertEqual((error as? MCPServiceError)?.code, .invalidArgument)
            XCTAssertEqual((error as? MCPServiceError)?.field, "requestId")
        }

        XCTAssertEqual(harness.model.mode, .system)
        XCTAssertEqual(harness.power.transitions, [.system])
        XCTAssertFalse(harness.activity.entries.last?.replayed == true)
    }

    func testDuplicateFailedRequestRetriesUntilItSucceeds() throws {
        let harness = MCPRuntimeHarness()
        harness.power.failNextTransition = true
        let command = MCPCommand.setSession(
            mode: .display,
            duration: .hours1,
            requestID: "failed-request"
        )

        assertError(.assertionFailed) {
            _ = try harness.service.execute(command, client: harness.client)
        }
        let retry = try harness.service.execute(command, client: harness.client)

        XCTAssertEqual(retry.data.mode, .display)
        XCTAssertEqual(harness.power.transitions, [.display, .display])
        XCTAssertFalse(harness.activity.entries.last?.replayed == true)
    }

    func testSameRequestIDFromAnotherClientIsNotAReplay() throws {
        let harness = MCPRuntimeHarness()
        let otherClient = MCPClientContext(identifier: "client-2", displayName: "Claude Desktop")

        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: "shared-id"),
            client: harness.client
        )
        let result = try harness.service.execute(
            .setSession(mode: .display, duration: .hours1, requestID: "shared-id"),
            client: otherClient
        )

        XCTAssertEqual(result.data.mode, .display)
        XCTAssertEqual(harness.power.transitions, [.system, .display])
        XCTAssertFalse(harness.activity.entries.last?.replayed == true)
    }

    func testDistinctRequestIDsExecuteSeparately() throws {
        let harness = MCPRuntimeHarness()

        _ = try harness.service.execute(
            .setSession(mode: .system, duration: .hours1, requestID: "request-1"),
            client: harness.client
        )
        _ = try harness.service.execute(
            .setSession(mode: .display, duration: .hours1, requestID: "request-2"),
            client: harness.client
        )

        XCTAssertEqual(harness.power.transitions, [.system, .display])
    }

    func testStatusPublisherCoalescesBurstsAndPublishesFinalState() {
        let harness = MCPRuntimeHarness()
        var snapshots: [MCPEnvelope<MCPStatusSnapshot>] = []
        _ = harness.service.statusPublisher.subscribe(client: harness.client) {
            snapshots.append($0)
        }

        harness.model.setBatteryThreshold(16)
        harness.model.setBatteryThreshold(17)
        harness.model.setBatteryThreshold(18)

        XCTAssertGreaterThan(harness.debouncer.scheduleCount, 1)
        XCTAssertTrue(snapshots.isEmpty)
        harness.debouncer.fire()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].data.battery.threshold, 18)
    }

    func testStatusSequencesIncreaseAcrossResponsesAndUIOriginatedEvents() throws {
        let harness = MCPRuntimeHarness()
        var snapshots: [MCPEnvelope<MCPStatusSnapshot>] = []
        _ = harness.service.statusPublisher.subscribe(client: harness.client) {
            snapshots.append($0)
        }

        let response = try harness.service.execute(
            .setBatteryThreshold(percent: 16, requestID: "threshold-1"),
            client: harness.client
        )
        harness.debouncer.fire()
        try harness.model.setMode(.system)
        harness.debouncer.fire()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertGreaterThan(snapshots[0].sequence, response.sequence)
        XCTAssertGreaterThan(snapshots[1].sequence, snapshots[0].sequence)
        XCTAssertEqual(snapshots[1].data.mode, .system)
    }

    func testCancellingSubscriptionPreventsLaterDelivery() {
        let harness = MCPRuntimeHarness()
        var snapshots: [MCPEnvelope<MCPStatusSnapshot>] = []
        let token = harness.service.statusPublisher.subscribe(client: harness.client) {
            snapshots.append($0)
        }

        harness.service.statusPublisher.cancel(token)
        harness.model.setBatteryThreshold(20)
        harness.debouncer.fire()

        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(
            harness.activity.entries.suffix(2).map(\.action),
            [.subscribeStatus, .unsubscribeStatus]
        )
    }

    private func assertError(
        _ expected: MCPErrorCode,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? MCPServiceError)?.code, expected, file: file, line: line)
        }
    }
}

@MainActor
private final class MCPRuntimeHarness {
    let client = MCPClientContext(identifier: "client-1", displayName: "Codex")
    let clock = MCPRuntimeTestClock(now: Date(timeIntervalSince1970: 1_000))
    let settings = FakeSettingsStore(savedDuration: .hours1)
    let power = FakePowerAssertionManager()
    let battery = FakeBatteryMonitor()
    let scheduler = FakeSessionScheduler()
    let launchAtLogin = FakeLaunchAtLoginManager()
    let localization: LocalizationController
    let model: AppModel
    let activity: MCPActivityStore
    let cache: MCPRequestCache
    let debouncer = ManualMCPDebounceScheduler()
    let service: MCPControlService

    init() {
        localization = LocalizationController(
            settings: settings,
            systemLocale: { Locale(identifier: "en-US") }
        )
        model = AppModel(environment: AppEnvironment(
            powerAssertions: power,
            battery: battery,
            scheduler: scheduler,
            settings: settings,
            launchAtLogin: launchAtLogin,
            notifications: FakeNotificationSender(),
            lifecycle: FakeLifecycleObserver(),
            localization: localization,
            now: { [clock] in clock.now }
        ))
        activity = MCPActivityStore(now: { [clock] in clock.now })
        cache = MCPRequestCache()
        service = MCPControlService(
            model: model,
            activityStore: activity,
            requestCache: cache,
            debounceScheduler: debouncer,
            now: { [clock] in clock.now }
        )
    }
}

@MainActor
private final class ManualMCPDebounceScheduler: MCPDebounceScheduling {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduleCount = 0

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduleCount += 1
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let pending = action
        action = nil
        pending?()
    }
}

private final class MCPRuntimeTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

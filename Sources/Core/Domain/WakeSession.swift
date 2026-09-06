import Foundation

public struct WakeSession: Equatable, Sendable {
    public let mode: WakeMode
    public let startedAt: Date
    public let duration: SessionDuration
    public let expiresAt: Date?

    public init(mode: WakeMode, startedAt: Date, duration: SessionDuration) {
        self.mode = mode
        self.startedAt = startedAt
        self.duration = duration
        self.expiresAt = duration.interval.map { startedAt.addingTimeInterval($0) }
    }

    public init(
        mode: WakeMode,
        startedAt: Date,
        duration: SessionDuration,
        expiresAt: Date?
    ) {
        self.mode = mode
        self.startedAt = startedAt
        self.duration = duration
        self.expiresAt = expiresAt
    }
}

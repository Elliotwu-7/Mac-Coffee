import SwiftUI

@MainActor
public struct CountdownFormatter {
    private let localization: LocalizationController

    public init(localization: LocalizationController) {
        self.localization = localization
    }

    public func remainingText(until deadline: Date, now: Date) -> String {
        let total = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        let formatted: String
        if total >= 3_600 {
            formatted = localization.format(
                "countdown.hoursMinutes",
                arguments: total / 3_600,
                (total % 3_600) / 60
            )
        } else if total > 60 {
            formatted = localization.format("countdown.minutes", arguments: total / 60)
        } else {
            formatted = localization.format("countdown.seconds", arguments: total)
        }
        return localization.format("status.remaining", arguments: formatted)
    }
}

public struct CountdownText: View {
    private let deadline: Date?
    @ObservedObject private var localization: LocalizationController
    @State private var now = Date()

    public init(deadline: Date?, localization: LocalizationController) {
        self.deadline = deadline
        _localization = ObservedObject(wrappedValue: localization)
    }

    public var body: some View {
        Text(verbatim: displayText)
        .monospacedDigit()
        .accessibilityIdentifier("maccoffee.session.countdown")
        .accessibilityLabel(Text(verbatim: displayText))
        .task(id: deadline) {
            guard let deadline else { return }
            while !Task.isCancelled {
                now = Date()
                let remaining = deadline.timeIntervalSince(now)
                if remaining <= 0 { return }
                let cadence = remaining <= 60 ? 1.0 : min(60.0, remaining - 60.0)
                try? await Task<Never, Never>.sleep(for: .seconds(max(1, cadence)))
            }
        }
    }

    private var displayText: String {
        guard let deadline else {
            return localization.localized("duration.indefinite.long")
        }
        return CountdownFormatter(localization: localization).remainingText(until: deadline, now: now)
    }
}

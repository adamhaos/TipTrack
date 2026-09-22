import Foundation

nonisolated enum TipPeriod: String, CaseIterable, Sendable {
    case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, lastShift, allTime
}

nonisolated enum TipTrackSiriValidationError: Error, LocalizedError {
    case invalidAmount, emptyEntry, invalidDate

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter finite, nonnegative tip amounts, tip-out, hours, and hourly rate."
        case .emptyEntry: "Enter tips or hours before saving a shift."
        case .invalidDate: "Choose a valid shift date."
        }
    }
}

/// Shared calculations for Siri, independent of the live database and system dialogs.
nonisolated enum TipTrackSiriRules {
    static func periodDescription(_ period: TipPeriod, now: Date, calendar: Calendar) -> String {
        switch period {
        case .today: return "today"
        case .yesterday:
            guard let date = calendar.date(byAdding: .day, value: -1, to: now) else { return "yesterday" }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "yesterday (\(formatter.string(from: date)))"
        case .thisWeek: return "this week"
        case .lastWeek: return "last week"
        case .thisMonth: return "this month"
        case .lastMonth: return "last month"
        case .thisYear: return "this year"
        case .lastShift: return "on your last logged shift"
        case .allTime: return "across all time"
        }
    }

    static func inputAmount(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let normalized = trimmed.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func requiresAuthentication(appLock: Bool, earningsPrivacy: Bool,
        revealsEarnings: Bool, unlocked: Bool) -> Bool {
        (appLock || (earningsPrivacy && revealsEarnings)) && !unlocked
    }

    static func validate(credit: Double, cash: Double, tipOut: Double,
        hours: Double?, hourlyRate: Double?, date: Date) throws {
        let values = [credit, cash, tipOut, hours ?? 0, hourlyRate ?? 0]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              (credit + cash - tipOut + (hours ?? 0) * (hourlyRate ?? 0)).isFinite else {
            throw TipTrackSiriValidationError.invalidAmount
        }
        guard credit > 0 || cash > 0 || (hours ?? 0) > 0 else {
            throw TipTrackSiriValidationError.emptyEntry
        }
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw TipTrackSiriValidationError.invalidDate
        }
    }

    static func interval(for period: TipPeriod, now: Date, calendar: Calendar) -> DateInterval? {
        switch period {
        case .lastShift, .allTime: return nil
        case .today: return calendar.dateInterval(of: .day, for: now)
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: now)
                .flatMap { calendar.dateInterval(of: .day, for: $0) }
        case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: now)
        case .lastWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now)
                .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        case .thisMonth: return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
                .flatMap { calendar.dateInterval(of: .month, for: $0) }
        case .thisYear: return calendar.dateInterval(of: .year, for: now)
        }
    }

    static func hourlyAverage(earningsAndHours: [(earnings: Double, hours: Double?)]) -> Double? {
        let timed = earningsAndHours.filter { ($0.hours ?? 0) > 0 }
        let hours = timed.reduce(0) { $0 + ($1.hours ?? 0) }
        return hours > 0 ? timed.reduce(0) { $0 + $1.earnings } / hours : nil
    }
}

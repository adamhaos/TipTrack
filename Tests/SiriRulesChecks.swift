import Foundation

// Compile with TipTrack/TipTrackSiriRules.swift. This never opens the app database.
@main
struct SiriRulesChecks {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 22))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let week = TipTrackSiriRules.interval(for: .thisWeek, now: now, calendar: calendar)!
        precondition(week.start == monday)
        precondition(calendar.component(.day, from: week.end) == 5)
        let previousWeek = TipTrackSiriRules.interval(for: .lastWeek, now: now, calendar: calendar)!
        precondition(previousWeek.end == week.start)
        let month = TipTrackSiriRules.interval(for: .thisMonth, now: now, calendar: calendar)!
        let previousMonth = TipTrackSiriRules.interval(for: .lastMonth, now: now, calendar: calendar)!
        precondition(previousMonth.end == month.start)
        precondition(calendar.component(.month, from: previousMonth.start) == 9)
        let today = TipTrackSiriRules.interval(for: .today, now: now, calendar: calendar)!
        let yesterday = TipTrackSiriRules.interval(for: .yesterday, now: now, calendar: calendar)!
        precondition(yesterday.end == today.start)
        precondition(TipTrackSiriRules.interval(for: .lastShift, now: now, calendar: calendar) == nil)
        precondition(TipTrackSiriRules.interval(for: .allTime, now: now, calendar: calendar) == nil)
        let year = TipTrackSiriRules.interval(for: .thisYear, now: now, calendar: calendar)!
        precondition(calendar.component(.month, from: year.start) == 1)
        calendar.firstWeekday = 1
        let sundayWeek = TipTrackSiriRules.interval(for: .thisWeek, now: now, calendar: calendar)!
        precondition(calendar.component(.weekday, from: sundayWeek.start) == 1)

        let dstDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let dstDay = TipTrackSiriRules.interval(for: .today, now: dstDate, calendar: calendar)!
        precondition(dstDay.duration == 23 * 3600)
        // A late-night follow-up uses the previous local day, including DST days.
        for (month, day, duration) in [(3, 9, 23.0), (11, 2, 25.0)] {
            let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 0, minute: 1))!
            let priorDay = TipTrackSiriRules.interval(for: .yesterday, now: afterMidnight, calendar: calendar)!
            precondition(priorDay.end == calendar.startOfDay(for: afterMidnight))
            precondition(priorDay.duration == duration * 3600)
            precondition(priorDay.start <= priorDay.end.addingTimeInterval(-1))
        }
        precondition(TipTrackSiriRules.hourlyAverage(earningsAndHours: [(100, 5), (900, nil), (50, 0)]) == 20)
        precondition(TipTrackSiriRules.hourlyAverage(earningsAndHours: [(100, 5), (100, 10)]) == 200.0 / 15)
        precondition(TipTrackSiriRules.hourlyAverage(earningsAndHours: [(100, nil)]) == nil)
        precondition(TipTrackSiriRules.requiresAuthentication(appLock: true, earningsPrivacy: false, revealsEarnings: false, unlocked: false))
        precondition(TipTrackSiriRules.requiresAuthentication(appLock: false, earningsPrivacy: true, revealsEarnings: true, unlocked: false))
        precondition(!TipTrackSiriRules.requiresAuthentication(appLock: false, earningsPrivacy: true, revealsEarnings: false, unlocked: false))
        precondition(!TipTrackSiriRules.requiresAuthentication(appLock: true, earningsPrivacy: true, revealsEarnings: true, unlocked: true))
        precondition(!TipTrackSiriRules.requiresAuthentication(appLock: false, earningsPrivacy: false, revealsEarnings: true, unlocked: false))

        try TipTrackSiriRules.validate(credit: 100, cash: 20, tipOut: 5, hours: 6, hourlyRate: 15, date: now)
        try TipTrackSiriRules.validate(credit: 0, cash: 0, tipOut: 0, hours: 6, hourlyRate: 15, date: now)
        try TipTrackSiriRules.validate(credit: 0, cash: 10, tipOut: 20, hours: nil, hourlyRate: nil, date: now)
        for bad in [Double.nan, Double.infinity, -1] {
            rejects { try TipTrackSiriRules.validate(credit: bad, cash: 0, tipOut: 0, hours: nil, hourlyRate: nil, date: now) }
            rejects { try TipTrackSiriRules.validate(credit: 10, cash: 0, tipOut: 0, hours: bad, hourlyRate: nil, date: now) }
            rejects { try TipTrackSiriRules.validate(credit: 10, cash: 0, tipOut: bad, hours: 1, hourlyRate: nil, date: now) }
            rejects { try TipTrackSiriRules.validate(credit: 10, cash: 0, tipOut: 0, hours: 1, hourlyRate: bad, date: now) }
        }
        rejects { try TipTrackSiriRules.validate(credit: 0, cash: 0, tipOut: 0, hours: nil, hourlyRate: nil, date: now) }
        rejects { try TipTrackSiriRules.validate(credit: 1, cash: 0, tipOut: 0, hours: .greatestFiniteMagnitude, hourlyRate: 2, date: now) }
        print("Siri checks passed: periods, week preferences, DST, hourly averages, privacy gates, and input validation.")
    }

    private static func rejects(_ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("An invalid Siri entry was accepted")
        } catch { }
    }
}

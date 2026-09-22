import Foundation

@main
struct EarningsInsightsChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        let jobA = UUID(), jobB = UUID()
        func date(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        func record(_ date: Date, _ earnings: Double, _ hours: Double?, _ job: UUID = jobA) -> EarningsRecord {
            EarningsRecord(id: UUID(), date: date, earnings: earnings, hours: hours, jobID: job, jobName: job == jobA ? "A" : "B")
        }
        let ranks = EarningsInsights.rankings([
            record(date(10, 5), 100, 2), record(date(10, 6), 100, 8),
            record(date(10, 7), 999, nil), record(date(10, 8), 150, 5, jobB)
        ], byWeekday: false, calendar: calendar)
        precondition(ranks.count == 2 && ranks[0].name == "B" && ranks[0].hourly == 30)
        precondition(ranks[1].hourly == 20 && ranks[1].count == 2)
        precondition(EarningsInsights.rankings([record(date(10, 7), 999, nil)], byWeekday: true, calendar: calendar).isEmpty)
        let now = date(10, 7) // Wednesday; Thursday earnings must not enter the comparison.
        let records = [record(date(10, 5), 300, nil), record(date(10, 8), 999, nil),
            record(date(9, 28), 100, nil), record(date(10, 1), 900, nil),
            record(date(9, 21), 200, nil), record(date(9, 24), 900, nil),
            record(date(9, 1), 800, nil)]
        let comparison = EarningsInsights.comparison(records, now: now, calendar: calendar)!
        precondition(comparison.current == 300 && comparison.usual == 150 && comparison.weeks == 2)
        precondition(EarningsInsights.comparison([record(date(9, 28), 100, nil)], now: now, calendar: calendar) == nil)
        // The week crossing DST must still compare calendar days, not 24-hour offsets.
        let dst = EarningsInsights.comparison([
            record(date(11, 2), 50, nil), record(date(10, 26), 100, nil), record(date(10, 19), 200, nil)
        ], now: date(11, 2), calendar: calendar)!
        precondition(dst.current == 50 && dst.usual == 150)
        print("Insights checks passed: weighted hourly rankings, untimed shifts, comparable days, missing history, and DST.")
    }
}

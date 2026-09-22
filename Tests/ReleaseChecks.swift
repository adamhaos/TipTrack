import Foundation
import SwiftData

// Compile alongside Models, TipTrackCSV, CalendarFeed, and TipTrackSiriRules.
// Uses only transient models; never opens a saved database.
@main
struct ReleaseChecks {
    static func main() throws {
        let date = Date(timeIntervalSince1970: 1_791_000_000)
        let job = Job(name: "Harbor, \"Vine\"\nRestaurant")
        precondition(job.receiptPOS == "Auto Detect")
        precondition(job.iconName == "briefcase.fill")
        let container = try ModelContainer(for: Job.self, Shift.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        job.receiptPOS = "Toast"
        job.iconName = "fork.knife"
        job.reminderDelay = -30
        context.insert(job)
        try context.save()
        let reloaded = try ModelContext(container).fetch(FetchDescriptor<Job>())
        precondition(reloaded.first?.receiptPOS == "Toast")
        precondition(reloaded.first?.iconName == "fork.knife")
        precondition(reloaded.first?.reminderDelay == -30)
        // Exercise before/at/after end offsets, including shifts crossing midnight.
        let start = date
        let end = start.addingTimeInterval(8 * 3600)
        for timing in ShiftLoggingReminderTiming.allCases {
            let fire = ShiftLoggingReminderTiming.fireDate(start: start, end: end,
                offsetMinutes: timing.rawValue, now: start.addingTimeInterval(-3600))
            precondition(fire == end.addingTimeInterval(Double(timing.rawValue) * 60))
        }
        precondition(ShiftLoggingReminderTiming.fireDate(start: start, end: start.addingTimeInterval(1800),
            offsetMinutes: -60, now: start.addingTimeInterval(-7200)) == nil)
        precondition(ShiftLoggingReminderTiming.fireDate(start: start, end: end,
            offsetMinutes: -30, now: end) == nil)
        precondition(ShiftLoggingReminderTiming.message(jobName: "Cafe", offsetMinutes: -60)
            .contains("ends in 1 hour"))
        precondition(ShiftLoggingReminderTiming.message(jobName: "Cafe", offsetMinutes: -30)
            .contains("ends in 30 minutes"))
        precondition(ShiftLoggingReminderTiming.message(jobName: "Cafe", offsetMinutes: 15)
            .contains("has ended"))
        let shift = Shift(date: date, creditTip: 100.25, cashTip: 20.50, barTipOut: 5.25,
            hoursWorked: 6.5, hourlyRate: 15, job: job)
        let csv = TipTrackCSV.exportText(for: [shift])
        let parsed = TipTrackCSV.parse(csv)
        precondition(parsed.rows.count == 1 && parsed.rejectedRowCount == 0)
        let row = parsed.rows[0]
        precondition(row.jobName == job.name && row.hoursWorked == 6.5 && row.hourlyRate == 15)
        precondition(shift.totalEarnings == 213)
        precondition(TipTrackCSV.rowsForImport([row, row], existingShifts: []).count == 1)
        precondition(TipTrackCSV.rowsForImport([row], existingShifts: [shift]).isEmpty)
        let unassigned = Shift(date: row.date, creditTip: 100.25, cashTip: 20.5, barTipOut: 5.25,
            hoursWorked: 6.5, hourlyRate: 15)
        let unassignedRow = TipTrackCSV.parse(TipTrackCSV.exportText(for: [unassigned])).rows[0]
        precondition(TipTrackCSV.rowsForImport([unassignedRow], existingShifts: [unassigned]).isEmpty)
        unassigned.hourlyRate = 20
        precondition(TipTrackCSV.rowsForImport([unassignedRow], existingShifts: [unassigned]).count == 1)

        for amount in ["nan", "inf", "-1", "abc"] {
            for column in [2, 3, 4, 7, 8] {
                var fields = ["2026-10-02", "Cafe", "10", "20", "5", "15", "25", "6", "15"]
                fields[column] = amount
                let invalid = TipTrackCSV.parse(fields.joined(separator: ","))
                precondition(invalid.rows.isEmpty && invalid.rejectedRowCount == 1)
            }
        }
        let overflow = TipTrackCSV.parse("2026-10-02,Cafe,10,20,5,15,25,1e308,15")
        precondition(overflow.rows.isEmpty && overflow.rejectedRowCount == 1)
        let malformed = TipTrackCSV.parse("2026-10-02,\"Cafe,10,20,5")
        precondition(malformed.rows.isEmpty && malformed.rejectedRowCount == 1)
        precondition(TipTrackCSV.parse("2026-10-02,Cafe,0,0,0").rows.count == 1)
        precondition(TipTrackSiriRules.inputAmount("267,69", locale: Locale(identifier: "fr_FR")) == 267.69)
        precondition(TipTrackSiriRules.inputAmount("267.69", locale: Locale(identifier: "fr_FR")) == 267.69)
        for value in ["nan", "inf", "-2", "garbage"] {
            precondition(TipTrackSiriRules.inputAmount(value) == nil)
        }
        precondition(TipTrackSiriRules.inputAmount("") == 0)

        let id = UUID()
        let feed = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:weekly
        DTSTART;TZID=America/New_York:20261002T170000
        DTEND;TZID=America/New_York:20261002T230000
        RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=FR
        EXDATE;TZID=America/New_York:20261009T170000
        SUMMARY:Weekly shift
        END:VEVENT
        BEGIN:VEVENT
        UID:weekly
        RECURRENCE-ID;TZID=America/New_York:20261016T170000
        DTSTART;TZID=America/New_York:20261016T180000
        DTEND;TZID=America/New_York:20261016T230000
        SUMMARY:Moved shift
        END:VEVENT
        END:VCALENDAR
        """
        let events = try CalendarFeed.parse(feed, jobID: id, now: date)
        precondition(events.count == 2)
        precondition(events[0].end.timeIntervalSince(events[0].start) == 6 * 3600)
        precondition(events[1].title == "Moved shift")
        let largeIntervalFeed = feed.replacingOccurrences(of: "FREQ=WEEKLY;COUNT=3;BYDAY=FR",
            with: "FREQ=YEARLY;INTERVAL=\(Int.max);COUNT=3")
        _ = try CalendarFeed.parse(largeIntervalFeed, jobID: id, now: date)
        precondition(CalendarFeed.url("webcal://example.com/feed.ics")?.scheme == "https")
        precondition(CalendarFeed.url("http://example.com/feed.ics") == nil)
        print("Release checks passed: CSV round trips, duplicate protection, invalid amounts, hourly pay, localized entry, and recurring schedules.")
    }
}

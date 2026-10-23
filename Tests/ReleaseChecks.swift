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
        // Two-digit years read as 20xx instead of year 26; hex and exponents are rejected.
        let shortYear = TipTrackCSV.parse("10/13/26 18:30,Cafe,10,20,5").rows
        precondition(shortYear.count == 1 && Calendar(identifier: .gregorian).component(.year, from: shortYear[0].date) == 2026)
        precondition(TipTrackCSV.parse("2026-10-02,Cafe,0x10,0,0").rows.isEmpty)
        precondition(TipTrackCSV.parse("2026-10-02,Cafe,1e3,0,0").rows.isEmpty)
        // The repeated 1 AM hour when clocks go back keeps its exact moment through export.
        let ambiguous = Shift(date: Date(timeIntervalSince1970: 1_793_514_600), creditTip: 10, cashTip: 0,
            hoursWorked: 7.3333, hourlyRate: 15.125, job: job)
        let ambiguousRow = TipTrackCSV.parse(TipTrackCSV.exportText(for: [ambiguous])).rows[0]
        precondition(ambiguousRow.date == ambiguous.date)
        precondition(ambiguousRow.hoursWorked == 7.3333 && ambiguousRow.hourlyRate == 15.125)
        precondition(TipTrackCSV.rowsForImport([ambiguousRow], existingShifts: [ambiguous]).isEmpty)
        // Formula-looking names are neutralized in the file and restored on import.
        let formulaJob = Job(name: "=HYPERLINK(1)")
        let formulaCSV = TipTrackCSV.exportText(for: [Shift(date: date, creditTip: 1, cashTip: 0,
            notes: "+note", job: formulaJob)])
        precondition(formulaCSV.contains("\"'=HYPERLINK(1)\"") && formulaCSV.contains("\"'+note\""))
        let formulaRow = TipTrackCSV.parse(formulaCSV).rows[0]
        precondition(formulaRow.jobName == "=HYPERLINK(1)" && formulaRow.notes == "+note")
        // A name that really starts with an apostrophe keeps it.
        let quotedJob = Job(name: "'=Example")
        let quotedRow = TipTrackCSV.parse(TipTrackCSV.exportText(for: [Shift(date: date, creditTip: 1, cashTip: 0,
            job: quotedJob)])).rows[0]
        precondition(quotedRow.jobName == "'=Example")
        // Older exports without a UTC offset still import.
        precondition(TipTrackCSV.parse("2026-10-02 18:30,Cafe,10,20,5").rows.count == 1)

        // Spring-forward night: a time in the skipped hour moves to the next valid time.
        let gapFeed = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:gap
        DTSTART;TZID=America/New_York:20270313T200000
        DTEND;TZID=America/New_York:20270314T023000
        SUMMARY:Late bar
        END:VEVENT
        BEGIN:VEVENT
        UID:outlook
        DTSTART;TZID=Pacific Standard Time:20270320T170000
        DTEND;TZID=Pacific Standard Time:20270320T230000
        SUMMARY:Outlook shift
        END:VEVENT
        BEGIN:VEVENT
        UID:until
        DTSTART;TZID=America/New_York:20270322T170000
        DURATION:PT6H
        RRULE:FREQ=DAILY;UNTIL=20270324
        SUMMARY:Until shift
        END:VEVENT
        BEGIN:VEVENT
        UID:until
        RECURRENCE-ID;TZID=America/New_York:20270323T170000
        DTSTART;TZID=America/New_York:20270323T180000
        DURATION:PT2H
        SUMMARY:Moved short
        END:VEVENT
        END:VCALENDAR
        """
        let gapEvents = try CalendarFeed.parse(gapFeed, jobID: id, now: Date(timeIntervalSince1970: 1_804_000_000))
        let late = gapEvents.first { $0.title == "Late bar" }!
        precondition(late.end.timeIntervalSince(late.start) == 6.5 * 3600)
        let outlook = gapEvents.first { $0.title == "Outlook shift" }!
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        precondition(pacific.component(.hour, from: outlook.start) == 17)
        precondition(gapEvents.filter { $0.title == "Until shift" }.count == 2)
        precondition(CalendarFeed.date(CalendarFeed.Property(name: "DTSTART", parameters: [:],
            value: "20270230T235959Z")) == nil)
        let moved = gapEvents.first { $0.title == "Moved short" }!
        precondition(moved.end.timeIntervalSince(moved.start) == 2 * 3600)
        print("Release checks passed: CSV round trips, duplicate protection, invalid amounts, hourly pay, localized entry, and recurring schedules.")
    }
}

import AppIntents
import Foundation
import LocalAuthentication
import SwiftData
import SwiftUI

extension TipPeriod: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time Period")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .today: "Today",
        .yesterday: "Yesterday",
        .thisWeek: "This Week",
        .lastWeek: "Last Week",
        .thisMonth: "This Month",
        .lastMonth: "Last Month",
        .thisYear: "This Year",
        .lastShift: "Last Shift",
        .allTime: "All Time"
    ]
}

enum TipInsightQuestion: String, AppEnum {
    case bestPayingJob, averagePerShift, bestShift
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Earnings Question")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .bestPayingJob: "Best Paying Job",
        .averagePerShift: "Average Earnings Per Shift",
        .bestShift: "Best Shift"
    ]
}

enum TipWeekday: Int, AppEnum {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Day of the Week")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .sunday: "Sunday", .monday: "Monday", .tuesday: "Tuesday", .wednesday: "Wednesday",
        .thursday: "Thursday", .friday: "Friday", .saturday: "Saturday"
    ]
    var name: String { Calendar.current.weekdaySymbols[rawValue - 1] }
}

struct TipTrackJobEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Job")
    static let defaultQuery = TipTrackJobQuery()
    // Job names can reveal where someone works, so Siri must authenticate before showing them.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    let id: UUID
    // A Siri-facing description needs iOS 27.3 (above the deployment target) and stored
    // property wrappers can't be availability-gated, so the name keeps the plain init.
    @Property(title: "Name") var name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TipTrackJobQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TipTrackJobEntity] {
        try await TipTrackSiriPrivacy.authorize()
        return try await TipTrackIntentStore.jobs(identifiers: identifiers)
    }

    func entities(matching string: String) async throws -> [TipTrackJobEntity] {
        try await TipTrackSiriPrivacy.authorize()
        return try await TipTrackIntentStore.jobs(matching: string)
    }

    // No prompt here: the app refreshes suggestions at launch, before it is unlocked.
    func suggestedEntities() async throws -> [TipTrackJobEntity] {
        try await TipTrackIntentStore.jobs()
    }
}

@MainActor
private enum TipTrackSiriPrivacy {
    // Siri gets its own short-lived grant so authenticating for an intent never
    // unlocks the app itself; parameter resolution and perform() share one prompt.
    private static var grantExpiry: Date?

    static var hasGrant: Bool { grantExpiry.map { $0 > Date() } ?? false }

    static func authorize(revealsEarnings: Bool = false) async throws {
        let protected = UserDefaults.standard.bool(forKey: FeatureKeys.appLock)
            || (revealsEarnings && UserDefaults.standard.bool(forKey: "privacyEnabled"))
        guard protected, !PrivacyManager.shared.unlocked, !hasGrant else { return }
        // Wait for an authentication already started by the app's lock screen.
        while PrivacyManager.shared.authenticating {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !PrivacyManager.shared.unlocked, !hasGrant else { return }
        let success = (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
            localizedReason: "Reveal your TipTrack earnings")) ?? false
        guard success else { throw TipTrackIntentError.privacyLocked }
        grantExpiry = Date().addingTimeInterval(60)
    }
}

@MainActor
private enum TipTrackIntentNavigation {
    static func open(_ destination: TipTrackControlDestination) {
        // Preserve routes until ContentView is ready, including cold launches.
        UserDefaults(suiteName: "group.atm.TipTrack")?.set(destination.rawValue, forKey: "tiptrack.pendingRoute")
        NotificationCenter.default.post(name: .tipTrackIntentRoute, object: nil)
    }
}

enum TipTrackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noJobs
    case unableToAccessData
    case privacyLocked

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noJobs: "That job is unavailable. Add or select a job in TipTrack3r, then try again."
        case .unableToAccessData: "TipTrack3r couldn’t access your shift data. Open the app and try again."
        case .privacyLocked: "Your TipTrack3r data is locked. Open the app and authenticate before using this action."
        }
    }
}

@MainActor
enum TipTrackIntentStore {
    private static var registeredContainer: ModelContainer?
    static func register(_ container: ModelContainer) { registeredContainer = container }

    private static let backgroundContainer: ModelContainer? = {
        let schema = Schema([Shift.self, Job.self])
        let automatic = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        let legacy = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        let storeURL = FileManager.default.fileExists(atPath: automatic.url.path) ? automatic.url :
            (FileManager.default.fileExists(atPath: legacy.path) ? legacy : automatic.url)
        let cloudSync = UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true
        let configuration = ModelConfiguration(schema: schema, url: storeURL,
            cloudKitDatabase: cloudSync ? .private("iCloud.atm.TipTrack") : .none)
        return try? ModelContainer(for: schema, configurations: [configuration])
    }()

    private static var container: ModelContainer? { registeredContainer ?? backgroundContainer }

    static func requirePrivacyAccess(revealsEarnings: Bool = false) throws {
        let defaults = UserDefaults.standard
        guard !TipTrackSiriRules.requiresAuthentication(
            appLock: defaults.bool(forKey: FeatureKeys.appLock),
            earningsPrivacy: defaults.bool(forKey: "privacyEnabled"),
            revealsEarnings: revealsEarnings,
            unlocked: PrivacyManager.shared.unlocked || TipTrackSiriPrivacy.hasGrant
        ) else { throw TipTrackIntentError.privacyLocked }
    }

    static func jobs(identifiers: [UUID]? = nil, matching search: String? = nil) throws -> [TipTrackJobEntity] {
        try requirePrivacyAccess()
        guard let container else { throw TipTrackIntentError.unableToAccessData }
        let jobs = try ModelContext(container).fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\Job.name)]))
        return jobs.filter { job in
            (identifiers == nil || identifiers?.contains(job.id) == true) &&
            (search == nil || job.name.localizedCaseInsensitiveContains(search ?? ""))
        }.map { TipTrackJobEntity(id: $0.id, name: $0.name) }
    }

    static func summary(period: TipPeriod, jobID: UUID?, now: Date = Date()) throws -> (total: Double, count: Int, hourly: Double?) {
        try requirePrivacyAccess(revealsEarnings: true)
        guard let container else { throw TipTrackIntentError.unableToAccessData }
        let context = ModelContext(container)
        if let jobID {
            guard try context.fetch(FetchDescriptor<Job>()).contains(where: { $0.id == jobID }) else {
                throw TipTrackIntentError.noJobs
            }
        }
        var shifts = try context.fetch(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Shift.date, order: .reverse)]
        )).filter { jobID == nil || $0.job?.id == jobID }

        if period == .lastShift {
            // A shift logged ahead of time isn't the last one worked.
            shifts = Array(shifts.filter { $0.date <= now }.prefix(1))
        } else if let interval = TipTrackSiriRules.interval(for: period, now: now, calendar: .preferredWeek) {
            shifts = shifts.filter { $0.date >= interval.start && $0.date < interval.end }
        }

        let total = shifts.reduce(0) { $0 + $1.totalEarnings }
        let hourly = TipTrackSiriRules.hourlyAverage(earningsAndHours: shifts.map { ($0.totalEarnings, $0.hoursWorked) })
        return (total, shifts.count, hourly)
    }

    /// Earnings for one calendar day, such as "last month on the 15th".
    static func summary(day: Date, jobID: UUID?) throws -> (total: Double, count: Int, hourly: Double?) {
        try requirePrivacyAccess(revealsEarnings: true)
        guard let container else { throw TipTrackIntentError.unableToAccessData }
        let context = ModelContext(container)
        if let jobID, !(try context.fetch(FetchDescriptor<Job>()).contains { $0.id == jobID }) {
            throw TipTrackIntentError.noJobs
        }
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return (0, 0, nil) }
        let start = interval.start, end = interval.end
        let shifts = try context.fetch(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.deletedAt == nil && $0.date >= start && $0.date < end }
        )).filter { jobID == nil || $0.job?.id == jobID }
        let total = shifts.reduce(0) { $0 + $1.totalEarnings }
        let hourly = TipTrackSiriRules.hourlyAverage(earningsAndHours: shifts.map { ($0.totalEarnings, $0.hoursWorked) })
        return (total, shifts.count, hourly)
    }

    /// Saves a shift dictated to Siri, then refreshes the widgets and the Watch.
    static func logShift(jobID: UUID?, date: Date, credit: Double, cash: Double, tipOut: Double,
        hours: Double?, hourlyRate: Double?) throws -> Double {
        try requirePrivacyAccess()
        guard let container else { throw TipTrackIntentError.unableToAccessData }
        let context = ModelContext(container)
        let job = try jobID.map { id in
            guard let match = try context.fetch(FetchDescriptor<Job>()).first(where: { $0.id == id }) else {
                throw TipTrackIntentError.noJobs
            }
            return match
        }
        let payEnabled = UserDefaults.standard.object(forKey: FeatureKeys.hourlyPayEnabled) as? Bool ?? true
        let shift = Shift(date: date, creditTip: credit, cashTip: cash, barTipOut: tipOut,
            hoursWorked: hours.flatMap { $0 > 0 ? $0 : nil },
            hourlyRate: payEnabled ? (hourlyRate ?? 0) : 0, job: job)
        context.insert(shift)
        do { try context.save() } catch {
            context.rollback()
            throw TipTrackIntentError.unableToAccessData
        }
        let all = (try? context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Shift.date)]))) ?? []
        WidgetSnapshotWriter.publish(shifts: all)
        WatchSyncService.shared.publish()
        return shift.totalEarnings
    }

    static func insightRecords(period: TipPeriod, jobID: UUID?, now: Date) throws -> [EarningsRecord] {
        try requirePrivacyAccess(revealsEarnings: true)
        guard let container else { throw TipTrackIntentError.unableToAccessData }
        let context = ModelContext(container)
        if let jobID, !(try context.fetch(FetchDescriptor<Job>()).contains { $0.id == jobID }) {
            throw TipTrackIntentError.noJobs
        }
        var records = try context.fetch(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Shift.date, order: .reverse)]
        )).filter { (jobID == nil || $0.job?.id == jobID) && $0.date <= now }.map(\.earningsRecord)
        if period == .lastShift { records = Array(records.prefix(1)) }
        else if let interval = TipTrackSiriRules.interval(for: period, now: now, calendar: .preferredWeek) {
            records = records.filter { $0.date >= interval.start && $0.date < interval.end }
        }
        return records
    }


}

struct AskTipInsightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About Best Shifts"
    static let description = IntentDescription("Ask about your best-paying job, average earnings per shift, or best shift. Defaults to this month across all jobs.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = false
    @Parameter(title: "Question", description: "Which insight to compute: the job with the highest total earnings, the average earnings per logged shift, or the single highest-earning shift.", default: .averagePerShift)
    var question: TipInsightQuestion
    @Parameter(title: "Period", description: "The time range to look at, relative to today. Weeks follow the person's chosen first day of the week.", default: .thisMonth)
    var period: TipPeriod
    @Parameter(title: "Job", description: "Limit the answer to one job. Leave empty to include every job.")
    var job: TipTrackJobEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$question) for \(\.$period)") { \.$job }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TipTrackSiriPrivacy.authorize(revealsEarnings: true)
        let now = Date()
        let records = try await TipTrackIntentStore.insightRecords(period: period, jobID: job?.id, now: now)
        let calendar = await Calendar.preferredWeek
        let periodName = TipTrackSiriRules.periodDescription(period, now: now, calendar: calendar)
        let jobName = job.map { " at \($0.name)" } ?? ""
        guard !records.isEmpty else {
            return .result(dialog: "There are no logged shifts \(periodName)\(jobName).")
        }
        switch question {
        case .averagePerShift:
            let average = records.reduce(0) { $0 + $1.earnings } / Double(records.count)
            return .result(dialog: "You averaged \(average.formatted(.currency(code: "USD"))) per logged shift \(periodName)\(jobName), across \(records.count) shifts.")
        case .bestShift:
            let best = records.sorted { $0.earnings == $1.earnings ? $0.date > $1.date : $0.earnings > $1.earnings }[0]
            return .result(dialog: "Your highest-earning shift \(periodName)\(jobName) was at \(best.jobName) on \(best.date.formatted(date: .abbreviated, time: .omitted)): \(best.earnings.formatted(.currency(code: "USD"))).")
        case .bestPayingJob:
            let grouped = Dictionary(grouping: records, by: \.jobID)
            let totals = grouped.compactMap { id, values -> (id: UUID, name: String, total: Double)? in
                guard let id else { return nil }
                return (id, values[0].jobName, values.reduce(0) { $0 + $1.earnings })
            }.sorted { $0.total == $1.total ? $0.id.uuidString < $1.id.uuidString : $0.total > $1.total }
            guard let best = totals.first else {
                return .result(dialog: "Your shifts \(periodName) are not assigned to a job yet.")
            }
            return .result(dialog: "\(best.name) earned you the most \(periodName): \(best.total.formatted(.currency(code: "USD"))) in total logged earnings.")
        }
    }
}

struct AskTipTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About Tips"
    static let description = IntentDescription("Get earnings and timed-shift hourly averages across all jobs for your chosen period. Prompts for the period if it cannot be determined.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = false

    @Parameter(title: "Period", description: "The time range to total, relative to today, such as today, last week, or this month. Weeks follow the person's chosen first day of the week.", requestValueDialog: "Which time period would you like?", requestDisambiguationDialog: "Which time period?")
    var period: TipPeriod

    @Parameter(title: "Job", description: "Limit the total to one job. Leave empty to include every job.", requestDisambiguationDialog: "Which job?")
    var job: TipTrackJobEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get earnings for \(\.$period)") { \.$job }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog & ShowsSnippetView {
        try await TipTrackSiriPrivacy.authorize(revealsEarnings: true)
        let now = Date()
        let result = try await TipTrackIntentStore.summary(period: period, jobID: job?.id, now: now)
        let jobName = job.map { " at \($0.name)" } ?? ""
        let calendar = await Calendar.preferredWeek
        let periodName = TipTrackSiriRules.periodDescription(period, now: now, calendar: calendar)
        let card = TipTrackEarningsCard(period: periodName, job: job?.name, total: result.total, shifts: result.count, hourly: result.hourly)
        if result.count == 0 {
            return .result(value: 0, dialog: "There are no logged shifts \(periodName)\(jobName).", view: card)
        }
        if let hourly = result.hourly {
            return .result(value: result.total,
                dialog: "You made \(result.total, format: .currency(code: "USD")) \(periodName)\(jobName) across \(result.count) shifts, averaging \(hourly, format: .currency(code: "USD")) per hour.", view: card)
        }
        return .result(value: result.total,
            dialog: "You made \(result.total, format: .currency(code: "USD")) \(periodName)\(jobName) across \(result.count) shifts.", view: card)
    }
}

struct LogTipsWithSiriIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Shift"
    static let description = IntentDescription("Logs a worked shift in Tip Tracker with its credit card tips, cash tips, tip-out, and optional hours. Siri reads the entry back and asks for confirmation before saving.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = false

    @Parameter(title: "Job", description: "The job or workplace the shift was at.", requestValueDialog: "Which job did you work?")
    var job: TipTrackJobEntity?
    @Parameter(title: "Date", description: "The day the shift was worked. Defaults to today.")
    var date: Date?
    @Parameter(title: "Credit Tips", description: "Credit card tips in dollars, before tip-out.", requestValueDialog: "How much did you make in credit tips?")
    var creditTips: Double?
    @Parameter(title: "Cash Tips", description: "Cash tips in dollars, before tip-out.", requestValueDialog: "How much did you make in cash tips?")
    var cashTips: Double?
    @Parameter(title: "Tip Out", description: "Dollars the person tipped out to coworkers, such as the bar or bussers. Subtracted from cash.")
    var tipOut: Double?
    @Parameter(title: "Hours Worked", description: "Hours worked on the shift, as a decimal number.")
    var hoursWorked: Double?
    @Parameter(title: "Hourly Rate", description: "Base hourly wage in dollars, before tips.")
    var hourlyRate: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a shift at \(\.$job)") {
            \.$date
            \.$creditTips
            \.$cashTips
            \.$tipOut
            \.$hoursWorked
            \.$hourlyRate
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TipTrackSiriPrivacy.authorize()
        var jobEntity = job
        if jobEntity == nil {
            let jobs = try await TipTrackIntentStore.jobs()
            if jobs.count == 1 { jobEntity = jobs[0] }
            else if !jobs.isEmpty { throw $job.needsValueError("Which job did you work?") }
        }
        let credit = creditTips ?? 0, cash = cashTips ?? 0, out = tipOut ?? 0
        let shiftDate = date ?? Date()
        try TipTrackSiriRules.validate(credit: credit, cash: cash, tipOut: out,
            hours: hoursWorked, hourlyRate: hourlyRate, date: shiftDate)

        let usd = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        var parts = ["\(credit.formatted(usd)) credit", "\(cash.formatted(usd)) cash"]
        if out > 0 { parts.append("\(out.formatted(usd)) tip-out") }
        if let hoursWorked, hoursWorked > 0 { parts.append("\(hoursWorked.formatted()) hours") }
        let day = Calendar.current.isDateInToday(shiftDate) ? "today"
            : "on \(shiftDate.formatted(date: .abbreviated, time: .omitted))"
        let at = jobEntity.map { " at \($0.name)" } ?? ""
        let summary = "\(parts.joined(separator: ", "))\(at) \(day)"
        try await requestConfirmation(result: .result(dialog: "Log \(summary)?"), confirmationActionName: .add)

        let total = try await TipTrackIntentStore.logShift(jobID: jobEntity?.id, date: shiftDate,
            credit: credit, cash: cash, tipOut: out, hours: hoursWorked, hourlyRate: hourlyRate)
        return .result(dialog: "Logged. That shift comes to \(total.formatted(usd)).")
    }
}

/// Earnings for a specific calendar day, e.g. "last month on the 15th".
struct AskAboutDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About a Day"
    static let description = IntentDescription("Get total earnings for one specific calendar day, such as March 15 or last Friday.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = false

    @Parameter(title: "Day", description: "The calendar day to total. Only the date matters, not the time.", requestValueDialog: "Which day?")
    var day: Date
    @Parameter(title: "Job", description: "Limit the total to one job. Leave empty to include every job.")
    var job: TipTrackJobEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get earnings on \(\.$day)") { \.$job }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog & ShowsSnippetView {
        try await TipTrackSiriPrivacy.authorize(revealsEarnings: true)
        let result = try await TipTrackIntentStore.summary(day: day, jobID: job?.id)
        let dayName = "on \(day.formatted(date: .complete, time: .omitted))"
        let jobName = job.map { " at \($0.name)" } ?? ""
        let card = TipTrackEarningsCard(period: dayName, job: job?.name, total: result.total, shifts: result.count, hourly: result.hourly)
        guard result.count > 0 else {
            return .result(value: 0, dialog: "There are no logged shifts \(dayName)\(jobName).", view: card)
        }
        return .result(value: result.total,
            dialog: "You made \(result.total, format: .currency(code: "USD")) \(dayName)\(jobName).", view: card)
    }
}

/// Average take-home on one day of the week, e.g. "what do I average on a Thursday?"
struct AskWeekdayAverageIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About a Day of the Week"
    static let description = IntentDescription("Get the average earnings for days worked on one day of the week, such as Thursdays. Several shifts on the same day count as one day.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = false

    @Parameter(title: "Day of the Week", description: "Which weekday to average.", requestValueDialog: "Which day of the week?")
    var weekday: TipWeekday
    @Parameter(title: "Period", description: "The time range to look at, relative to today. Defaults to all time.", default: .allTime)
    var period: TipPeriod
    @Parameter(title: "Job", description: "Limit the average to one job. Leave empty to include every job.")
    var job: TipTrackJobEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get average earnings on \(\.$weekday) for \(\.$period)") { \.$job }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try await TipTrackSiriPrivacy.authorize(revealsEarnings: true)
        let now = Date()
        let calendar = Calendar.current
        let records = try await TipTrackIntentStore.insightRecords(period: period, jobID: job?.id, now: now)
            .filter { calendar.component(.weekday, from: $0.date) == weekday.rawValue }
        let days = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        let weekCalendar = await Calendar.preferredWeek
        let periodName = TipTrackSiriRules.periodDescription(period, now: now, calendar: weekCalendar)
        let jobName = job.map { " at \($0.name)" } ?? ""
        guard !days.isEmpty else {
            return .result(value: 0, dialog: "You have no logged \(weekday.name) shifts \(periodName)\(jobName).")
        }
        let average = records.reduce(0) { $0 + $1.earnings } / Double(days.count)
        return .result(value: average,
            dialog: "You average \(average, format: .currency(code: "USD")) on \(weekday.name)s\(jobName) \(periodName), across \(days.count) \(days.count == 1 ? "day" : "days") worked.")
    }
}

struct LogShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Shift"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Siri is information-only in Tip Tracker. Log shifts in the app.")
    }
}

struct ViewTipHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "View Tip History"
    static let description = IntentDescription("Opens Tip Tracker to the list of past logged shifts.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await TipTrackIntentNavigation.open(.history)
        return .result()
    }
}

struct OpenShiftCalendarIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Shift Calendar"
    static let description = IntentDescription("Opens Tip Tracker to the calendar of logged and scheduled shifts.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await TipTrackIntentNavigation.open(.calendar)
        return .result()
    }
}

struct StartLiveShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Shift"
    static let isDiscoverable = false
    @Parameter(title: "Job") var job: TipTrackJobEntity?
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Siri is information-only in Tip Tracker. Start your shift timer in the app.")
    }
}

struct EndLiveShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "End Current Shift"
    static let isDiscoverable = false
    @Parameter(title: "Job") var job: TipTrackJobEntity?
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Siri is information-only in Tip Tracker. End your shift timer in the app.")
    }
}

struct TipTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskTipTrackIntent(), phrases: [
            "How much did I make in \(.applicationName)",
            "How much did I make tonight in \(.applicationName)",
            "What about \(\.$period) in \(.applicationName)",
            "How much did I make \(\.$period) in \(.applicationName)",
            "How much did I make at my job \(\.$period) in \(.applicationName)",
            "How much did I make at work \(\.$period) in \(.applicationName)",
            "What are my earnings \(\.$period) in \(.applicationName)",
            "How much did I earn at \(\.$job) in \(.applicationName)",
            "Ask \(.applicationName) about my tips"
        ], shortTitle: "Ask About Tips", systemImageName: "bubble.left.and.text.bubble.right.fill")
        AppShortcut(intent: AskTipInsightsIntent(), phrases: [
            "What is my \(\.$question) in \(.applicationName)",
            "What was my \(\.$question) in \(.applicationName)",
            "Ask \(.applicationName) about my \(\.$question)"
        ], shortTitle: "Earnings Insights", systemImageName: "chart.bar.fill")
        AppShortcut(intent: AskWeekdayAverageIntent(), phrases: [
            "What do I average on \(\.$weekday) in \(.applicationName)",
            "How much do I make on \(\.$weekday) in \(.applicationName)"
        ], shortTitle: "Day of the Week", systemImageName: "calendar.day.timeline.left")
        AppShortcut(intent: LogTipsWithSiriIntent(), phrases: [
            "Log a shift in \(.applicationName)",
            "Log a shift at \(\.$job) in \(.applicationName)",
            "Log my tips in \(.applicationName)"
        ], shortTitle: "Log a Shift", systemImageName: "plus.circle.fill")
        AppShortcut(intent: ViewTipHistoryIntent(), phrases: ["Show my tip history in \(.applicationName)"],
            shortTitle: "Tip History", systemImageName: "clock.arrow.circlepath")
        AppShortcut(intent: OpenShiftCalendarIntent(), phrases: ["Open my shift calendar in \(.applicationName)"],
            shortTitle: "Shift Calendar", systemImageName: "calendar")
    }
}

// Siri AI Developer Preview (iOS 27.3 SDK). Turns the information-only intents into
// tools Siri AI can call from natural requests. These compile automatically with
// Xcode 27.3 or later (AppIntents 301.2+) and are skipped with Xcode 27.2, so either
// Xcode builds the app. The intents keep working on iOS 27.0 either way; the tool
// conformance only applies on iOS 27.3 and later. This is the conformance that
// @AppIntent(.tool) generates, written out so the SDK check can gate it.
#if SIRI_AI_PREVIEW || canImport(AppIntents, _version: 301.2)
@available(iOS 27.3, *) extension AskTipTrackIntent: ToolIntent {}
@available(iOS 27.3, *) extension AskTipInsightsIntent: ToolIntent {}
@available(iOS 27.3, *) extension ViewTipHistoryIntent: ToolIntent {}
@available(iOS 27.3, *) extension OpenShiftCalendarIntent: ToolIntent {}
@available(iOS 27.3, *) extension AskAboutDayIntent: ToolIntent {}
@available(iOS 27.3, *) extension AskWeekdayAverageIntent: ToolIntent {}
@available(iOS 27.3, *) extension LogTipsWithSiriIntent: ToolIntent {}
#endif

/// Siri result card for "Ask About Tips". Static content only: Siri renders it ahead of display.
struct TipTrackEarningsCard: View {
    let period: String
    let job: String?
    let total: Double
    let shifts: Int
    let hourly: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label {
                Text(total, format: .currency(code: "USD"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            } icon: {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.green)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { details }
                VStack(alignment: .leading, spacing: 4) { details }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var heading: String {
        guard let job else { return period.capitalized }
        return "\(job), \(period)"
    }

    @ViewBuilder private var details: some View {
        Label("^[\(shifts) shift](inflect: true)", systemImage: "calendar")
        if let hourly {
            Label("\(hourly.formatted(.currency(code: "USD"))) per hour", systemImage: "clock")
        }
    }

    private var spokenSummary: String {
        var parts = ["\(heading): \(total.formatted(.currency(code: "USD")))",
                     shifts == 1 ? "1 shift" : "\(shifts) shifts"]
        if let hourly { parts.append("\(hourly.formatted(.currency(code: "USD"))) per hour") }
        return parts.joined(separator: ", ")
    }
}

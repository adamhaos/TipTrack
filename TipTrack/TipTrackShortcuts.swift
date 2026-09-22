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

struct TipTrackJobEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Job")
    static let defaultQuery = TipTrackJobQuery()

    let id: UUID
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
            shifts = Array(shifts.prefix(1))
        } else if let interval = TipTrackSiriRules.interval(for: period, now: now, calendar: .preferredWeek) {
            shifts = shifts.filter { $0.date >= interval.start && $0.date < interval.end }
        }

        let total = shifts.reduce(0) { $0 + $1.totalEarnings }
        let hourly = TipTrackSiriRules.hourlyAverage(earningsAndHours: shifts.map { ($0.totalEarnings, $0.hoursWorked) })
        return (total, shifts.count, hourly)
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
    @Parameter(title: "Question", default: .averagePerShift) var question: TipInsightQuestion
    @Parameter(title: "Period", default: .thisMonth) var period: TipPeriod
    @Parameter(title: "Job") var job: TipTrackJobEntity?

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

    @Parameter(title: "Period", requestValueDialog: "Which time period would you like?", requestDisambiguationDialog: "Which time period?")
    var period: TipPeriod

    @Parameter(title: "Job", requestDisambiguationDialog: "Which job?")
    var job: TipTrackJobEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get earnings for \(\.$period)") { \.$job }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        try await TipTrackSiriPrivacy.authorize(revealsEarnings: true)
        let now = Date()
        let result = try await TipTrackIntentStore.summary(period: period, jobID: job?.id, now: now)
        let jobName = job.map { " at \($0.name)" } ?? ""
        let calendar = await Calendar.preferredWeek
        let periodName = TipTrackSiriRules.periodDescription(period, now: now, calendar: calendar)
        if result.count == 0 {
            return .result(value: 0, dialog: "There are no logged shifts \(periodName)\(jobName).")
        }
        if let hourly = result.hourly {
            return .result(value: result.total,
                dialog: "You made \(result.total, format: .currency(code: "USD")) \(periodName)\(jobName) across \(result.count) shifts, averaging \(hourly, format: .currency(code: "USD")) per hour.")
        }
        return .result(value: result.total,
            dialog: "You made \(result.total, format: .currency(code: "USD")) \(periodName)\(jobName) across \(result.count) shifts.")
    }
}

struct LogTipsWithSiriIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Tips"
    static let description = IntentDescription("Voice logging is no longer available. Log shifts in Tip Tracker.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true

    @Parameter(title: "Job", requestValueDialog: "Which job did you work?")
    var job: TipTrackJobEntity?
    @Parameter(title: "Date", requestValueDialog: "What date was the shift?")
    var date: Date?
    @Parameter(title: "Credit Tips", requestValueDialog: "How much did you make in credit tips?")
    var creditTips: Double?
    @Parameter(title: "Cash Tips", requestValueDialog: "How much did you make in cash tips?")
    var cashTips: Double?
    @Parameter(title: "Tip Out")
    var tipOut: Double?
    @Parameter(title: "Hours Worked")
    var hoursWorked: Double?
    @Parameter(title: "Hourly Rate")
    var hourlyRate: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Log tips for \(\.$job)") {
            \.$date
            \.$creditTips
            \.$cashTips
            \.$tipOut
            \.$hoursWorked
            \.$hourlyRate
        }
    }

    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Siri is information-only in Tip Tracker. Log shifts in the app.")
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
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await TipTrackIntentNavigation.open(.history)
        return .result()
    }
}

struct OpenShiftCalendarIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Shift Calendar"
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
        AppShortcut(intent: ViewTipHistoryIntent(), phrases: ["Show my tip history in \(.applicationName)"],
            shortTitle: "Tip History", systemImageName: "clock.arrow.circlepath")
        AppShortcut(intent: OpenShiftCalendarIntent(), phrases: ["Open my shift calendar in \(.applicationName)"],
            shortTitle: "Shift Calendar", systemImageName: "calendar")
    }
}

import Foundation

// Shared by the iPhone app and the watch app. The phone owns all data; the watch
// sends commands and mirrors the state the phone publishes.
nonisolated enum WatchSyncKey {
    static let state = "state"
    static let command = "command"
}

nonisolated struct WatchJob: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String
    var isDefault: Bool
    var iconName: String?
}

nonisolated struct WatchLiveShift: Codable, Hashable, Sendable {
    var id: UUID
    var startedAt: Date
    var jobID: UUID?
    var jobName: String
}

nonisolated struct WatchPeriodTotals: Codable, Hashable, Sendable {
    var credit: Double = 0
    var netCash: Double = 0
    var shifts = 0
    var total: Double { credit + netCash }
}

nonisolated struct WatchDaySummary: Codable, Hashable, Sendable {
    var date: Date
    var total: Double
    var hours: Double
    var shifts: Int
    var scheduled: Bool
}

// The phone's dashboard numbers. Left out entirely when earnings privacy is on.
nonisolated struct WatchEarningsSummary: Codable, Hashable, Sendable {
    var week: [WatchDaySummary]
    var weekTotals: WatchPeriodTotals
    var month: Date
    var monthTotals: WatchPeriodTotals
    var lastShiftDate: Date?
    var lastShiftTotal: Double?
}

nonisolated struct WatchUpcomingShift: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var jobID: UUID?
    var jobName: String
    var start: Date
    var end: Date
}

// Chosen in the iPhone app's Apple Watch settings.
nonisolated struct WatchDisplayOptions: Codable, Hashable, Sendable {
    var showTotals = true
    var showLiveTimer = false
}

nonisolated struct WatchPhoneState: Codable, Hashable, Sendable {
    var jobs: [WatchJob] = []
    var liveShift: WatchLiveShift?
    var summary: WatchEarningsSummary?
    var earningsHidden: Bool?
    var options: WatchDisplayOptions?
    var upcoming: [WatchUpcomingShift]?
    /// The end of the person's week, so the watch can list the rest of this week's shifts.
    var weekEnd: Date?
}

nonisolated struct WatchShiftEntry: Codable, Hashable, Sendable {
    // Generated on the watch so a queued entry delivered twice is only saved once.
    var id: UUID
    var date: Date
    var jobID: UUID?
    var creditTip: Double
    var cashTip: Double
    var tipOut: Double
    var hoursWorked: Double?
}

nonisolated enum WatchCommand: Codable, Hashable, Sendable {
    // Commands carry the watch's timestamp so queued delivery keeps the real start time.
    case startShift(id: UUID, jobID: UUID?, at: Date)
    case endShift
    case logShift(WatchShiftEntry)
    case undoLog(id: UUID)
}

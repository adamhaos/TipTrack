import Foundation
import Observation
import WatchConnectivity

// Mirrors the phone's state and sends commands. Actions update the watch right away;
// when the phone is out of reach they are queued and delivered once it reconnects.
@MainActor @Observable
final class WatchSessionStore: NSObject {
    static let shared = WatchSessionStore()
    private static let cacheKey = "tiptrack.watch.state"

    private(set) var state: WatchPhoneState
    private(set) var hasPhoneState: Bool
    private(set) var pendingCount = 0

    var jobs: [WatchJob] { state.jobs }
    var liveShift: WatchLiveShift? { state.liveShift }
    /// The phone only publishes when something changes, so after midnight, a new week or a
    /// new month the cached totals belong to a period that's over: show that period as empty.
    var summary: WatchEarningsSummary? {
        guard var summary = state.summary else { return nil }
        let now = Date()
        let calendar = Calendar.current
        if let lastDay = summary.week.last?.date, calendar.startOfDay(for: now) > lastDay {
            summary.week = []
            summary.weekTotals = WatchPeriodTotals()
        }
        if !calendar.isDate(summary.month, equalTo: now, toGranularity: .month), summary.month < now {
            summary.month = calendar.dateInterval(of: .month, for: now)?.start ?? now
            summary.monthTotals = WatchPeriodTotals()
        }
        return summary
    }
    var earningsHidden: Bool { state.earningsHidden ?? false }
    var options: WatchDisplayOptions { state.options ?? WatchDisplayOptions() }
    var upcoming: [WatchUpcomingShift] { (state.upcoming ?? []).filter { $0.end > Date() } }
    /// Upcoming shifts through the end of the person's week.
    var upcomingThisWeek: [WatchUpcomingShift] {
        guard var weekEnd = state.weekEnd else { return upcoming }
        // A stored week end that has passed means a new week has started since the last update.
        while weekEnd <= Date() { weekEnd = weekEnd.addingTimeInterval(7 * 86_400) }
        return upcoming.filter { $0.start < weekEnd }
    }
    /// Set when a shift is logged so the home screen can rain cash.
    private(set) var celebration: Date?
    var defaultJob: WatchJob? { jobs.first(where: \.isDefault) ?? jobs.first }

    private override init() {
        let cached = UserDefaults.standard.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode(WatchPhoneState.self, from: $0) }
        state = cached ?? WatchPhoneState()
        hasPhoneState = cached != nil
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func startShift(job: WatchJob?) {
        guard liveShift == nil else { return }
        let shift = WatchLiveShift(id: UUID(), startedAt: Date(), jobID: job?.id, jobName: job?.name ?? "Work Shift")
        apply { $0.liveShift = shift }
        send(.startShift(id: shift.id, jobID: job?.id, at: shift.startedAt))
    }

    @discardableResult
    func endShift() -> WatchLiveShift? {
        let ended = liveShift
        apply { $0.liveShift = nil }
        send(.endShift(id: ended?.id))
        return ended
    }

    func clearCelebration() {
        celebration = nil
    }

    /// The shift just logged, while its Undo is still offered.
    private(set) var undoableEntry: WatchShiftEntry?

    func log(_ entry: WatchShiftEntry) {
        sentLogIDs = Array((sentLogIDs + [entry.id]).suffix(20))
        send(.logShift(entry))
        celebration = Date()
        undoableEntry = entry
    }

    /// Recent logs sent to the phone, to match against the ones it couldn't save.
    private var sentLogIDs: [UUID] {
        get { (UserDefaults.standard.stringArray(forKey: "tiptrack.watch.sentLogs") ?? []).compactMap(UUID.init) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: "tiptrack.watch.sentLogs") }
    }

    /// Set when the phone reports that a shift logged here wasn't saved.
    var logFailure: String?

    func undoLastLog() {
        guard let entry = undoableEntry else { return }
        undoableEntry = nil
        send(.undoLog(id: entry.id))
    }

    func dismissUndo(for id: UUID) {
        if undoableEntry?.id == id { undoableEntry = nil }
    }

    private func apply(_ change: (inout WatchPhoneState) -> Void) {
        change(&state)
        cache()
    }

    private func receive(_ data: Data) {
        guard let received = try? JSONDecoder().decode(WatchPhoneState.self, from: data) else { return }
        let failed = sentLogIDs.filter { (received.rejectedLogIDs ?? []).contains($0) }
        if !failed.isEmpty {
            sentLogIDs.removeAll { failed.contains($0) }
            if undoableEntry.map({ failed.contains($0.id) }) == true { undoableEntry = nil }
            logFailure = "Your iPhone couldn't save a shift logged on this watch. Please log it again."
        }
        // Commands still queued for the phone would be undone by its older state.
        guard pendingCount == 0 else {
            // Applied in full once the queue drains, so the watch ends up matching the phone.
            deferredState = data
            apply {
                $0.jobs = received.jobs
                $0.summary = received.summary
                $0.earningsHidden = received.earningsHidden
                $0.options = received.options
                $0.upcoming = received.upcoming
                $0.weekEnd = received.weekEnd
            }
            return
        }
        state = received
        hasPhoneState = true
        cache()
    }

    /// The phone's latest full state, held while queued commands are still on their way.
    private var deferredState: Data?

    private func cache() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func refreshPendingCount() {
        pendingCount = WCSession.default.outstandingUserInfoTransfers.filter(\.isTransferring).count
    }

    private static let attemptKey = "attempt"

    private func send(_ command: WatchCommand) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(command) else { return }
        let session = WCSession.default
        let payload: [String: Any] = [WatchSyncKey.command: data]
        // Once anything is queued, queue everything after it too, so the phone receives
        // commands in the order they were made (a direct End could otherwise beat a queued Start).
        refreshPendingCount()
        guard session.activationState == .activated, session.isReachable, pendingCount == 0 else {
            session.transferUserInfo(payload)
            refreshPendingCount()
            return
        }
        session.sendMessage(payload, replyHandler: { reply in
            let state = reply[WatchSyncKey.state] as? Data
            Task { @MainActor in
                if let state { WatchSessionStore.shared.receive(state) }
            }
        }, errorHandler: { _ in
            // The phone dropped out mid-send; queue it instead so it isn't lost.
            Task { @MainActor in
                WCSession.default.transferUserInfo(payload)
                WatchSessionStore.shared.refreshPendingCount()
            }
        })
    }
}

extension WatchSessionStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?) {
        let data = session.receivedApplicationContext[WatchSyncKey.state] as? Data
        Task { @MainActor in
            refreshPendingCount()
            if let data { receive(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchSyncKey.state] as? Data else { return }
        Task { @MainActor in receive(data) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let failed = error != nil
        nonisolated(unsafe) let userInfo = userInfoTransfer.userInfo
        Task { @MainActor in
            // A failed log or undo is retried a few times rather than dropped, since the watch
            // already showed it as done; both are safe to deliver late. Timer starts and ends
            // aren't, since a retry would land behind newer ones; the phone's state settles those.
            if failed, let command = userInfo[WatchSyncKey.command] as? Data,
               let decoded = try? JSONDecoder().decode(WatchCommand.self, from: command) {
                let attempt = (userInfo[Self.attemptKey] as? Int ?? 0) + 1
                let retriable: Bool
                switch decoded {
                case .logShift, .undoLog: retriable = true
                case .startShift, .endShift: retriable = false
                }
                if retriable && attempt <= 3 {
                    WCSession.default.transferUserInfo([WatchSyncKey.command: command, Self.attemptKey: attempt])
                }
            }
            refreshPendingCount()
            if pendingCount == 0, let data = deferredState {
                deferredState = nil
                receive(data)
            }
        }
    }
}

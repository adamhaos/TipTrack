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
    var summary: WatchEarningsSummary? { state.summary }
    var earningsHidden: Bool { state.earningsHidden ?? false }
    var options: WatchDisplayOptions { state.options ?? WatchDisplayOptions() }
    var upcoming: [WatchUpcomingShift] { (state.upcoming ?? []).filter { $0.end > Date() } }
    /// Upcoming shifts through the end of the person's week.
    var upcomingThisWeek: [WatchUpcomingShift] {
        guard let weekEnd = state.weekEnd else { return upcoming }
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
        send(.endShift)
        return ended
    }

    func clearCelebration() {
        celebration = nil
    }

    /// The shift just logged, while its Undo is still offered.
    private(set) var undoableEntry: WatchShiftEntry?

    func log(_ entry: WatchShiftEntry) {
        send(.logShift(entry))
        celebration = Date()
        undoableEntry = entry
    }

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
        // Commands still queued for the phone would be undone by its older state.
        guard pendingCount == 0 else {
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

    private func cache() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func refreshPendingCount() {
        pendingCount = WCSession.default.outstandingUserInfoTransfers.filter(\.isTransferring).count
    }

    private func send(_ command: WatchCommand) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(command) else { return }
        let session = WCSession.default
        let payload = [WatchSyncKey.command: data]
        guard session.activationState == .activated, session.isReachable else {
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
        Task { @MainActor in
            refreshPendingCount()
            // Pick up the state the phone published while the queue was draining.
            if pendingCount == 0, let data = WCSession.default.receivedApplicationContext[WatchSyncKey.state] as? Data {
                receive(data)
            }
        }
    }
}

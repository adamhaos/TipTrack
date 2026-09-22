import Foundation
import Observation
import SwiftData
import WatchConnectivity

// Phone side of the watch app: applies watch commands to the shared store and
// publishes jobs and the live shift as the watch's application context.
@MainActor @Observable
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()
    @ObservationIgnored private var container: ModelContainer?
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    private(set) var lastSynced: Date?

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish() {
        guard WCSession.isSupported(), let state = currentState() else { return }
        let session = WCSession.default
        refreshStatus()
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(state) else { return }
        do {
            try session.updateApplicationContext([WatchSyncKey.state: data])
            lastSynced = Date()
        } catch {}
    }

    private func refreshStatus() {
        let session = WCSession.default
        let active = session.activationState == .activated
        isPaired = active && session.isPaired
        isWatchAppInstalled = active && session.isWatchAppInstalled
        isReachable = active && session.isReachable
    }

    private static func option(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    private func currentState() -> WatchPhoneState? {
        guard let container else { return nil }
        let jobs = (try? container.mainContext.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\Job.name)]))) ?? []
        let live = LiveShiftManager.shared.current.map {
            WatchLiveShift(id: $0.id, startedAt: $0.startedAt, jobID: $0.jobID, jobName: $0.jobName)
        }
        let hidden = UserDefaults.standard.bool(forKey: "privacyEnabled")
        let showEarnings = Self.option(FeatureKeys.watchShowEarnings)
        return WatchPhoneState(jobs: jobs.map {
            WatchJob(id: $0.id, name: $0.name, colorHex: $0.colorHex, isDefault: $0.isDefault, iconName: $0.iconName)
        }, liveShift: live, summary: hidden || !showEarnings ? nil : summary(container: container),
            earningsHidden: hidden && showEarnings,
            options: WatchDisplayOptions(showTotals: Self.option(FeatureKeys.watchShowTotals),
                showLiveTimer: Self.option(FeatureKeys.watchShowLiveTimer, default: false)),
            upcoming: upcoming(jobs: jobs), weekEnd: weekEnd)
    }

    private var weekEnd: Date? {
        Calendar.preferredWeek.dateInterval(of: .weekOfYear, for: Date())?.end
    }

    // Everything left this week for the watch's Up Next list, and always the next
    // three so the home card isn't empty late in the week.
    private func upcoming(jobs: [Job], now: Date = Date()) -> [WatchUpcomingShift] {
        let weekEnd = weekEnd ?? now
        return ScheduleStore.shared.events
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
            .enumerated()
            .filter { $0.offset < 3 || $0.element.start < weekEnd }
            .map { _, event in
                WatchUpcomingShift(id: event.id, jobID: event.jobID,
                    jobName: jobs.first { $0.id == event.jobID }?.name ?? event.title,
                    start: event.start, end: event.end)
            }
    }

    private func summary(container: ModelContainer, now: Date = Date()) -> WatchEarningsSummary {
        let shifts = (try? container.mainContext.fetch(FetchDescriptor<Shift>(
            predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let calendar = Calendar.preferredWeek
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }.map { day in
            let dayShifts = shifts.filter { calendar.isDate($0.date, inSameDayAs: day) }
            return WatchDaySummary(date: day, total: dayShifts.reduce(0) { $0 + $1.totalEarnings },
                hours: dayShifts.reduce(0) { $0 + ($1.hoursWorked ?? 0) }, shifts: dayShifts.count,
                scheduled: ScheduleStore.shared.events.contains { calendar.isDate($0.start, inSameDayAs: day) })
        }
        func totals(_ matching: [Shift]) -> WatchPeriodTotals {
            WatchPeriodTotals(credit: matching.reduce(0) { $0 + $1.creditEarnings },
                netCash: matching.reduce(0) { $0 + $1.netCash }, shifts: matching.count)
        }
        let weekShifts = shifts.filter { shift in week.contains { calendar.isDate(shift.date, inSameDayAs: $0.date) } }
        let monthShifts = shifts.filter { Calendar.current.isDate($0.date, equalTo: now, toGranularity: .month) }
        let last = shifts.filter { $0.date < now }.max { $0.date < $1.date }
        return WatchEarningsSummary(week: week, weekTotals: totals(weekShifts),
            month: Calendar.current.dateInterval(of: .month, for: now)?.start ?? now, monthTotals: totals(monthShifts),
            lastShiftDate: last?.date, lastShiftTotal: last?.totalEarnings)
    }

    private func handle(_ data: Data) async -> Data? {
        guard let container, let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else { return nil }
        let context = container.mainContext
        let jobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        // A widget or Siri action may have changed the live shift while the app was suspended.
        LiveShiftManager.shared.reloadSharedState()
        switch command {
        case let .startShift(id, jobID, at):
            let job = jobs.first { $0.id == jobID } ?? jobs.first(where: \.isDefault) ?? jobs.first
            await LiveShiftManager.shared.start(job: job, id: id, startedAt: at)
        case .endShift:
            await LiveShiftManager.shared.stop()
        case let .logShift(entry):
            save(entry, jobs: jobs, context: context)
        case let .undoLog(id):
            undo(id, context: context)
        }
        return currentState().flatMap { try? JSONEncoder().encode($0) }
    }

    // Shifts undone on the watch. A queued log can arrive after its own undo, so it's
    // remembered here and skipped instead of being saved again.
    private static let undoneKey = "watch.undoneShiftIDs"
    private var undoneIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.undoneKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(50)), forKey: Self.undoneKey) }
    }

    private func undo(_ id: UUID, context: ModelContext) {
        undoneIDs.append(id.uuidString)
        guard let shift = try? context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id })).first else { return }
        context.delete(shift)
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        publishWidgets(context: context)
    }

    private func publishWidgets(context: ModelContext) {
        let shifts = (try? context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\Shift.date)]))) ?? []
        WidgetSnapshotWriter.publish(shifts: shifts)
    }

    private func save(_ entry: WatchShiftEntry, jobs: [Job], context: ModelContext) {
        guard !undoneIDs.contains(entry.id.uuidString) else { return }
        let id = entry.id
        let existing = (try? context.fetchCount(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id }))) ?? 0
        let values = [entry.creditTip, entry.cashTip, entry.tipOut, entry.hoursWorked ?? 0]
        guard existing == 0, values.allSatisfy({ $0.isFinite && $0 >= 0 }), values.contains(where: { $0 > 0 }) else { return }
        context.insert(Shift(id: id, date: entry.date, creditTip: entry.creditTip, cashTip: entry.cashTip,
            barTipOut: entry.tipOut, hoursWorked: entry.hoursWorked.flatMap { $0 > 0 ? $0 : nil },
            job: jobs.first { $0.id == entry.jobID }))
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        // The app may have been launched in the background with no view to refresh the widgets.
        publishWidgets(context: context)
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?) {
        Task { @MainActor in publish() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in publish() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in refreshStatus() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to a different watch deactivates the old session; reactivate for the new one.
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[WatchSyncKey.command] as? Data else { return replyHandler([:]) }
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let state = await handle(data)
            reply(state.map { [WatchSyncKey.state: $0] } ?? [:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchSyncKey.command] as? Data else { return }
        Task { @MainActor in
            _ = await handle(data)
        }
    }
}

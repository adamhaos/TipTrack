import Foundation
import SwiftData
import Observation
import UserNotifications
import BackgroundTasks
import CryptoKit
import WidgetKit

@MainActor @Observable
final class ScheduleStore {
    static let shared = ScheduleStore()
    struct Cache: Codable {
        var events: [ScheduledShift] = []
        var refreshed: [String: Date] = [:]
        var sources: [String: String] = [:]
    }
    var events: [ScheduledShift] = []
    var status: [UUID: String] = [:]
    var refreshing = false
    var notificationMessage: String?
    private var cache = Cache()
    private var pendingRefresh = false
    private var scheduling = false
    private var pendingScheduling = false
    private let cacheURL = URL.applicationSupportDirectory.appendingPathComponent("schedule-cache.json")
    private struct WidgetScheduleItem: Codable {
        let id: String
        let jobName: String
        let start: Date
        let end: Date
    }
    init() {
        if let data = try? Data(contentsOf: cacheURL), let stored = try? JSONDecoder().decode(Cache.self, from: data) {
            cache = stored
            events = stored.events
        }
    }
    func refreshedAt(_ job: Job) -> Date? { cache.refreshed[job.id.uuidString] }
    func resetDownloadedSchedule() {
        events = []
        status = [:]
        notificationMessage = nil
        cache = Cache()
        try? FileManager.default.removeItem(at: cacheURL)
        UserDefaults(suiteName: "group.atm.TipTrack")?.removeObject(forKey: "tiptrack.widget.schedule")
        WidgetCenter.shared.reloadAllTimelines()
    }
    func requestBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "atm.TipTrack.scheduleRefresh")
        request.earliestBeginDate = Date().addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    func backgroundRefresh(container: ModelContainer) async {
        await refresh(context: container.mainContext)
    }
    func refresh(context: ModelContext) async {
        guard !refreshing else { pendingRefresh = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            pendingRefresh = false
            guard let fetchedJobs = try? context.fetch(FetchDescriptor<Job>()) else { break }
            let validIDs = Set(fetchedJobs.filter { !$0.calendarFeeds.isEmpty }.map(\.id))
            events.removeAll { !validIDs.contains($0.jobID) }
            for job in fetchedJobs where !job.calendarFeeds.isEmpty {
                if Task.isCancelled { return }
                let feeds = job.calendarFeeds
                let sourceText = feeds.map { "\($0.id)|\($0.url)|\($0.filter)" }.joined(separator: "||")
                let source = SHA256.hash(data: Data(sourceText.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                if cache.sources[job.id.uuidString] != source {
                    events.removeAll { $0.jobID == job.id }
                    cache.refreshed[job.id.uuidString] = nil
                }
                var importedForJob: [ScheduledShift] = []
                var failures: [String] = []
                var failedFeedIDs = Set<UUID>()
                for feed in feeds {
                    guard let url = CalendarFeed.url(feed.url) else {
                        failures.append(feed.name)
                        failedFeedIDs.insert(feed.id)
                        continue
                    }
                    do {
                        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
                        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                              response.url?.scheme == "https" else { throw CalendarFeed.FeedError.invalid }
                        var data = Data()
                        for try await byte in bytes {
                            guard data.count < 2_000_000 else { throw CalendarFeed.FeedError.invalid }
                            data.append(byte)
                        }
                        guard let text = String(data: data, encoding: .utf8) else { throw CalendarFeed.FeedError.invalid }
                        var imported = try CalendarFeed.parse(text, jobID: job.id)
                        for index in imported.indices { imported[index].feedID = feed.id }
                        if !feed.filter.isEmpty {
                            imported = imported.filter { $0.title.localizedCaseInsensitiveContains(feed.filter) }
                        }
                        importedForJob.append(contentsOf: imported)
                    } catch {
                        failures.append(feed.name)
                        failedFeedIDs.insert(feed.id)
                    }
                }
                if failures.count < feeds.count {
                    if !failures.isEmpty {
                        // Keep the last downloaded shifts from feeds that failed, but let
                        // successful feeds drop shifts that were removed from them.
                        let importedIDs = Set(importedForJob.map(\.id))
                        importedForJob.append(contentsOf: events.filter { event in
                            guard event.jobID == job.id, !importedIDs.contains(event.id) else { return false }
                            return event.feedID.map(failedFeedIDs.contains) ?? true
                        })
                    }
                    events.removeAll { $0.jobID == job.id }
                    var unique: [String: ScheduledShift] = [:]
                    for event in importedForJob { unique[event.id] = event }
                    events.append(contentsOf: unique.values)
                    cache.refreshed[job.id.uuidString] = Date()
                    cache.sources[job.id.uuidString] = source
                    status[job.id] = failures.isEmpty
                        ? "\(importedForJob.count) shifts from \(feeds.count) calendar\(feeds.count == 1 ? "" : "s")"
                        : "\(importedForJob.count) shifts downloaded; \(failures.count) calendar\(failures.count == 1 ? "" : "s") could not refresh"
                } else {
                    status[job.id] = "Could not refresh any calendar. Previously downloaded shifts are retained."
                }
            }
            events.sort { $0.start < $1.start }
            cache.events = events
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(cache).write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { notificationMessage = "The downloaded schedule could not be saved for offline use." }
            publishWidgetSchedule(jobs: fetchedJobs)
            await scheduleReminders(context: context)
        } while pendingRefresh && !Task.isCancelled
        requestBackgroundRefresh()
    }
    private func publishWidgetSchedule(jobs: [Job]) {
        let names = Dictionary(jobs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let items = events.filter { !$0.allDay }.map {
            WidgetScheduleItem(id: $0.id, jobName: names[$0.jobID] ?? "Job", start: $0.start, end: $0.end)
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults(suiteName: "group.atm.TipTrack")?.set(data, forKey: "tiptrack.widget.schedule")
        WidgetCenter.shared.reloadAllTimelines()
    }
    func loggedEventIDs(shifts: [Shift]) -> Set<String> {
        let active = shifts.filter { $0.deletedAt == nil }
        var matched = Set(active.compactMap(\.scheduledEventID))
        // Older/manual entries match one event per job and calendar day, not every event that day.
        for shift in active where shift.scheduledEventID == nil {
            if let event = events.first(where: {
                !matched.contains($0.id) && $0.jobID == shift.job?.id &&
                    Calendar.current.isDate($0.start, inSameDayAs: shift.date)
            }) { matched.insert(event.id) }
        }
        return matched
    }
    func scheduleReminders(context: ModelContext) async {
        guard !scheduling else { pendingScheduling = true; return }
        scheduling = true
        defer { scheduling = false }
        repeat {
            pendingScheduling = false
            await updateReminders(context: context)
        } while pendingScheduling && !Task.isCancelled
    }
    private func updateReminders(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("scheduled.") }.map(\.identifier))
        let jobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            notificationMessage = jobs.contains(where: \.endReminder) ? "Allow notifications in iOS Settings for shift logging reminders." : nil
            return
        }
        let shifts = (try? context.fetch(FetchDescriptor<Shift>())) ?? []
        let matched = loggedEventIDs(shifts: shifts)
        var requests: [(Date, UNNotificationRequest)] = []
        let startReminders = UserDefaults.standard.bool(forKey: FeatureKeys.preShiftReminder)
        let startLead = max(5, UserDefaults.standard.integer(forKey: "preShiftReminderMinutes"))
        for event in events where !event.allDay && !matched.contains(event.id) {
            guard let job = jobs.first(where: { $0.id == event.jobID }) else { continue }
            let digest = SHA256.hash(data: Data(event.id.utf8)).map { String(format: "%02x", $0) }.joined()
            if startReminders {
                let fire = event.start.addingTimeInterval(Double(-startLead) * 60)
                if fire > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = "Shift starting soon!"
                    content.body = "Your shift at \(job.name) starts in \(startLead) minutes."
                    content.sound = .default
                    content.userInfo = ["eventID": event.id, "jobID": job.id.uuidString]
                    let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second], from: fire), repeats: false)
                    requests.append((fire, UNNotificationRequest(identifier: "scheduled.start." + digest, content: content, trigger: trigger)))
                }
            }
            if job.endReminder {
                if let fire = ShiftLoggingReminderTiming.fireDate(
                    start: event.start, end: event.end, offsetMinutes: job.reminderDelay, now: Date()
                ) {
                    let content = UNMutableNotificationContent()
                    content.title = "Log your shift"
                    content.body = ShiftLoggingReminderTiming.message(jobName: job.name, offsetMinutes: job.reminderDelay)
                    content.sound = .default
                    content.userInfo = ["eventID": event.id, "jobID": job.id.uuidString]
                    let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second], from: fire), repeats: false)
                    requests.append((fire, UNNotificationRequest(identifier: "scheduled.end." + digest, content: content, trigger: trigger)))
                }
            }
        }
        // Reserve space for seven existing repeating reminders and system scheduling limits.
        notificationMessage = requests.count > 50 ? "The next 50 shift reminders are scheduled. Open TipTrack to replenish them." : nil
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(50) {
            do { try await center.add(request) } catch { notificationMessage = "Some shift reminders could not be scheduled." }
        }
    }
}

@MainActor @Observable
final class AppRoute: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppRoute()
    var logRequest: UUID?
    var historyRequest: UUID?
    var calendarRequest: UUID?
    var timerStartRequest: UUID?
    var timerStopRequest: UUID?
    var event: ScheduledShift?
    var logDate: Date?
    var logJobID: UUID?
    func openLog(event: ScheduledShift? = nil, date: Date? = nil, jobID: UUID? = nil) {
        self.event = event
        logDate = date
        logJobID = jobID
        logRequest = UUID()
    }
    func openHistory() { historyRequest = UUID() }
    func openCalendar() { calendarRequest = UUID() }
    func openTimerStart() { timerStartRequest = UUID() }
    func openTimerStop() { timerStopRequest = UUID() }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["eventID"] as? String
        openLog(event: ScheduleStore.shared.events.first { $0.id == id })
    }
}

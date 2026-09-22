import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

fileprivate struct AdvancedStoredShift: Codable {
    let date: Date
    let creditTip: Double
    let cashTip: Double
    let barTipOut: Double
    var hoursWorked: Double? = nil
    var hourlyRate: Double? = nil
    var total: Double { creditTip + (hoursWorked ?? 0) * (hourlyRate ?? 0) + cashTip - barTipOut }
}
fileprivate struct AdvancedSnapshot: Codable { let shifts: [AdvancedStoredShift] }
fileprivate struct AdvancedScheduleItem: Codable, Identifiable {
    let id: String
    let jobName: String
    let start: Date
    let end: Date
}

fileprivate enum AdvancedWidgetData {
    static let defaults = UserDefaults(suiteName: "group.atm.TipTrack")
    static var shifts: [AdvancedStoredShift] {
        guard let data = defaults?.data(forKey: "tiptrack.widget.snapshot") else { return [] }
        return (try? JSONDecoder().decode(AdvancedSnapshot.self, from: data).shifts) ?? []
    }
    static var schedule: [AdvancedScheduleItem] {
        guard let data = defaults?.data(forKey: "tiptrack.widget.schedule") else { return [] }
        return (try? JSONDecoder().decode([AdvancedScheduleItem].self, from: data)) ?? []
    }
}

fileprivate struct AdvancedWidgetEntry: TimelineEntry {
    let date: Date
    let shifts: [AdvancedStoredShift]
    let schedule: [AdvancedScheduleItem]
}

fileprivate struct AdvancedWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AdvancedWidgetEntry {
        let now = Date()
        return AdvancedWidgetEntry(date: now,
            shifts: [AdvancedStoredShift(date: now, creditTip: 145, cashTip: 42, barTipOut: 7)],
            schedule: [AdvancedScheduleItem(id: "preview", jobName: "Harbor Grill",
                start: now.addingTimeInterval(3600), end: now.addingTimeInterval(18000))])
    }
    func getSnapshot(in context: Context, completion: @escaping (AdvancedWidgetEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AdvancedWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(900))))
    }
    private func entry() -> AdvancedWidgetEntry {
        AdvancedWidgetEntry(date: Date(), shifts: AdvancedWidgetData.shifts, schedule: AdvancedWidgetData.schedule)
    }
}

fileprivate struct SevenDayCalendarWidgetView: View {
    let entry: AdvancedWidgetEntry
    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: entry.date)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Next 7 Days", systemImage: "calendar").font(.caption.bold())
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let logged = entry.shifts.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
                    let scheduled = entry.schedule.contains { Calendar.current.isDate($0.start, inSameDayAs: day) }
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.bold())
                        Text(day.formatted(.dateTime.day())).font(.caption)
                        Circle().fill(logged ? Color.green : (scheduled ? Color.blue : Color.secondary.opacity(0.2)))
                            .frame(width: 7, height: 7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Calendar.current.isDateInToday(day) ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack { Label("Scheduled", systemImage: "circle.fill").foregroundStyle(.blue); Label("Logged", systemImage: "circle.fill").foregroundStyle(.green) }
                .font(.caption2)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "tiptrack://calendar"))
    }
}

struct TipTrackSevenDayWidget: Widget {
    let kind = "TipTrackSevenDayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AdvancedWidgetProvider()) { SevenDayCalendarWidgetView(entry: $0) }
            .configurationDisplayName("Seven-Day Calendar")
            .description("See scheduled and completed shifts for the next seven days.")
            .supportedFamilies([.systemMedium])
    }
}

fileprivate struct TonightWidgetView: View {
    let entry: AdvancedWidgetEntry
    private var tonight: AdvancedScheduleItem? {
        entry.schedule.first { $0.end > entry.date && Calendar.current.isDateInToday($0.start) }
    }
    private var forecast: Double? {
        let recent = entry.shifts.sorted { $0.date > $1.date }.prefix(20)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.total } / Double(recent.count)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Tonight", systemImage: "moon.stars.fill").font(.caption.bold()).foregroundStyle(.indigo)
            if let tonight {
                Text(tonight.jobName).font(.headline).lineLimit(1)
                Text("\(tonight.start.formatted(date: .omitted, time: .shortened))–\(tonight.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                if let forecast { Text("Typical: \(forecast, format: .currency(code: "USD"))").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Link(destination: URL(string: "tiptrack://log")!) { Label("Log Shift", systemImage: "plus.circle.fill").font(.caption.bold()) }
            } else {
                Spacer()
                Text("No shift scheduled tonight").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct TipTrackTonightWidget: Widget {
    let kind = "TipTrackTonightWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AdvancedWidgetProvider()) { TonightWidgetView(entry: $0) }
            .configurationDisplayName("Tonight")
            .description("Tonight’s job, time, typical earnings, and quick entry.")
            .supportedFamilies([.systemSmall])
    }
}

struct TipTrackQuickEntryWidget: Widget {
    let kind = "TipTrackQuickEntryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AdvancedWidgetProvider()) { _ in
            VStack(alignment: .leading, spacing: 8) {
                Label("Quick Actions", systemImage: "bolt.fill").font(.subheadline.bold()).lineLimit(1)
                Button(intent: WidgetRouteIntent(destination: .start)) {
                    Label("Start Timer", systemImage: "timer").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(intent: WidgetRouteIntent(destination: .log)) {
                    Label("Log Shift", systemImage: "plus.circle").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.small)
                Spacer(minLength: 0)
            }
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick Entry")
        .description("Start a timer or log a shift.")
        .supportedFamilies([.systemSmall])
    }
}

enum WidgetRouteDestination: String, AppEnum {
    case start, stop, log, history, calendar
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "TipTrack Route")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .start: "Start Shift", .stop: "End Shift", .log: "Log Shift",
        .history: "View History", .calendar: "Shift Calendar"
    ]
}

struct WidgetRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open TipTrack"
    static let isDiscoverable = false
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Opens") var destination: WidgetRouteDestination
    init() { destination = .log }
    init(destination: WidgetRouteDestination) { self.destination = destination }
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.atm.TipTrack")?.set(destination.rawValue, forKey: "tiptrack.pendingRoute")
        return .result()
    }
}

nonisolated struct LiveShiftAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var startedAt: Date
        var jobName: String
        var jobColorHex: String?
        var jobIcon: String?
    }
    var shiftID: UUID
}

private extension LiveShiftAttributes.ContentState {
    var elapsed: ClosedRange<Date> { startedAt...Date.distantFuture }
    var icon: String { jobIcon ?? "briefcase.fill" }

    // Activities started before the job color was stored fall back to green.
    var tint: Color {
        let clean = (jobColorHex ?? "").trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard clean.count == 6, Scanner(string: clean).scanHexInt64(&value) else { return .green }
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

private struct LiveShiftJobBadge: View {
    let state: LiveShiftAttributes.ContentState
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: state.icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(state.tint)
            .frame(width: size, height: size)
            .background(state.tint.opacity(0.22), in: Circle())
            .overlay(Circle().stroke(state.tint.opacity(0.5), lineWidth: 1))
    }
}

private struct LiveShiftEndButton: View {
    var body: some View {
        Link(destination: URL(string: "tiptrack://stop")!) {
            Label("End & Log Tips", systemImage: "stop.fill")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(Color.red, in: Capsule())
        }
    }
}

struct TipTrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveShiftAttributes.self) { context in
            let state = context.state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    LiveShiftJobBadge(state: state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.jobName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("On the clock since \(state.startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(timerInterval: state.elapsed, countsDown: false)
                        .font(.system(.title, design: .rounded).monospacedDigit().bold())
                        .foregroundStyle(state.tint)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130, alignment: .trailing)
                        .lineLimit(1)
                }
                LiveShiftEndButton()
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveShiftJobBadge(state: state, size: 46)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: state.elapsed, countsDown: false)
                        .font(.system(.title2, design: .rounded).monospacedDigit().bold())
                        .foregroundStyle(state.tint)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, maxHeight: .infinity, alignment: .trailing)
                        .lineLimit(1)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.jobName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Since \(state.startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveShiftEndButton()
                        .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: state.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.tint)
                    .padding(.leading, 2)
            } compactTrailing: {
                // A fixed width keeps the island from stretching as the timer gains digits.
                Text(timerInterval: state.elapsed, countsDown: false)
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(state.tint)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
            } minimal: {
                Image(systemName: "timer")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(state.tint)
            }
            .keylineTint(state.tint)
        }
    }
}

fileprivate struct NextShiftLockScreenView: View {
    let entry: AdvancedWidgetEntry

    private var nextShift: AdvancedScheduleItem? {
        entry.schedule.first { $0.end > entry.date }
    }

    var body: some View {
        Group {
            if let nextShift {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar.badge.clock").font(.caption2)
                        Text("Next").font(.caption2)
                        Spacer(minLength: 2)
                        Text(nextShift.start, format: .dateTime.weekday(.narrow).month(.defaultDigits).day())
                            .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.55)
                    }
                    Text(nextShift.jobName).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(nextShift.start.formatted(date: .omitted, time: .shortened)) – \(nextShift.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.55)
                }
            } else {
                Label("No upcoming shift", systemImage: "calendar")
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct TipTrackNextShiftLockWidget: Widget {
    let kind = "TipTrackNextShiftLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AdvancedWidgetProvider()) { NextShiftLockScreenView(entry: $0) }
            .configurationDisplayName("Next Shift")
            .description("See your next scheduled shift on the Lock Screen.")
            .supportedFamilies([.accessoryRectangular])
    }
}

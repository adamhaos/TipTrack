import AppIntents
import SwiftUI
import WidgetKit

enum SummaryPeriod: String, AppEnum {
    case weekly, monthly
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.weekly: "This Week", .monthly: "This Month"]
    var title: String { self == .weekly ? "This Week" : "This Month" }
}
enum SummaryStyle: String, AppEnum {
    case gradient, minimal, cards
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Style")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.gradient: "Gradient", .minimal: "Minimal", .cards: "Cards"]
}
enum SummaryAccent: String, AppEnum {
    case green, blue, purple, orange
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Accent")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.green: "Green", .blue: "Blue", .purple: "Purple", .orange: "Orange"]
    var color: Color {
        switch self { case .green: .green; case .blue: .blue; case .purple: .purple; case .orange: .orange }
    }
}
enum SummaryLayout: String, AppEnum {
    case detailed, compact, totalOnly, hidden
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Layout")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .detailed: "Detailed", .compact: "Compact", .totalOnly: "Total Only", .hidden: "Hidden Amounts"
    ]
}
struct SummaryConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tip Summary"
    static let description = IntentDescription("Choose your period, style, color, and privacy.")
    @Parameter(title: "Period", default: .weekly) var period: SummaryPeriod
    @Parameter(title: "Style", default: .gradient) var style: SummaryStyle
    @Parameter(title: "Accent", default: .green) var accent: SummaryAccent
    @Parameter(title: "Layout", default: .detailed) var layout: SummaryLayout
}
private struct StoredShift: Codable {
    let date: Date
    let creditTip: Double
    let cashTip: Double
    let barTipOut: Double
    let hoursWorked: Double?
    let hourlyRate: Double?
    var netCash: Double { cashTip - barTipOut }
    var basePay: Double { (hoursWorked ?? 0) * (hourlyRate ?? 0) }
    var creditEarnings: Double { creditTip + basePay }
    var total: Double { creditEarnings + netCash }
}
private struct StoredSnapshot: Codable { let shifts: [StoredShift] }
struct SummaryEntry: TimelineEntry {
    let date: Date
    var period: SummaryPeriod = .weekly
    var style: SummaryStyle = .gradient
    var accent: SummaryAccent = .green
    var layout: SummaryLayout = .detailed
    var credit: Double = 0
    var netCash: Double = 0
    var hourly: Double?
    var count: Int = 0
    var hidden = false
    var needsOpen = false
    var total: Double { credit + netCash }
}
struct TipTrackSummaryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), credit: 486, netCash: 214, hourly: 28.57, count: 4)
    }
    func snapshot(for configuration: SummaryConfigurationIntent, in context: Context) async -> SummaryEntry {
        makeEntry(configuration, date: Date())
    }
    func timeline(for configuration: SummaryConfigurationIntent, in context: Context) async -> Timeline<SummaryEntry> {
        let now = Date()
        var calendar = Calendar.current
        calendar.firstWeekday = UserDefaults(suiteName: "group.atm.TipTrack")?
            .object(forKey: "calendar.weekStart") as? Int ?? 2
        let component: Calendar.Component = configuration.period == .weekly ? .weekOfYear : .month
        let boundary = calendar.dateInterval(of: component, for: now)?.end ?? now.addingTimeInterval(86400)
        return Timeline(entries: [makeEntry(configuration, date: now), makeEntry(configuration, date: boundary)],
            policy: .after(min(boundary, now.addingTimeInterval(1800))))
    }
    private func makeEntry(_ config: SummaryConfigurationIntent, date: Date) -> SummaryEntry {
        let defaults = UserDefaults(suiteName: "group.atm.TipTrack")
        let hidden = config.layout == .hidden || defaults?.bool(forKey: "privacyEnabled") == true
        var entry = SummaryEntry(date: date, period: config.period, style: config.style, accent: config.accent,
            layout: config.layout, hidden: hidden)
        guard !hidden else { return entry }
        guard let data = defaults?.data(forKey: "tiptrack.widget.snapshot"),
              let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data) else {
            entry.needsOpen = true
            return entry
        }
        var calendar = Calendar.current
        calendar.firstWeekday = UserDefaults(suiteName: "group.atm.TipTrack")?
            .object(forKey: "calendar.weekStart") as? Int ?? 2
        guard let interval = calendar.dateInterval(of: config.period == .weekly ? .weekOfYear : .month, for: date) else { return entry }
        let shifts = stored.shifts.filter { $0.date >= interval.start && $0.date < interval.end }
        entry.credit = shifts.reduce(0) { $0 + $1.creditEarnings }
        entry.netCash = shifts.reduce(0) { $0 + $1.netCash }
        entry.count = shifts.count
        let timed = shifts.filter { ($0.hoursWorked ?? 0) > 0 }
        let hours = timed.reduce(0) { $0 + ($1.hoursWorked ?? 0) }
        entry.hourly = hours > 0 ? timed.reduce(0) { $0 + $1.total } / hours : nil
        return entry
    }
}
struct TipTrackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry
    private var foreground: Color { entry.style == .gradient ? .white : .primary }
    var body: some View {
        VStack(alignment: .leading, spacing: entry.layout == .compact ? 4 : 8) {
            HStack {
                Text(entry.period.title).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: entry.hidden ? "eye.slash" : "banknote").font(.caption)
            }.foregroundStyle(foreground.opacity(0.8))
            Spacer(minLength: 0)
            if entry.hidden {
                Text("Earnings hidden").font(.headline).foregroundStyle(foreground)
                Text("Open TipTrack to unlock").font(.caption2).foregroundStyle(foreground.opacity(0.8))
            } else if entry.needsOpen {
                Text("Open TipTrack to sync").font(.headline).foregroundStyle(foreground)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.total, format: .currency(code: "USD"))
                            .font(.system(size: entry.layout == .compact ? 24 : 30, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(foreground)
                            .privacySensitive()
                        if entry.layout != .totalOnly {
                            Text("\(entry.count) \(entry.count == 1 ? "shift" : "shifts")").font(.caption2)
                                .foregroundStyle(foreground.opacity(0.8))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if family == .systemMedium && entry.layout == .detailed {
                        VStack(alignment: .leading, spacing: 5) {
                            metric("Credit", entry.credit)
                            metric("Net Cash", entry.netCash)
                            if let hourly = entry.hourly { metric("Per Hour", hourly) }
                        }
                        .padding(entry.style == .cards ? 8 : 0)
                        .background(entry.style == .cards ? entry.accent.color.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: "tiptrack://log")!) {
                Label("Log Shift", systemImage: "plus.circle.fill").font(.caption.bold())
                    .foregroundStyle(foreground)
            }
        }
        .containerBackground(for: .widget) {
            if entry.style == .gradient {
                LinearGradient(colors: [entry.accent.color.opacity(0.9), .black],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color(uiColor: .systemBackground)
                    .overlay(entry.accent.color.opacity(entry.style == .cards ? 0.04 : 0.1))
            }
        }
        .widgetURL(URL(string: "tiptrack://log"))
    }
    private func metric(_ title: String, _ amount: Double) -> some View {
        HStack {
            Text(title).foregroundStyle(foreground.opacity(0.7))
            Spacer(minLength: 4)
            Text(amount, format: .currency(code: "USD")).bold().foregroundStyle(foreground).privacySensitive()
        }.font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
    }
}
struct TipTrackSummaryWidget: Widget {
    let kind = "TipTrackSummaryWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SummaryConfigurationIntent.self, provider: TipTrackSummaryProvider()) {
            TipTrackWidgetView(entry: $0)
        }
        .configurationDisplayName("Tip Summary")
        .description("Weekly or monthly tips, your style, and quick shift entry.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

enum QuickActionDestination: String {
    case log, history, calendar

    var icon: String {
        switch self {
        case .log: "plus"
        case .history: "clock.arrow.circlepath"
        case .calendar: "calendar"
        }
    }

    var title: String {
        switch self {
        case .log: "Log Shift"
        case .history: "History"
        case .calendar: "Calendar"
        }
    }

    var url: URL { URL(string: "tiptrack://\(rawValue)")! }
}

struct QuickActionEntry: TimelineEntry {
    let date: Date
    let destination: QuickActionDestination
}

struct QuickActionProvider: TimelineProvider {
    let destination: QuickActionDestination

    func placeholder(in context: Context) -> QuickActionEntry {
        QuickActionEntry(date: Date(), destination: destination)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionEntry) -> Void) {
        completion(QuickActionEntry(date: Date(), destination: destination))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionEntry(date: Date(), destination: destination)], policy: .never))
    }
}

struct QuickActionWidgetView: View {
    let entry: QuickActionEntry

    var body: some View {
        Link(destination: entry.destination.url) {
            Image(systemName: entry.destination.icon)
                .font(.title2.weight(.semibold))
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel(entry.destination.title)
    }
}

struct TipTrackLogShortcutWidget: Widget {
    let kind = "TipTrackLogShortcutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionProvider(destination: .log)) {
            QuickActionWidgetView(entry: $0)
        }
        .configurationDisplayName("Log Shift")
        .description("Open Log Shift from your Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TipTrackHistoryShortcutWidget: Widget {
    let kind = "TipTrackHistoryShortcutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionProvider(destination: .history)) {
            QuickActionWidgetView(entry: $0)
        }
        .configurationDisplayName("View History")
        .description("Open TipTrack history from your Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TipTrackCalendarShortcutWidget: Widget {
    let kind = "TipTrackCalendarShortcutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionProvider(destination: .calendar)) {
            QuickActionWidgetView(entry: $0)
        }
        .configurationDisplayName("Shift Calendar")
        .description("Open the shift calendar from your Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

fileprivate struct StoredScheduleItem: Codable, Identifiable {
    let id: String
    let jobName: String
    let start: Date
    let end: Date
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    fileprivate let shifts: [StoredScheduleItem]
}

struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        let now = Date()
        return UpcomingEntry(date: now, shifts: [
            StoredScheduleItem(id: "1", jobName: "Downtown Cafe", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(18000)),
            StoredScheduleItem(id: "2", jobName: "Harbor Grill", start: now.addingTimeInterval(90000), end: now.addingTimeInterval(108000))
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [entry(at: now)], policy: .after(now.addingTimeInterval(1800))))
    }

    private func entry(at date: Date) -> UpcomingEntry {
        let data = UserDefaults(suiteName: "group.atm.TipTrack")?.data(forKey: "tiptrack.widget.schedule")
        let stored = data.flatMap { try? JSONDecoder().decode([StoredScheduleItem].self, from: $0) } ?? []
        let end = Calendar.current.date(byAdding: .day, value: 5,
            to: Calendar.current.startOfDay(for: date)) ?? date.addingTimeInterval(432000)
        return UpcomingEntry(date: date,
            shifts: stored.filter { $0.end >= date && $0.start < end }.sorted { $0.start < $1.start })
    }
}

struct UpcomingShiftsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                UpcomingCalendarStrip(entry: entry)
            } else {
                UpcomingShiftList(shifts: Array(entry.shifts.prefix(3)))
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "tiptrack://calendar"))
    }
}

private struct UpcomingCalendarStrip: View {
    let entry: UpcomingEntry

    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: entry.date)
        return (0..<5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                UpcomingDayCard(
                    day: day,
                    shift: entry.shifts.first { Calendar.current.isDate($0.start, inSameDayAs: day) }
                )
            }
        }
    }
}

private struct UpcomingDayCard: View {
    let day: Date
    let shift: StoredScheduleItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(day, format: .dateTime.day())
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            if let shift {
                Text(shift.jobName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Text(shift.start, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(shift.end, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("No shift")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.secondary.opacity(Calendar.current.isDateInToday(day) ? 0.14 : 0.07),
            in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct UpcomingShiftList: View {
    let shifts: [StoredScheduleItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Upcoming Shifts", systemImage: "calendar")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if shifts.isEmpty {
                Spacer()
                Text("No shifts in the next 5 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(shifts) { shift in
                    UpcomingShiftRow(shift: shift)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct UpcomingShiftRow: View {
    let shift: StoredScheduleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(shift.start, format: .dateTime.weekday(.abbreviated))
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(shift.jobName)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(shift.start.formatted(date: .omitted, time: .shortened))–\(shift.end.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct TipTrackUpcomingWidget: Widget {
    let kind = "TipTrackUpcomingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingProvider()) { UpcomingShiftsView(entry: $0) }
            .configurationDisplayName("Upcoming Shifts")
            .description("See your next five days of scheduled shifts.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TipTrackWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TipTrackSummaryWidget()
        TipTrackUpcomingWidget()
        TipTrackLogShortcutWidget()
        TipTrackHistoryShortcutWidget()
        TipTrackCalendarShortcutWidget()
        TipTrackSevenDayWidget()
        TipTrackTonightWidget()
        TipTrackQuickEntryWidget()
        TipTrackLiveActivity()
        TipTrackNextShiftLockWidget()
    }
}

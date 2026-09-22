import SwiftUI
import WatchKit

struct WatchLogDraft: Hashable, Identifiable {
    var id = UUID()
    var date = Date()
    var jobID: UUID?
    var hours: Double?
}

// A compact take on the iPhone dashboard. The first page always fits one screen:
// today's earnings, Log Shift and what's up next. Week and month totals are the
// next page down (swipe or turn the Digital Crown).
struct WatchHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let store = WatchSessionStore.shared
    @State private var selectedJobID: UUID?
    @State private var logDraft: WatchLogDraft?
    @State private var isChoosingJob = false
    @State private var page = 0

    private var selectedJob: WatchJob? {
        store.jobs.first { $0.id == selectedJobID } ?? store.defaultJob
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                todayPage
                    .tag(0)
                if let summary = store.summary, store.options.showTotals {
                    // A fixed page, like the first one: both cards fit without scrolling.
                    WatchTotalsPage(summary: summary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .containerBackground(accent.gradient.opacity(0.25), for: .tabView)
                    .tag(1)
                }
            }
            .tabViewStyle(.verticalPage)
            .toolbar {
                // In the top-left corner, level with the clock.
                ToolbarItem(placement: .topBarLeading) {
                    Text("TipTrack3r")
                        .font(.footnote.bold())
                        .foregroundStyle(accent)
                }
            }
            .navigationDestination(item: $logDraft) { draft in
                WatchLogShiftView(draft: draft)
            }
            .sheet(isPresented: $isChoosingJob) {
                jobChooser
            }
        }
        // Over the whole stack, so the rain starts while the log form slides away.
        .overlay {
            if let burst = store.celebration, !reduceMotion {
                WatchCashRain(startedAt: burst)
                    .id(burst)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .task(id: burst) {
                        try? await Task.sleep(for: .seconds(2.2))
                        store.clearCelebration()
                    }
            }
        }
        // Like the phone: "Shift Saved · Undo" for five seconds after logging.
        .overlay(alignment: .bottom) {
            if let entry = store.undoableEntry {
                undoToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: entry.id) {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { store.dismissUndo(for: entry.id) }
                    }
            }
        }
        .animation(.snappy(duration: 0.25), value: store.undoableEntry?.id)
    }

    private var undoToast: some View {
        Button {
            withAnimation { store.undoLastLog() }
            WKInterfaceDevice.current().play(.click)
        } label: {
            HStack(spacing: 6) {
                Text("Shift Saved")
                    .foregroundStyle(.white)
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(.yellow)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.black.opacity(0.5), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shift saved. Undo")
        .padding(.bottom, 4)
        .ignoresSafeArea(edges: .bottom)
    }

    private var accent: Color {
        selectedJob.map { Color(watchHex: $0.colorHex) } ?? .accentColor
    }

    // Two upcoming shifts fit under Log Shift on 44mm and larger watches; smaller
    // screens, or a live timer row taking the room, show just the next one.
    private var upcomingLimit: Int {
        let roomy = WKInterfaceDevice.current().screenBounds.height >= 224
        let timerRow = store.liveShift != nil || store.options.showLiveTimer
        return roomy && !timerRow ? 2 : 1
    }

    private var todayPage: some View {
        // A running timer adds a row; on smaller watches drop the least important
        // lines first so nothing slides up under the title.
        ViewThatFits(in: .vertical) {
            todayContent(showsDetail: true, showsUpcoming: true)
            todayContent(showsDetail: false, showsUpcoming: true)
            todayContent(showsDetail: false, showsUpcoming: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The last card may sit in the bottom inset, as it did before the fit check.
        .ignoresSafeArea(.container, edges: .bottom)
        .containerBackground(accent.gradient.opacity(0.25), for: .tabView)
    }

    private func todayContent(showsDetail: Bool, showsUpcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = store.summary {
                WatchHeadline(summary: summary, showsDetail: showsDetail)
            } else if store.earningsHidden {
                WatchHiddenEarnings()
            }
            if let live = store.liveShift {
                activeShift(live)
            }
            logShiftButton
            if store.liveShift == nil && store.options.showLiveTimer {
                startTimerLink
            }
            if showsUpcoming {
                NavigationLink {
                    WatchWeekScheduleView(shifts: store.upcomingThisWeek, jobs: store.jobs)
                } label: {
                    WatchUpcomingShifts(shifts: store.upcoming, jobs: store.jobs, limit: upcomingLimit)
                }
                .buttonStyle(.plain)
            }
            status
        }
    }

    private func activeShift(_ live: WatchLiveShift) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(live.jobName)
                    .font(.caption2.bold())
                    .foregroundStyle(jobColor(live.jobID))
                    .lineLimit(1)
                Text(live.startedAt, style: .timer)
                    .font(.system(.title3, design: .rounded).monospacedDigit().bold())
            }
            // Timer text is greedy; give it the slack so the button stays pinned right.
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                endShift()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End Shift")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(Color.green.opacity(0.35), lineWidth: 1))
    }

    private var startTimerLink: some View {
        Button {
            if store.jobs.count > 1 { isChoosingJob = true } else { store.startShift(job: selectedJob) }
        } label: {
            Label("Start live timer", systemImage: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var jobChooser: some View {
        List(store.jobs) { job in
            Button {
                isChoosingJob = false
                selectedJobID = job.id
                store.startShift(job: job)
            } label: {
                Label(job.name, systemImage: job.iconName ?? "briefcase.fill")
                    .foregroundStyle(Color(watchHex: job.colorHex))
            }
        }
        .navigationTitle("Choose a Job")
    }

    private var logShiftButton: some View {
        let color = selectedJob.map { Color(watchHex: $0.colorHex) } ?? .accentColor
        return Button {
            logDraft = WatchLogDraft(jobID: selectedJob?.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Log Shift")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var status: some View {
        if !store.hasPhoneState {
            Text("Open TipTrack3r on your iPhone to sync your jobs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if store.pendingCount > 0 {
            Label("Waiting for iPhone", systemImage: "iphone.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func endShift() {
        guard let ended = store.endShift() else { return }
        let hours = max(0.25, Date().timeIntervalSince(ended.startedAt) / 3600)
        logDraft = WatchLogDraft(date: ended.startedAt, jobID: ended.jobID, hours: (hours * 100).rounded() / 100)
    }

    private func jobColor(_ id: UUID?) -> Color {
        store.jobs.first { $0.id == id }.map { Color(watchHex: $0.colorHex) } ?? .green
    }
}

private struct WatchHeadline: View {
    let summary: WatchEarningsSummary
    var showsDetail = true

    private var today: WatchDaySummary? {
        summary.week.first { Calendar.current.isDateInToday($0.date) }
    }

    private var detail: String {
        if let today, today.shifts > 0 {
            return today.hours > 0
                ? "\(today.hours.formatted(.number.precision(.fractionLength(0...2)))) hours today"
                : "\(today.shifts) shift\(today.shifts == 1 ? "" : "s") today"
        }
        guard let date = summary.lastShiftDate, let total = summary.lastShiftTotal else { return "No shifts logged yet" }
        return "Last \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(total.formatted(.currency(code: "USD")))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((today?.total ?? 0).formatted(.currency(code: "USD")))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("today")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if showsDetail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 2)
    }
}

// Week and month as two separate cards, so each total has room to breathe.
private struct WatchTotalsPage: View {
    let summary: WatchEarningsSummary

    var body: some View {
        VStack(spacing: 6) {
            WatchPeriodCard(title: "This Week", totals: summary.weekTotals)
            WatchPeriodCard(title: summary.month.formatted(.dateTime.month(.wide)), totals: summary.monthTotals)
        }
        .padding(.top, 2)
    }
}

private struct WatchPeriodCard: View {
    let title: String
    let totals: WatchPeriodTotals

    private var creditShare: Double {
        let positive = max(totals.credit, 0) + max(totals.netCash, 0)
        return positive > 0 ? max(totals.credit, 0) / positive : 0
    }

    private func short(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(totals.shifts) shift\(totals.shifts == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(totals.total.formatted(.currency(code: "USD")))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            GeometryReader { geometry in
                if totals.total > 0 {
                    HStack(spacing: 2) {
                        Capsule().fill(Color.blue).frame(width: max(0, geometry.size.width * creditShare - 1))
                        Capsule().fill(Color.green)
                    }
                } else {
                    Capsule().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(height: 4)
            HStack {
                Text("\(short(totals.credit)) credit")
                    .foregroundStyle(.blue)
                Spacer(minLength: 4)
                Text("\(short(totals.netCash)) cash")
                    .foregroundStyle(.green)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WatchUpcomingShifts: View {
    let shifts: [WatchUpcomingShift]
    let jobs: [WatchJob]
    var limit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text("UP NEXT")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            if shifts.isEmpty {
                Text("No shifts scheduled")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shifts.prefix(limit)) { shift in
                    HStack(spacing: 4) {
                        Text(shift.jobName)
                            .font(.footnote.bold())
                            .foregroundStyle(jobs.first { $0.id == shift.jobID }.map { Color(watchHex: $0.colorHex) } ?? .blue)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(when(shift))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func when(_ shift: WatchUpcomingShift) -> String {
        let time = shift.start.formatted(date: .omitted, time: .shortened)
        if shift.start <= Date() { return "Now" }
        if Calendar.current.isDateInToday(shift.start) { return time }
        if Calendar.current.isDateInTomorrow(shift.start) { return "Tmrw \(time)" }
        return "\(shift.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

// Every scheduled shift from now through the end of the person's week, by day.
private struct WatchWeekScheduleView: View {
    let shifts: [WatchUpcomingShift]
    let jobs: [WatchJob]

    private var days: [(day: Date, shifts: [WatchUpcomingShift])] {
        Dictionary(grouping: shifts) { Calendar.current.startOfDay(for: $0.start) }
            .map { ($0.key, $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        List {
            if shifts.isEmpty {
                Text("No more shifts this week")
                    .foregroundStyle(.secondary)
            }
            ForEach(days, id: \.day) { day in
                Section(dayName(day.day)) {
                    ForEach(day.shifts) { shift in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shift.jobName)
                                .font(.headline)
                                .foregroundStyle(jobs.first { $0.id == shift.jobID }.map { Color(watchHex: $0.colorHex) } ?? .blue)
                                .lineLimit(1)
                            Text("\(shift.start.formatted(date: .omitted, time: .shortened))–\(shift.end.formatted(date: .omitted, time: .shortened))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("This Week")
    }

    private func dayName(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// A watch-sized version of the cash that rains on iPhone when a shift is saved.
private struct WatchCashRain: View {
    let startedAt: Date

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                ZStack {
                    ForEach(0..<16) { index in
                        let delay = Double((index * 7) % 16) * 0.05
                        let duration = 1.3 + Double(index % 4) * 0.1
                        let progress = min(1, max(0, (elapsed - delay) / duration))
                        let startX = geometry.size.width * (Double((index * 5) % 16) + 0.5) / 16
                        let sway = sin(progress * .pi * 2 + Double(index)) * 10
                        Image(systemName: "banknote.fill")
                            .font(.system(size: CGFloat(14 + index % 3 * 3)))
                            .foregroundStyle(index.isMultiple(of: 2) ? Color.green : Color.mint)
                            .rotationEffect(.degrees(Double(index * 37) + progress * (index.isMultiple(of: 2) ? 100 : -100)))
                            .opacity(elapsed >= delay && progress < 1 ? min(1, progress / 0.06) * 0.9 : 0)
                            .position(x: startX + sway, y: -30 + (geometry.size.height + 60) * pow(progress, 1.25))
                    }
                }
            }
        }
    }
}

private struct WatchHiddenEarnings: View {
    var body: some View {
        Label("Earnings hidden", systemImage: "eye.slash")
            .font(.footnote.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

extension Color {
    init(watchHex hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        guard clean.count == 6 else { self = .blue; return }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

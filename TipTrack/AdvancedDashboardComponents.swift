import SwiftUI

struct DashboardGreeting: View {
    let jobs: [Job]
    let shifts: [Shift]
    let showsGreeting: Bool
    @State private var showsInsights = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let iconSize: CGFloat = 48
    @AppStorage("insightsDiscoveryCount") private var insightsDiscoveryCount = 0
    @AppStorage(FeatureKeys.alwaysShowInsightsLabel) private var alwaysShowInsightsLabel = false
    @Bindable private var schedule = ScheduleStore.shared
    @AppStorage(FeatureKeys.headlineMetric) private var storedMetric = DashboardHeadlineMetric.today.rawValue

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var tonight: ScheduledShift? {
        schedule.events.first {
            $0.end > Date() && Calendar.current.isDateInToday($0.start)
        }
    }

    private var weekInterval: DateInterval? {
        Calendar.preferredWeek.dateInterval(of: .weekOfYear, for: Date())
    }

    private var currentWeekShifts: [Shift] {
        guard let weekInterval else { return [] }
        return shifts.filter { $0.date >= weekInterval.start && $0.date < weekInterval.end }
    }

    private var previousWeekShifts: [Shift] {
        guard let weekInterval,
              let previousStart = Calendar.preferredWeek.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start),
              let previousEnd = Calendar.preferredWeek.date(byAdding: .weekOfYear, value: -1, to: weekInterval.end) else {
            return []
        }
        return shifts.filter { $0.date >= previousStart && $0.date < previousEnd }
    }

    private var weeklyEarnings: Double {
        currentWeekShifts.reduce(0) { $0 + $1.totalEarnings }
    }

    private var weeklyHours: Double {
        currentWeekShifts.reduce(0) { $0 + ($1.hoursWorked ?? 0) }
    }

    private var previousWeekEarnings: Double {
        previousWeekShifts.reduce(0) { $0 + $1.totalEarnings }
    }

    private var metric: DashboardHeadlineMetric {
        DashboardHeadlineMetric(rawValue: storedMetric) ?? .today
    }

    private var todayShifts: [Shift] {
        shifts.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayEarnings: Double {
        todayShifts.reduce(0) { $0 + $1.totalEarnings }
    }

    /// Today's hours, or the last logged shift when nothing is logged yet today.
    private var todayDetail: String {
        if !todayShifts.isEmpty {
            let hours = todayShifts.reduce(0) { $0 + ($1.hoursWorked ?? 0) }
            let count = todayShifts.count
            return hours > 0
                ? "\(hours.formatted(.number.precision(.fractionLength(0...2)))) hours today"
                : "\(count) shift\(count == 1 ? "" : "s") today"
        }
        guard let last = shifts.filter({ $0.date < Date() }).max(by: { $0.date < $1.date }) else {
            return "No shifts logged yet"
        }
        return "Last shift \(last.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(last.totalEarnings.formatted(.currency(code: "USD")))"
    }

    private var comparisonText: String {
        guard previousWeekEarnings > 0 else { return "No prior-week comparison yet" }
        let change = ((weeklyEarnings - previousWeekEarnings) / previousWeekEarnings) * 100
        return "\(abs(change).formatted(.number.precision(.fractionLength(0))))% \(change >= 0 ? "up" : "down") from last week"
    }

    var body: some View {
        HStack(alignment: .headlineCenter, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                headline
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: headlineValue))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: headlineValue)
                    .alignmentGuide(.headlineCenter) { $0[VerticalAlignment.center] }
                Text(metric == .today
                    ? todayDetail
                    : "\(weeklyHours.formatted(.number.precision(.fractionLength(0...2)))) hours · \(comparisonText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showsGreeting {
                    if let tonight {
                        let name = jobs.first(where: { $0.id == tonight.jobID })?.name ?? "your job"
                        Text("\(greeting) · \(name) at \(tonight.start.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(greeting)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                insightsDiscoveryCount = min(insightsDiscoveryCount + 1, 3)
                showsInsights = true
            } label: {
                VStack(spacing: 0) {
                    ZStack {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.green.gradient)
                            .shadow(color: .green.opacity(0.18), radius: 3, y: 2)
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.mint)
                            .offset(x: 17, y: -14)
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.8))
                            .offset(x: -18, y: 12)
                    }
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .contentShape(Rectangle())
                    // Hidden after a few visits, leaving just the cash icon.
                    if alwaysShowInsightsLabel || insightsDiscoveryCount < 3 {
                        HStack(spacing: 2) {
                            Text("Insights")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)
            // Center the icon (not icon + label) on the headline.
            .alignmentGuide(.headlineCenter) { _ in Self.iconSize / 2 }
            .accessibilityLabel("Earnings insights")
            .accessibilityHint("View your earnings trends and best shifts, jobs, and weekdays")
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showsInsights) { EarningsInsightsView() }
    }

    /// The number in the headline, so its digits can roll when it changes.
    private var headlineValue: Double {
        switch metric {
        case .today: todayEarnings
        case .earnings: weeklyEarnings
        case .hours: weeklyHours
        case .shifts: Double(currentWeekShifts.count)
        case .hourlyAverage:
            TipTrackSiriRules.hourlyAverage(
                earningsAndHours: currentWeekShifts.map { ($0.totalEarnings, $0.hoursWorked) }) ?? 0
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch metric {
        case .today:
            Text("\(todayEarnings, format: .currency(code: "USD")) earned today")
                .font(.title2.bold())
        case .earnings:
            Text("\(weeklyEarnings, format: .currency(code: "USD")) earned this week")
                .font(.title2.bold())
        case .hours:
            Text("\(weeklyHours.formatted(.number.precision(.fractionLength(0...2)))) hours this week")
                .font(.title2.bold())
        case .shifts:
            Text("\(currentWeekShifts.count) shifts this week")
                .font(.title2.bold())
        case .hourlyAverage:
            let average = TipTrackSiriRules.hourlyAverage(
                earningsAndHours: currentWeekShifts.map { ($0.totalEarnings, $0.hoursWorked) }
            ) ?? 0
            Text("\(average, format: .currency(code: "USD")) per hour")
                .font(.title2.bold())
        }
    }
}

struct SevenDayDashboardStrip: View {
    @Environment(\.tipTrackColorful) private var colorfulTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shifts: [Shift]
    let onOpenDay: (Date) -> Void
    @Bindable private var schedule = ScheduleStore.shared
    @AppStorage(FeatureKeys.weekStart) private var weekStart = 2
    @State private var weekOffset = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isPaging = false

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStart
        return calendar
    }

    private var weekStartDate: Date {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromWeekStart = (weekday - weekStart + 7) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today) ?? today
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) ?? currentWeekStart
    }

    private func days(relativeWeek: Int) -> [Date] {
        (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset + relativeWeek * 7, to: weekStartDate)
        }
    }

    var body: some View {
        weekPage(relativeWeek: 0)
            .hidden()
            .overlay {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(-1...1, id: \.self) { relativeWeek in
                            weekPage(relativeWeek: relativeWeek)
                                .frame(width: geometry.size.width)
                                .accessibilityHidden(relativeWeek != 0)
                        }
                    }
                    .offset(x: -geometry.size.width + dragOffset)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                guard !isPaging,
                                      abs(value.translation.width) > abs(value.translation.height) else { return }
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                guard !isPaging else { return }
                                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                                let shouldPage = horizontal && (abs(value.translation.width) > 50
                                    || abs(value.predictedEndTranslation.width) > geometry.size.width * 0.4)
                                guard shouldPage else {
                                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragOffset = 0 }
                                    return
                                }
                                let direction = value.translation.width < 0 ? 1 : -1
                                if reduceMotion {
                                    weekOffset += direction
                                    dragOffset = 0
                                } else {
                                    isPaging = true
                                    withAnimation(.snappy(duration: 0.28), completionCriteria: .removed) {
                                        dragOffset = -CGFloat(direction) * geometry.size.width
                                    } completion: {
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            weekOffset += direction
                                            dragOffset = 0
                                            isPaging = false
                                        }
                                    }
                                }
                            }
                    )
                    .allowsHitTesting(!isPaging)
                }
            }
            .clipped()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func weekPage(relativeWeek: Int) -> some View {
        let days = days(relativeWeek: relativeWeek)
        return HStack(spacing: 5) {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                let dayColor = TipTrackColorPalette.rainbow[index % TipTrackColorPalette.rainbow.count]
                let logged = shifts.contains { calendar.isDate($0.date, inSameDayAs: day) }
                let scheduled = schedule.events.contains { calendar.isDate($0.start, inSameDayAs: day) }

                Button {
                    guard !isPaging, dragOffset == 0 else { return }
                    onOpenDay(day)
                } label: {
                    VStack(spacing: 5) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.bold())
                            .foregroundStyle(colorfulTheme ? dayColor : Color.primary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.caption)
                        Circle()
                            .fill(colorfulTheme
                                ? dayColor
                                : (logged ? Color.green : (scheduled ? Color.blue : Color.secondary.opacity(0.2))))
                            .frame(width: 6, height: 6)
                            // Pops when a shift is logged on this day.
                            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? false : logged) { dot, scale in
                                dot.scaleEffect(scale)
                            } keyframes: { _ in
                                SpringKeyframe(2.2, duration: 0.18, spring: .snappy)
                                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(colorfulTheme
                        ? dayColor.opacity(calendar.isDateInToday(day) ? 0.2 : 0.08)
                        : (calendar.isDateInToday(day) ? Color.accentColor.opacity(0.12) : .clear),
                        in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityHint("Shows statistics for this day")
            }
        }
    }
}

private extension VerticalAlignment {
    /// Lines up the insights button with the middle of the headline text.
    enum HeadlineCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let headlineCenter = VerticalAlignment(HeadlineCenter.self)
}

import SwiftUI
import SwiftData

struct ShiftCalendarView: View {
    var onClose: (() -> Void)? = nil
    var showsDetails = true
    var onCompactHeightChange: ((CGFloat) -> Void)?
    var onShowDetails: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }, sort: \Shift.date) private var shifts: [Shift]
    @Query(sort: \Job.name) private var jobs: [Job]
    @State private var month: Date
    @State private var turn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Date
    @State private var selectedJob: UUID?
    @State private var dayPage = 0
    @State private var quickActionDay: Date?
    @State private var showsDayActions = false
    @State private var shiftToEdit: Shift?
    @ScaledMetric(relativeTo: .subheadline) private var entryCardHeight: CGFloat = 112
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(FeatureKeys.calendarEarnings) private var showEarnings = true
    @AppStorage(FeatureKeys.weekStart) private var weekStart = 2
    @Bindable private var schedule = ScheduleStore.shared

    init(initialDate: Date = Date(), onClose: (() -> Void)? = nil, showsDetails: Bool = true, onCompactHeightChange: ((CGFloat) -> Void)? = nil, onShowDetails: (() -> Void)? = nil) {
        self.onShowDetails = onShowDetails
        self.onCompactHeightChange = onCompactHeightChange
        self.showsDetails = showsDetails
        self.onClose = onClose
        let selectedDate = Calendar.current.startOfDay(for: initialDate)
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate)
        _selected = State(initialValue: selectedDate)
    }

    private var monthlyEarnings: Double {
        shifts.filter { shift in
            (selectedJob == nil || shift.job?.id == selectedJob)
                && Calendar.current.isDate(shift.date, equalTo: month, toGranularity: .month)
        }.reduce(0) { $0 + $1.totalEarnings }
    }

    private var showsReturnToToday: Bool {
        !Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
            || !Calendar.current.isDateInToday(selected)
    }

    private var weekdayColumns: [Int] {
        (0..<7).map { (weekStart - 1 + $0) % 7 }
    }

    private struct CalendarWeek: Identifiable {
        let days: [Date]

        var id: Date {
            days[0]
        }
    }

    private struct CalendarSnapshot {
        var weeks: [CalendarWeek]
        var shiftsByDay: [Date: [Shift]]
        var eventsByDay: [Date: [ScheduledShift]]
        var matched: Set<String>
    }

    private var calendarSnapshot: CalendarSnapshot {
        let cal = Calendar.preferredWeek
        let offset = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let days = (0..<((offset + count + 6) / 7 * 7)).compactMap {
            cal.date(byAdding: .day, value: $0 - offset, to: month).map(cal.startOfDay(for:))
        }
        let weeks = stride(from: 0, to: days.count, by: 7).map { startIndex in
            CalendarWeek(days: Array(days[startIndex..<min(startIndex + 7, days.count)]))
        }
        let visibleRange = (days.first ?? month)..<(cal.date(byAdding: .day, value: 1, to: days.last ?? month) ?? month)
        var shiftsByDay: [Date: [Shift]] = [:]
        for shift in shifts where (selectedJob == nil || shift.job?.id == selectedJob) && visibleRange.contains(shift.date) {
            shiftsByDay[cal.startOfDay(for: shift.date), default: []].append(shift)
        }
        var eventsByDay: [Date: [ScheduledShift]] = [:]
        for event in schedule.events where (selectedJob == nil || event.jobID == selectedJob) && visibleRange.contains(event.start) {
            eventsByDay[cal.startOfDay(for: event.start), default: []].append(event)
        }
        return CalendarSnapshot(
            weeks: weeks,
            shiftsByDay: shiftsByDay,
            eventsByDay: eventsByDay,
            matched: schedule.loggedEventIDs(shifts: shifts)
        )
    }

    var body: some View {
        let snapshot = calendarSnapshot
        let selectedKey = Calendar.preferredWeek.startOfDay(for: selected)
        let selectedShifts = shifts.filter {
            (selectedJob == nil || $0.job?.id == selectedJob)
                && Calendar.current.isDate($0.date, inSameDayAs: selectedKey)
        }
        let selectedEvents = schedule.events.filter {
            (selectedJob == nil || $0.jobID == selectedJob)
                && Calendar.current.isDate($0.start, inSameDayAs: selectedKey)
        }

        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Picker("Job", selection: $selectedJob) {
                                Text("All Jobs").tag(nil as UUID?)
                                ForEach(jobs) { Label($0.name, systemImage: $0.iconSymbolName).foregroundStyle(Color(hex: $0.colorHex)).tag(Optional($0.id)) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityLabel("Filter by job")
                            Spacer()
                            Button {
                                let today = Calendar.current.startOfDay(for: Date())
                                let todayMonth = Calendar.current.dateInterval(of: .month, for: today)?.start ?? today
                                CardTurn.perform($turn, forward: todayMonth > month, reduceMotion: reduceMotion) {
                                    month = todayMonth
                                    selected = today
                                }
                            } label: {
                                Text("Today").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.borderless)
                            .disabled(!showsReturnToToday)
                            .accessibilityLabel("Return calendar to today")
                        }
                        HStack(spacing: 10) {
                            Button { move(-1) } label: {
                                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                                    .frame(width: 34, height: 34)
                                    .background(Color.secondary.opacity(0.08), in: Circle())
                            }.accessibilityLabel("Previous month")
                            Spacer(minLength: 0)
                            VStack(spacing: 3) {
                                monthTitle
                                monthEarnings
                            }
                            .cardTurn(turn)
                            Spacer(minLength: 0)
                            Button { move(1) } label: {
                                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                                    .frame(width: 34, height: 34)
                                    .background(Color.secondary.opacity(0.08), in: Circle())
                            }.accessibilityLabel("Next month")
                        }
                        .buttonStyle(.borderless)
                    Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                        GridRow {
                            ForEach(weekdayColumns, id: \.self) { weekdayIndex in
                                Text(Calendar.current.veryShortWeekdaySymbols[weekdayIndex])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        ForEach(snapshot.weeks) { week in
                            GridRow {
                                ForEach(week.days, id: \.self) { day in
                                    dayCell(day, snapshot: snapshot)
                                }
                            }
                        }
                    }
                    .id(month)
                    .cardTurn(turn)

                        if selectedJob == nil && jobs.count > 1 {
                            jobColorLegend
                        }
                    }
                    .padding(.vertical, 2)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if !showsDetails { onCompactHeightChange?(height + 128) }
                    }
                    .listRowSeparator(.hidden)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if showsDetails {
                Section(selected.formatted(.dateTime.weekday(.wide).month().day())) {
                    Text("\(selectedShifts.count) \(selectedShifts.count == 1 ? "shift" : "shifts") · \(selectedShifts.reduce(0) { $0 + $1.totalEarnings }, format: .currency(code: "USD")) earned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    let entries = combinedEntries(shifts: selectedShifts, events: selectedEvents)
                    let pageSize = textSize >= .xxLarge ? 2 : 4
                    let range = CalendarNavigation.pageRange(itemCount: entries.count, page: dayPage, pageSize: pageSize)
                    let columns = textSize >= .xxLarge ? 1 : 2
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                        ForEach(Array(entries[range])) { entry in
                            dayEntry(entry, matched: snapshot.matched)
                        }
                    }
                    if entries.count > pageSize {
                        HStack {
                            Button { dayPage = max(0, dayPage - 1) } label: {
                                Image(systemName: "chevron.left").frame(width: 34, height: 28)
                            }
                            .disabled(range.lowerBound == 0)
                            .accessibilityLabel("Previous entries for this day")
                            Spacer()
                            Text("\(range.lowerBound + 1)–\(range.upperBound) of \(entries.count)")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            Spacer()
                            Button { dayPage += 1 } label: {
                                Image(systemName: "chevron.right").frame(width: 34, height: 28)
                            }
                            .disabled(range.upperBound == entries.count)
                            .accessibilityLabel("Next entries for this day")
                        }
                        .buttonStyle(.borderless)
                    }

                    if selectedEvents.isEmpty && selectedShifts.isEmpty {
                        Text("No shifts for this day").foregroundStyle(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                Section {
                    NavigationLink("Schedule Status") {
                        ScheduleStatusView(jobs: jobs)
                    }

                }
                }
            }
            .environment(\.defaultMinListRowHeight, 28)
            .listSectionSpacing(12)
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, 8, for: .scrollContent)
            .scrollDisabled(!showsDetails)
            .sheet(item: $shiftToEdit) { EditShiftSheet(shift: $0) }
            .onChange(of: selected) { dayPage = 0 }
            .onChange(of: selectedJob) { dayPage = 0 }
            .protectEarnings()
            .navigationTitle("Shift Calendar").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } } }
            .task { await schedule.refresh(context: context) }

        }
    }
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var monthTitle: some View {
        Text(month.formatted(.dateTime.month(.wide).year()))
            .font(.headline)
            .lineLimit(1).minimumScaleFactor(0.65)
    }

    private var monthEarnings: some View {
        Text(monthlyEarnings, format: .currency(code: "USD"))
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.65)
            .accessibilityLabel("Monthly earnings: \(monthlyEarnings.formatted(.currency(code: "USD")))")
    }

    private func move(_ amount: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: amount, to: month) else { return }
        CardTurn.perform($turn, forward: amount > 0, reduceMotion: reduceMotion) {
            month = newMonth
            selected = CalendarNavigation.selectedDay(in: newMonth, matching: selected, calendar: .current)
        }
    }
    private enum DayEntry: Identifiable {
        case shift(Shift, ScheduledShift?)
        case event(ScheduledShift)

        var id: String {
            switch self {
            case .shift(let shift, _): "shift-\(shift.id)"
            case .event(let event): "event-\(event.id)"
            }
        }
    }

    private func combinedEntries(shifts: [Shift], events: [ScheduledShift]) -> [DayEntry] {
        var used = Set(shifts.compactMap(\.scheduledEventID))
        var entries: [DayEntry] = []
        for shift in shifts {
            let event: ScheduledShift?
            if let id = shift.scheduledEventID {
                event = events.first { $0.id == id }
            } else {
                event = events.first {
                    !used.contains($0.id) && $0.jobID == shift.job?.id
                        && Calendar.current.isDate($0.start, inSameDayAs: shift.date)
                }
            }
            if let event { used.insert(event.id) }
            entries.append(.shift(shift, event))
        }
        entries += events.filter { !used.contains($0.id) }.map(DayEntry.event)
        return entries
    }

    @ViewBuilder
    private func dayEntry(_ entry: DayEntry, matched: Set<String>) -> some View {
        switch entry {
        case .shift(let shift, let event):
            Button { shiftToEdit = shift } label: {
                CalendarDayEntryCard(
                    jobName: shift.job?.name ?? "Unassigned",
                    color: shift.job.map { Color(hex: $0.colorHex) } ?? .secondary,
                    symbolName: shift.job?.iconSymbolName ?? "briefcase.fill",
                    headline: shift.totalEarnings.formatted(.currency(code: "USD")),
                    detail: event.map { eventTime($0) }
                        ?? shift.hoursWorked.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) hours worked" }
                        ?? "Logged shift",
                    actionLabel: "Edit shift", height: entryCardHeight
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this shift")
            .shiftQuickActions(shift) { shiftToEdit = shift }
        case .event(let event):
            let job = jobs.first { $0.id == event.jobID }
            let logged = matched.contains(event.id)
            Button {
                if !logged {
                    AppRoute.shared.openLog(event: event)
                    close()
                }
            } label: {
                CalendarDayEntryCard(
                    jobName: job?.name ?? "Job",
                    color: job.map { Color(hex: $0.colorHex) } ?? .secondary,
                    symbolName: job?.iconSymbolName ?? "briefcase.fill",
                    headline: eventTime(event), detail: event.title,
                    actionLabel: logged ? "Logged" : "Log shift", height: entryCardHeight
                )
            }
            .buttonStyle(.plain)
            .disabled(logged)
        }
    }

    private func eventTime(_ event: ScheduledShift) -> String {
        event.allDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }

    private struct JobFill: Identifiable {
        let id: String
        let color: Color
        var earnings: Double
        var share: Double = 0
    }

    private func jobFills(shifts: [Shift]) -> [JobFill] {
        var grouped: [String: JobFill] = [:]
        for shift in shifts {
            let key = shift.job?.id.uuidString ?? "unassigned"
            if grouped[key] == nil {
                grouped[key] = JobFill(id: key,
                    color: shift.job.map { Color(hex: $0.colorHex) } ?? .secondary,
                    earnings: 0)
            }
            grouped[key]?.earnings += shift.totalEarnings
        }
        let total = grouped.values.reduce(0) { $0 + max(0, $1.earnings) }
        return grouped.values.sorted { $0.id < $1.id }.map { fill in
            var fill = fill
            fill.share = total > 0 ? max(0, fill.earnings) / total : 1 / Double(grouped.count)
            return fill
        }
    }

    // Names each job's color, since days are shaded by each job's share of earnings.
    private var jobColorLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(jobs) { job in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: job.colorHex).opacity(0.35))
                            .frame(width: 12, height: 12)
                        Text(job.name)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day colors: " + jobs.map(\.name).joined(separator: ", "))
    }

    private func dayCell(_ day: Date, snapshot: CalendarSnapshot) -> some View {
        let dayShifts = snapshot.shiftsByDay[day] ?? []
        let amount = dayShifts.reduce(0) { $0 + $1.totalEarnings }
        let scheduled = snapshot.eventsByDay[day] ?? []
        let missing = scheduled.contains { !$0.allDay && $0.end < Date() && !snapshot.matched.contains($0.id) }
        let upcoming = scheduled.contains { $0.end >= Date() && !snapshot.matched.contains($0.id) }
        let loggedJobIDs = (snapshot.shiftsByDay[day] ?? []).compactMap { $0.job?.id }
        let scheduledJobIDs = scheduled.map(\.jobID)
        let jobIDs = Array(Set(loggedJobIDs + scheduledJobIDs)).sorted { $0.uuidString < $1.uuidString }
        let fills = jobFills(shifts: dayShifts)
        return Button { selected = day } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day())).font(.subheadline)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if showEarnings && amount > 0 {
                    Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.system(size: 7, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    HStack(spacing: 2) {
                        ForEach(jobIDs.prefix(4), id: \.self) { jobID in
                            Circle()
                                .fill(jobs.first(where: { $0.id == jobID }).map { Color(hex: $0.colorHex) } ?? .secondary)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
            }.frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
                .background {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(fills) { fill in
                                fill.color.opacity(0.35)
                                    .frame(width: geometry.size.width * fill.share)
                            }
                        }
                    }
                    .background(dayShifts.isEmpty ? Color.clear : Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(
                    Calendar.current.isDate(day, inSameDayAs: selected) ? Color.accentColor : Color.secondary.opacity(0.18),
                    lineWidth: Calendar.current.isDate(day, inSameDayAs: selected) ? 2 : 0.5))
                .opacity(Calendar.current.isDate(day, equalTo: month, toGranularity: .month) ? 1 : 0.3)
        }.buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { showsDayActions && quickActionDay == day },
            set: { if !$0 && quickActionDay == day { showsDayActions = false } }
        ), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(day.formatted(date: .complete, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                Button("Log a shift") {
                    showsDayActions = false
                    AppRoute.shared.openLog(date: day, jobID: selectedJob)
                    close()
                }
                Button("View day breakdown") {
                    showsDayActions = false
                    selected = day
                    dayPage = 0
                    onShowDetails?()
                }
            }
            .buttonStyle(.bordered)
            .padding(16)
            .frame(maxWidth: 260)
            .presentationCompactAdaptation(.popover)
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            quickActionDay = day
            showsDayActions = true
        })
        .accessibilityAction(named: "Day actions") {
            quickActionDay = day
            showsDayActions = true
        }
        .accessibilityHint("Touch and hold for shift and day actions")
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(amount.formatted(.currency(code: "USD"))), \(scheduled.count) scheduled, \(jobIDs.count) jobs, \(missing ? "not logged" : (upcoming ? "upcoming" : ""))")
    }
}

private struct ScheduleStatusView: View {
    let jobs: [Job]
    @Environment(\.modelContext) private var context
    @Bindable private var schedule = ScheduleStore.shared

    var body: some View {
        List {
            if jobs.allSatisfy({ $0.calendarFeeds.isEmpty }) {
                Text("Add a schedule calendar to a job in Settings → Jobs.")
            }
            ForEach(jobs.filter { !$0.calendarFeeds.isEmpty }) { job in
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.name).font(.headline)
                    Text(schedule.status[job.id] ?? "Not refreshed yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let date = schedule.refreshedAt(job) {
                        Text("Updated \(date.formatted())").font(.caption)
                    }
                }
            }
            if let message = schedule.notificationMessage { Text(message).font(.caption) }
        }
        .scrollDisabled(false)
        .navigationTitle("Schedule Status")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await schedule.refresh(context: context) }
    }
}

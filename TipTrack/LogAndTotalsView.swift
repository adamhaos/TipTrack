import SwiftData
import SwiftUI
import UIKit

// MARK: - Log and Totals
struct LogAndTotalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tipTrackColorful) private var colorfulTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(FeatureKeys.appLock) private var appLock = false
    @AppStorage(FeatureKeys.weekStart) private var weekStart = 2
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }, sort: \Shift.date, order: .forward) private var shifts: [Shift]
    @Query(sort: \Job.name) private var jobs: [Job]

    @State private var selectedDate = Date()
    @AppStorage("automaticJobSelection") private var automaticJobSelection = false
    @AppStorage(FeatureKeys.greeting) private var showGreeting = false
    @AppStorage(FeatureKeys.showMonthly) private var showMonthly = true
    @AppStorage(FeatureKeys.showWeekly) private var showWeekly = true
    @AppStorage(FeatureKeys.showCalendarStrip) private var showCalendarStrip = true
    @AppStorage(FeatureKeys.showLiveActivity) private var showLiveActivity = false
    @AppStorage(FeatureKeys.showLogShift) private var showLogShift = true
    @AppStorage(FeatureKeys.showSpacer1) private var showSpacer1 = true
    @AppStorage(FeatureKeys.showSpacer2) private var showSpacer2 = false
    @AppStorage(FeatureKeys.showSpacer3) private var showSpacer3 = true
    @AppStorage(FeatureKeys.showSpacer4) private var showSpacer4 = false
    @AppStorage(FeatureKeys.cardOrder) private var storedCardOrder = ""
    @AppStorage(FeatureKeys.validation) private var entryValidation = true
    @AppStorage(FeatureKeys.receipts) private var receiptFeatures = false
    @AppStorage(FeatureKeys.liveTimer) private var liveTimerEnabled = false
    @AppStorage(FeatureKeys.hourlyPayEnabled) private var hourlyPayEnabled = true
    @Bindable private var liveShift = LiveShiftManager.shared
    @State private var manuallySelectedJob = false
    @State private var scheduledEventID: String?
    @State private var scheduledEventDate: Date?
    @State private var isShowingCalendar = false
    @State private var calendarInitialDate = Date()
    @State private var topPanelDragOffset: CGFloat = 0
    @State private var topPanelDismissOffset: CGFloat = 0
    @State private var isClosingTopPanel = false
    /// A panel requested while another is still sliding away; opened once it's gone.
    @State private var pendingTopPanelOpen: (() -> Void)?
    @State private var isTopPanelExpanded = false
    @State private var compactCalendarHeight: CGFloat = 450
    @State private var compactHistoryHeight: CGFloat = 340
    @State private var selectedJob: Job? = nil
    @State private var creditInput: String = ""
    @State private var cashInput: String = ""
    @State private var barTipOutInput: String = ""
    @State private var hoursWorkedInput: String = ""
    @State private var hourlyRateInput: String = ""
    @State private var notesInput: String = ""
    @AppStorage(FeatureKeys.shiftNotes) private var shiftNotesEnabled = false
    /// Hours copied from the schedule; cleared once the person edits them.
    @State private var prefilledHours: String?
    @FocusState private var isEditingNotes: Bool

    @State private var activeField: Field = .credit
    @State private var isFormExpanded: Bool = false
    @State private var formSheetContentHeight: CGFloat = 0
    @State private var formSheetDragOffset: CGFloat = 0
    @State private var cashRain: ShiftCashRain?
    @State private var saveError: String?
    @State private var isAddingFirstJob = false
    @State private var isShowingSettings = false
    @State private var isShowingHistory = false
    @State private var isShowingCurrentWeek = false
    @State private var isShowingSelectedMonth = false
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedWeekStart = Calendar.preferredWeek.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

    @State private var lastSavedShift: Shift? = nil
    @State private var showUndoToast: Bool = false
    @State private var undoTask: Task<Void, Never>? = nil
    @State private var validationMessage: String?
    @State private var pendingReceiptImage: UIImage?
    @State private var isShowingReceiptScanner = false
    @State private var isShowingLiveJobPicker = false

    enum Field: Hashable {
        case credit, cash, barTipOut, hoursWorked, hourlyRate
    }

    private var weekDays: [Date] {
        (0...6).compactMap { dayOffset in
            Calendar.preferredWeek.date(byAdding: .day, value: dayOffset, to: selectedWeekStart)
        }
    }

    private var dashboardCards: [DashboardCardID] {
        DashboardCardID.ordered(from: storedCardOrder)
    }

    private var currentWeekShifts: [Shift] {
        shifts.filter { shift in
            weekDays.contains { Calendar.preferredWeek.isDate(shift.date, inSameDayAs: $0) }
        }
    }

    private var weeklyCreditTotal: Double {
        currentWeekShifts.reduce(0) { $0 + $1.creditEarnings }
    }

    private var weeklyNetCashTotal: Double {
        currentWeekShifts.reduce(0) { $0 + $1.netCash }
    }

    private var weeklyAverageHourly: Double? {
        let timedShifts = currentWeekShifts.filter { ($0.hoursWorked ?? 0) > 0 }
        let hours = timedShifts.reduce(0) { $0 + ($1.hoursWorked ?? 0) }
        let earnings = timedShifts.reduce(0) { $0 + $1.totalEarnings }
        return hours > 0 ? earnings / hours : nil
    }

    private var currentMonthStart: Date {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    private var currentWeekStart: Date {
        Calendar.preferredWeek.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    private var canMoveToNextMonth: Bool {
        selectedMonth < currentMonthStart
    }

    private var canMoveToNextWeek: Bool {
        selectedWeekStart < currentWeekStart
    }

    private var currentWeekDateRange: String {
        guard let firstDay = weekDays.first, let lastDay = weekDays.last else {
            return "Current week"
        }

        let start = firstDay.formatted(.dateTime.month(.abbreviated).day())
        let end = lastDay.formatted(.dateTime.month(.abbreviated).day())
        return "\(start)–\(end)"
    }

    private var currentWeekForBreakdown: (key: String, date: Date, shifts: [Shift]) {
        (
            key: String(selectedWeekStart.timeIntervalSinceReferenceDate),
            date: selectedWeekStart,
            shifts: currentWeekShifts
        )
    }

    private var selectedMonthForBreakdown: (key: String, date: Date, shifts: [Shift]) {
        let monthShifts = shifts.filter {
            Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
        return (
            key: selectedMonth.formatted(.iso8601.year().month()),
            date: selectedMonth,
            shifts: monthShifts
        )
    }

    private var isFormHasData: Bool {
        (Double(creditInput) ?? 0.0 > 0) ||
        (Double(cashInput) ?? 0.0 > 0) ||
        (Double(barTipOutInput) ?? 0.0 > 0) ||
        (Double(hoursWorkedInput) ?? 0.0 > 0)
    }

    /// What the shift in the form would add to your earnings.
    private var draftTotal: Double {
        let credit = Double(creditInput) ?? 0
        let cash = Double(cashInput) ?? 0
        let tipOut = Double(barTipOutInput) ?? 0
        let hours = Double(hoursWorkedInput) ?? 0
        let rate = hourlyPayEnabled ? (Double(hourlyRateInput) ?? 0) : 0
        let total = credit + cash - tipOut + hours * rate
        return total.isFinite ? total : 0
    }

    private var sheetAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.4)
    }

    private var isShowingTopPanel: Bool {
        isShowingSettings || isShowingHistory || isShowingCalendar
    }

    private func closeTopPanel() {
        guard isShowingTopPanel, !isClosingTopPanel else { return }
        // Preserve the content and its size until the panel is offscreen.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            isClosingTopPanel = true
        } completion: {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isShowingSettings = false
                isShowingHistory = false
                isShowingCalendar = false
                topPanelDragOffset = 0
                topPanelDismissOffset = 0
                isTopPanelExpanded = false
                isClosingTopPanel = false
            }
            if let open = pendingTopPanelOpen {
                pendingTopPanelOpen = nil
                open()
            }
        }
    }

    private func openTopPanel(_ open: @escaping () -> Void) {
        if isClosingTopPanel {
            pendingTopPanelOpen = open
        } else {
            open()
        }
    }

    private func isUpwardPanelSwipe(_ value: DragGesture.Value) -> Bool {
        let translation = value.translation
        guard translation.height < -20,
              abs(translation.height) > abs(translation.width) * 1.2 else { return false }
        return translation.height < -55 || value.predictedEndTranslation.height < -100
    }

    @ViewBuilder
    private var topPanelContent: some View {
        if isShowingSettings {
            SettingsView(onClose: closeTopPanel)
        } else if isShowingHistory {
            WeeklyHistoryView(onClose: closeTopPanel, isExpanded: isTopPanelExpanded,
                onCompactHeightChange: { compactHistoryHeight = $0 },
                onRequestExpand: { withAnimation(sheetAnimation) { isTopPanelExpanded = true } })
        } else if isShowingCalendar {
            ShiftCalendarView(initialDate: calendarInitialDate, onClose: closeTopPanel, showsDetails: isTopPanelExpanded, onCompactHeightChange: { compactCalendarHeight = $0 }, onShowDetails: {
                withAnimation(sheetAnimation) { isTopPanelExpanded = true }
            })
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                NavigationStack {
                    dashboardLifecycle
                }
                .allowsHitTesting(!isFormExpanded && (!isShowingTopPanel || isClosingTopPanel))
                .accessibilityHidden(isFormExpanded || isShowingTopPanel)

                Color.black.opacity(isFormExpanded || (isShowingTopPanel && !isClosingTopPanel) ? 0.32 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isShowingTopPanel { closeTopPanel() }
                        else { dismissLogForm() }
                    }
                    .allowsHitTesting(isFormExpanded || (isShowingTopPanel && !isClosingTopPanel))
                    .accessibilityHidden(!isFormExpanded && !isShowingTopPanel)
                    .accessibilityLabel("Dismiss panel")
                    .accessibilityAddTraits(.isButton)
                    .zIndex(0.5)

                // Keep the form mounted so its height is measured before it slides in.
                logEntrySheet(
                    maxHeight: geometry.size.height * 0.94,
                    bottomInset: geometry.safeAreaInsets.bottom
                )
                .offset(y: isFormExpanded ? max(0, formSheetDragOffset) : geometry.size.height + 100)
                .allowsHitTesting(isFormExpanded)
                .accessibilityHidden(!isFormExpanded)
                .zIndex(1)

                if let cashRain {
                    ShiftCashRainView(burst: cashRain)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(2)
                }
            }
            .overlay(alignment: .top) {
                if isShowingTopPanel {
                    let compactHeight = min(isShowingCalendar ? compactCalendarHeight : compactHistoryHeight, geometry.size.height)
                    let expanded = isShowingSettings || isTopPanelExpanded
                    let panelHeight = expanded ? geometry.size.height : compactHeight
                    VStack(spacing: 0) {
                        topPanelContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 20, coordinateSpace: .named("topPanelDragSpace"))
                                    .onChanged { value in
                                        // Keep scrolling available in Settings and expanded history/calendar panels.
                                        guard !expanded || value.startLocation.y < 60,
                                              value.translation.height < 0,
                                              abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return }
                                        var transaction = Transaction(animation: nil)
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            topPanelDismissOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        if (!expanded || value.startLocation.y < 60),
                                           isUpwardPanelSwipe(value) {
                                            closeTopPanel()
                                        } else {
                                            withAnimation(sheetAnimation) { topPanelDismissOffset = 0 }
                                        }
                                    },
                                // Off in full-height panels: watching the whole panel swallowed
                                // taps on switches. Those panels close with Done or the handle.
                                including: expanded ? .subviews : .all
                            )
                        if !isShowingSettings {
                            VStack(spacing: 5) {
                                Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 40, height: 4)
                                Text(expanded ? "Swipe up to close" : (isShowingHistory
                                    ? "Pull down to see your full shift history.\nSwipe up to close."
                                    : "Pull to expand · Swipe up to close"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                                .frame(maxWidth: .infinity)
                                .frame(height: isShowingHistory && !expanded ? 48 : 40)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 5, coordinateSpace: .named("topPanelDragSpace"))
                                        .onChanged { value in
                                            let maximum = expanded ? 0 : geometry.size.height - compactHeight
                                            var transaction = Transaction(animation: nil)
                                            transaction.disablesAnimations = true
                                            withTransaction(transaction) {
                                                topPanelDismissOffset = min(0, value.translation.height)
                                                topPanelDragOffset = min(maximum, max(0, value.translation.height))
                                            }
                                        }
                                        .onEnded { value in
                                            withAnimation(sheetAnimation) {
                                                if isUpwardPanelSwipe(value) {
                                                    closeTopPanel()
                                                } else if value.translation.height > 35 || value.predictedEndTranslation.height > 80 {
                                                    isTopPanelExpanded = true
                                                }
                                                topPanelDragOffset = 0
                                                if !isClosingTopPanel { topPanelDismissOffset = 0 }
                                            }
                                        }
                                )
                                .accessibilityLabel(expanded ? "Close panel" : (isShowingHistory ? "Show full shift history" : "Expand panel"))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction {
                                    withAnimation(sheetAnimation) {
                                        if expanded { closeTopPanel() }
                                        else { isTopPanelExpanded = true }
                                    }
                                }
                                .accessibilityAction(named: "Close panel") {
                                    withAnimation(sheetAnimation) { closeTopPanel() }
                                }
                        }
                    }
                    .frame(height: panelHeight + topPanelDragOffset)
                    .frame(maxWidth: .infinity)
                    .background {
                        UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 0 : 28,
                                               bottomTrailingRadius: expanded ? 0 : 28)
                            .fill(Color(uiColor: .systemGroupedBackground))
                            .ignoresSafeArea(edges: expanded ? .all : .top)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top))
                    .offset(y: isClosingTopPanel ? -(geometry.size.height + geometry.safeAreaInsets.top + 100) : topPanelDismissOffset)
                    .allowsHitTesting(!isClosingTopPanel)
                    .accessibilityAddTraits(.isModal)
                }
            }
            // Measure against the stationary dashboard, not the panel moving under the finger.
            .coordinateSpace(name: "topPanelDragSpace")
            .animation(sheetAnimation, value: isFormExpanded)
            .animation(sheetAnimation, value: isShowingTopPanel)
            .animation(sheetAnimation, value: isTopPanelExpanded)
            .animation(sheetAnimation, value: compactCalendarHeight)
            .animation(sheetAnimation, value: compactHistoryHeight)
        }
    }

    private static let appStoreURL = URL(string: "https://apps.apple.com/app/id6809030435")!

    // Tapping the name offers to share the app.
    private var appTitleMenu: some View {
        Menu {
            ShareLink(item: Self.appStoreURL,
                message: Text("I track my tips with TipTrack3r. Check it out:")) {
                Label("Share This App", systemImage: "square.and.arrow.up")
            }
        } label: {
            Text("TipTrack3r")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .fixedSize()
        }
        .tint(.primary)
        .accessibilityHint("Share TipTrack3r")
    }

    private var dashboardPresentation: some View {
            dashboardLayout
            .appTitleToolbar(appTitleMenu)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        openTopPanel { isShowingSettings = true }
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                            .foregroundStyle(isFormExpanded ? Color.gray : (colorfulTheme ? Color.pink : Color.accentColor))
                    }
                    .disabled(isFormExpanded)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { openTopPanel { isShowingHistory = true } } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(isFormExpanded ? Color.gray : (colorfulTheme ? Color.orange : Color.accentColor))
                    }
                        .disabled(isFormExpanded)
                        .accessibilityLabel("Shift History")
                    Button {
                        openTopPanel {
                            calendarInitialDate = Date()
                            isShowingCalendar = true
                        }
                    } label: {
                        Image(systemName: "calendar")
                            .foregroundStyle(isFormExpanded ? Color.gray : (colorfulTheme ? Color.cyan : Color.accentColor))
                    }
                        .disabled(isFormExpanded)
                        .accessibilityLabel("Shift Calendar")
                }
            }
            .sheet(isPresented: $isAddingFirstJob) {
                EditJobView(job: Job(name: "", isDefault: true))
            }
            // Solid backgrounds: the default glass sheet showed the dashboard
            // blurred through the list at the half-height position.
            .sheet(isPresented: $isShowingCurrentWeek) {
                WeekBreakdownView(week: currentWeekForBreakdown)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color(uiColor: .systemGroupedBackground))
            }
            .sheet(isPresented: $isShowingSelectedMonth) {
                MonthBreakdownView(month: selectedMonthForBreakdown)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color(uiColor: .systemGroupedBackground))
            }
            .alert("Check This Entry", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("Save Anyway") { saveShift(skipValidation: true) }
                Button("Review", role: .cancel) { validationMessage = nil }
            } message: { Text(validationMessage ?? "") }
            .alert("Couldn't Save Shift", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
    }

    private var dashboardLifecycle: some View {
        dashboardLifecycleBase
            .onChange(of: weekStart) { alignSelectedWeek() }
            .onChange(of: jobs.map { $0.id }) { updateSelectedJob() }
            .onChange(of: scenePhase) { closeLockedPresentation() }
    }

    private func alignSelectedWeek() {
        selectedWeekStart = Calendar.preferredWeek.dateInterval(of: .weekOfYear, for: selectedWeekStart)?.start ?? currentWeekStart
    }

    private func updateSelectedJob() {
        let selectedID = selectedJob?.id
        if selectedID == nil || !jobs.contains(where: { $0.id == selectedID }) {
            selectedJob = jobs.first(where: { $0.isDefault }) ?? jobs.first
            scheduledEventID = nil
            scheduledEventDate = nil
        }
    }

    private func closeLockedPresentation() {
        guard scenePhase == .background && appLock else { return }
        isShowingSettings = false
        isShowingCalendar = false
        isShowingHistory = false
        isShowingCurrentWeek = false
        isShowingSelectedMonth = false
        isShowingLiveJobPicker = false
        isTopPanelExpanded = false
        topPanelDragOffset = 0
        dismissLogForm()
    }

    private var dashboardLifecycleBase: some View {
            dashboardPresentation
            .task(id: cashRain?.id) {
                guard let id = cashRain?.id else { return }
                try? await Task.sleep(for: .milliseconds(2900))
                guard !Task.isCancelled, cashRain?.id == id else { return }
                cashRain = nil
            }
            .onAppear {
                if selectedJob == nil {
                    selectedJob = jobs.first(where: { $0.isDefault }) ?? jobs.first
                }
                if AppRoute.shared.logRequest != nil { handleLogRoute() }
                if AppRoute.shared.historyRequest != nil { handleHistoryRoute() }
                if AppRoute.shared.calendarRequest != nil { handleCalendarRoute() }
                if AppRoute.shared.timerStartRequest != nil { handleTimerStartRoute() }
                if AppRoute.shared.timerStopRequest != nil { handleTimerStopRoute() }
            }
            .onChange(of: AppRoute.shared.logRequest) { _, _ in handleLogRoute() }
            .onChange(of: AppRoute.shared.historyRequest) { _, _ in handleHistoryRoute() }
            .onChange(of: AppRoute.shared.calendarRequest) { _, _ in handleCalendarRoute() }
            .onChange(of: AppRoute.shared.timerStartRequest) { _, _ in handleTimerStartRoute() }
            .onChange(of: AppRoute.shared.timerStopRequest) { _, _ in handleTimerStopRoute() }
            .onChange(of: isFormExpanded) { _, expanded in
                if expanded && automaticJobSelection && scheduledEventID == nil && !manuallySelectedJob {
                    manuallySelectedJob = false
                    chooseAutomaticJob()
                    if jobs.contains(where: { $0.latitude != nil }) { JobLocationManager.shared.request() }
                }
                if expanded { prefillScheduledHours() }
            }
            .onChange(of: selectedDate) { _, _ in
                if selectedDate != scheduledEventDate {
                    scheduledEventID = nil
                    scheduledEventDate = nil
                }
                if automaticJobSelection && !manuallySelectedJob { chooseAutomaticJob() }
                prefillScheduledHours()
            }
            .onChange(of: selectedJob?.id) { _, _ in prefillScheduledHours() }
            .onChange(of: JobLocationManager.shared.location) { _, _ in
                if automaticJobSelection && !manuallySelectedJob && scheduledEventID == nil { chooseAutomaticJob() }
            }
            .onChange(of: ScheduleStore.shared.events) { _, _ in
                if isFormExpanded && automaticJobSelection && !manuallySelectedJob && scheduledEventID == nil { chooseAutomaticJob() }
                prefillScheduledHours()
            }
    }

    /// Nothing set up yet: guide toward a first job instead of showing empty totals.
    private var isFirstRun: Bool { jobs.isEmpty && shifts.isEmpty }

    private var dashboardLayout: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                if isFirstRun {
                    FirstJobCard { isAddingFirstJob = true }
                        .padding(.vertical, 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                ForEach(dashboardCards.filter { !isFirstRun || ![.greeting, .monthly, .weekly].contains($0) }) { card in
                    dashboardCard(card)
                        .tint(colorfulTheme ? card.colorfulColor : Color.accentColor)
                }
            }
            .animation(sheetAnimation, value: isFirstRun)
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: liveShift.current?.id)
            .allowsHitTesting(!isFormExpanded)
            .accessibilityHidden(isFormExpanded)
            .overlay(alignment: .bottom) {
                if showUndoToast && !isFormExpanded {
                    undoToastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardCard(_ card: DashboardCardID) -> some View {
        switch card {
        case .greeting:
            DashboardGreeting(jobs: jobs, shifts: shifts, showsGreeting: showGreeting)
                .protectEarnings()
                .padding(.vertical, 2)
        case .calendar:
            if showCalendarStrip {
                SevenDayDashboardStrip(shifts: shifts) { day in
                    openTopPanel {
                        calendarInitialDate = day
                        isShowingCalendar = true
                    }
                }
            }
        case .monthly:
            if showMonthly { monthlySummaryView }
        case .weekly:
            if showWeekly { totalsSummaryView }
        case .liveActivity:
            // A running shift always shows so it can be ended, even one started from the watch.
            if (showLiveActivity && liveTimerEnabled) || liveShift.current != nil {
                liveTimerCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .logShift:
            if showLogShift {
                expandFormButton
                    .padding(.vertical, 6)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
            }
        case .spacer1:
            if showSpacer1 { Color.clear.frame(height: 10) }
        case .spacer2:
            if showSpacer2 { Color.clear.frame(height: 10) }
        case .spacer3:
            if showSpacer3 { Color.clear.frame(height: 5) }
        case .spacer4:
            if showSpacer4 { Color.clear.frame(height: 10) }
        }
    }

    private var monthlySummaryView: some View {
        MonthlyStatsCard(
            shifts: shifts,
            month: selectedMonth,
            canGoForward: canMoveToNextMonth,
            onPreviousMonth: { moveSelectedMonth(by: -1) },
            onNextMonth: { moveSelectedMonth(by: 1) },
            onOpenHistory: { isShowingSelectedMonth = true },
            onReturnToToday: { selectedMonth = currentMonthStart }
        )
        .protectEarnings()
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var liveTimerCard: some View {
        HStack(spacing: 8) {
            Image(systemName: liveShift.current == nil ? "timer" : "timer.circle.fill")
                .font(.subheadline)
                .foregroundStyle(liveShift.current == nil ? Color.blue : Color.green)
            
            if let active = liveShift.current {
                HStack(spacing: 6) {
                    Text(active.jobName)
                        .font(.caption.bold())
                    Text(timerInterval: active.startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Live Timer")
                    .font(.caption.bold())
            }
            
            Button(liveShift.current == nil ? "Start" : "End") {
                if liveShift.current == nil {
                    startLiveShift()
                } else {
                    Task { await finishLiveShift() }
                }
            }
            .font(.caption2.bold())
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .tint(liveShift.current == nil ? .blue : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .opacity(liveShift.current == nil ? 0.7 : 1)
        .confirmationDialog("Choose a Job", isPresented: $isShowingLiveJobPicker, titleVisibility: .visible) {
            ForEach(jobs) { job in
                Button(job.name) {
                    Task { await liveShift.start(job: job) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func startLiveShift() {
        if jobs.count > 1 {
            isShowingLiveJobPicker = true
        } else {
            Task { await liveShift.start(job: jobs.first) }
        }
    }
    
    private var totalsSummaryView: some View {
        CurrentWeekSummaryCard(
            dateRange: currentWeekDateRange,
            credit: weeklyCreditTotal,
            netCash: weeklyNetCashTotal,
            shiftCount: currentWeekShifts.count,
            averageHourly: weeklyAverageHourly,
            canGoForward: canMoveToNextWeek,
            onPreviousWeek: { moveSelectedWeek(by: -1) },
            onNextWeek: { moveSelectedWeek(by: 1) },
            onOpenWeek: { isShowingCurrentWeek = true },
            onReturnToToday: { selectedWeekStart = currentWeekStart }
        )
        .protectEarnings()
    }

    private var expandFormButton: some View {
        let jobColor = selectedJob.map { Color(hex: $0.colorHex) }
            ?? (colorfulTheme ? DashboardCardID.logShift.colorfulColor : Color.accentColor)
        return Button {
            withAnimation(sheetAnimation) {
                isFormExpanded = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Log Shift")
                    .font(.title3)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(jobColor)
            .foregroundColor(.white)
            .cornerRadius(18)
            .shadow(color: jobColor.opacity(0.22), radius: 7, x: 0, y: 3)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
            .overlay {
                AnimatedLogButtonBorder(color: jobColor, cornerRadius: 18)
            }
        }
    }

    private func logEntrySheet(maxHeight: CGFloat, bottomInset: CGFloat) -> some View {
        let measuredHeight = formSheetContentHeight > 0 ? formSheetContentHeight + 24 : maxHeight
        let sheetHeight = min(max(measuredHeight, 280), maxHeight)
        let sheetShape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 28, topTrailing: 28),
            style: .continuous
        )

        return VStack(spacing: 0) {
            ZStack {
                Color.clear
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 42, height: 5)
            }
            .frame(width: 120, height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        formSheetDragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let shouldDismiss = value.translation.height > 110
                            || value.predictedEndTranslation.height > 180
                        if shouldDismiss {
                            dismissLogForm()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                formSheetDragOffset = 0
                            }
                        }
                    }
            )

            ScrollViewReader { reader in
                ScrollView {
                    expandedFormView
                        .protectEarnings()
                        .background {
                            GeometryReader { contentGeometry in
                                Color.clear.preference(
                                    key: LogEntrySheetHeightKey.self,
                                    value: contentGeometry.size.height
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, max(14, bottomInset))
                }
                .scrollBounceBehavior(.basedOnSize)
                .task(id: formSheetContentHeight) {
                    guard isShowingReceiptScanner else { return }
                    // Wait one layout pass so the newly inserted scanner has a scroll target.
                    do { try await Task.sleep(for: .milliseconds(50)) }
                    catch { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        reader.scrollTo("checkoutSlipEditor", anchor: .bottom)
                    }
                }
                .onChange(of: isShowingReceiptScanner) { _, isShowing in
                    guard !isShowing else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        reader.scrollTo("shiftEntryTop", anchor: .top)
                    }
                }
            }
        }
        .frame(height: sheetHeight + bottomInset)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground), in: sheetShape)
        .overlay {
            sheetShape
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.2), radius: 22, y: -4)
        .padding(.bottom, -bottomInset)
        .onPreferenceChange(LogEntrySheetHeightKey.self) { height in
            guard abs(formSheetContentHeight - height) > 0.5 else { return }
            formSheetContentHeight = height
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: sheetHeight)
    }

    private func dismissLogForm() {
        isEditingNotes = false
        withAnimation(sheetAnimation) {
            formSheetDragOffset = 0
            isFormExpanded = false
            isShowingReceiptScanner = false
        }
    }

    private func closeReceiptScanner() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            isShowingReceiptScanner = false
        }
    }

    private var receiptScannerContent: some View {
        ReceiptScannerView(embedded: true, onCancel: closeReceiptScanner,
            preferredReportType: ShiftReportType(rawValue: selectedJob?.receiptPOS ?? "") ?? .automatic) { result in
            pendingReceiptImage = result.image
            if let credit = result.credit { creditInput = moneyString(credit) }
            if let cash = result.cash { cashInput = moneyString(cash) }
            if let tipOut = result.tipOut { barTipOutInput = moneyString(tipOut) }
            if let hours = result.hours { hoursWorkedInput = moneyString(hours) }
            closeReceiptScanner()
        }
    }

    private var expandedFormView: some View {
        let jobColor = selectedJob.map { Color(hex: $0.colorHex) }
            ?? (colorfulTheme ? DashboardCardID.logShift.colorfulColor : Color.accentColor)
        return VStack(spacing: 12) {
            HStack {
                Text("Log Shift Income")
                    .font(.headline)
                    .bold()
                Spacer()
                Button {
                    dismissLogForm()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }

            .id("shiftEntryTop")

            if !jobs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(jobs) { job in
                            let isSelected = selectedJob?.id == job.id
                            Button {
                                selectedJob = job
                                manuallySelectedJob = true
                                scheduledEventID = nil
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: job.iconSymbolName)
                                        .foregroundStyle(Color(hex: job.colorHex))
                                        .font(.caption)
                                    Text(job.name)
                                        .font(.caption)
                                        .bold()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: job.colorHex).opacity(isSelected ? 0.18 : 0.06))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: job.colorHex).opacity(isSelected ? 0.55 : 0.2), lineWidth: 1))
                                .foregroundColor(isSelected ? Color(hex: job.colorHex) : .primary)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Button {
                    adjustDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                Spacer()

                DatePicker("Shift Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()

                Spacer()

                Button {
                    adjustDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            VStack(spacing: 6) {
                inputDisplayRow(title: "Credit Tips", value: creditInput, field: .credit)
                inputDisplayRow(title: "Cash Tips", value: cashInput, field: .cash)
                inputDisplayRow(title: "Tip Out", value: barTipOutInput, field: .barTipOut)
                hoursDisplayRow
                if hourlyPayEnabled {
                    inputDisplayRow(title: "Hourly Rate (Optional)", value: hourlyRateInput, field: .hourlyRate)
                }
                if shiftNotesEnabled {
                    TextField("Add a note (optional)", text: $notesInput, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isEditingNotes)
                        .submitLabel(.done)
                        .onChange(of: notesInput) { _, text in
                            // Return ends the note, since the number pad takes over below.
                            if text.contains("\n") {
                                notesInput = text.replacingOccurrences(of: "\n", with: "")
                                isEditingNotes = false
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if receiptFeatures {
                Button {
                    withAnimation(sheetAnimation) {
                        isShowingReceiptScanner = true
                    }
                } label: {
                    Label(pendingReceiptImage == nil ? "Scan or Attach Checkout Slip" : "Receipt Attached · Scan Again",
                        systemImage: pendingReceiptImage == nil ? "doc.viewfinder" : "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .id("receiptScannerTrigger")
            }

            if isShowingReceiptScanner {
                receiptScannerContent
                    .id("checkoutSlipEditor")
                    .transition(.opacity)
            }

            CustomNumpadView { key in
                handleNumpadInput(key)
            }
            .padding(.top, 2)

            Button { saveShift() } label: {
                HStack(spacing: 8) {
                    Spacer()
                    ZStack {
                        Image(systemName: "circle.dashed")
                            .opacity(isFormHasData ? 0 : 1)
                        Image(systemName: "checkmark.circle.fill")
                            .opacity(isFormHasData ? 1 : 0)
                    }
                    ZStack {
                        Text("Enter Shift Information")
                            .opacity(isFormHasData ? 0 : 1)
                        HStack(spacing: 4) {
                            Text("Save")
                            RollingCurrencyText(amount: draftTotal)
                                .monospacedDigit()
                            Text("· \(selectedDate.formatted(.dateTime.month().day()))")
                        }
                        .opacity(isFormHasData ? 1 : 0)
                    }
                        .font(.headline)
                        .bold()
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    isFormHasData ? AnyShapeStyle(jobColor) : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
                )
                .foregroundColor(isFormHasData ? .white : .secondary)
                .cornerRadius(14)
            }
            .disabled(!isFormHasData)
            .animation(.easeInOut(duration: 0.24), value: isFormHasData)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func inputDisplayRow(title: String, value: String, field: Field) -> some View {
        let isSelected = activeField == field
        let numericVal = Double(value) ?? 0.0

        return Button {
            isEditingNotes = false
            activeField = field
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(isSelected ? .blue : .primary)
                Spacer()
                Text(numericVal, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .bold()
                    .monospacedDigit()
                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                if isSelected { BlinkingCursor() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var hoursDisplayRow: some View {
        let isSelected = activeField == .hoursWorked
        let hours = Double(hoursWorkedInput)

        return Button {
            isEditingNotes = false
            activeField = .hoursWorked
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hours Worked (Optional)")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(isSelected ? .blue : .primary)
                    if prefilledHours != nil && hoursWorkedInput == prefilledHours {
                        Text("From your schedule · tap to change")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(hours.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) hrs" } ?? "—")
                    .font(.subheadline)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(hours == nil ? .secondary : .primary)
                if isSelected { BlinkingCursor() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var undoToastView: some View {
        Button(action: undoLastSave) {
            HStack(spacing: 8) {
                Text("Shift Saved")
                    .foregroundStyle(.white)
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(.yellow)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.black.opacity(0.5), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shift saved. Undo last shift")
        .padding(.bottom, 8)
    }

    private func adjustDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func moveSelectedWeek(by value: Int) {
        guard let newWeek = Calendar.preferredWeek.date(
            byAdding: .weekOfYear,
            value: value,
            to: selectedWeekStart
        ) else {
            return
        }

        guard newWeek <= currentWeekStart else { return }

        // The card's turn animates this; animating it again here makes the new
        // amounts fade in while the card is edge-on, leaving them stuck grayed out.
        selectedWeekStart = newWeek
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func moveSelectedMonth(by value: Int) {
        guard let newMonth = Calendar.current.date(
            byAdding: .month,
            value: value,
            to: selectedMonth
        ) else {
            return
        }

        guard newMonth <= currentMonthStart else { return }

        // See moveSelectedWeek: the card's turn animates this.
        selectedMonth = newMonth
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func handleNumpadInput(_ key: String) {
        isEditingNotes = false
        var targetString: String
        switch activeField {
        case .credit: targetString = creditInput
        case .cash: targetString = cashInput
        case .barTipOut: targetString = barTipOutInput
        case .hoursWorked:
            // Typing over scheduled hours replaces them; backspace edits them.
            targetString = hoursWorkedInput == prefilledHours && key != "⌫" ? "" : hoursWorkedInput
            prefilledHours = nil
        case .hourlyRate: targetString = hourlyRateInput
        }

        if key == "⌫" {
            if !targetString.isEmpty { targetString.removeLast() }
        } else if key == "." {
            if !targetString.contains(".") {
                targetString += targetString.isEmpty ? "0." : "."
            }
        } else {
            if let dotIndex = targetString.firstIndex(of: ".") {
                let decimals = targetString[targetString.index(after: dotIndex)...]
                if decimals.count >= 2 { return }
            }
            targetString += key
        }

        switch activeField {
        case .credit: creditInput = targetString
        case .cash: cashInput = targetString
        case .barTipOut: barTipOutInput = targetString
        case .hoursWorked: hoursWorkedInput = targetString
        case .hourlyRate: hourlyRateInput = targetString
        }
    }

    private func saveShift(skipValidation: Bool = false) {
        let credit = Double(creditInput) ?? 0.0
        let cash = Double(cashInput) ?? 0.0
        let tipOut = Double(barTipOutInput) ?? 0.0
        let hoursWorked = Double(hoursWorkedInput).flatMap { $0 > 0 ? $0 : nil }
        let hourlyRate = Double(hourlyRateInput).flatMap { $0 > 0 ? $0 : nil }

        guard [credit, cash, tipOut, hoursWorked ?? 0, hourlyRate ?? 0].allSatisfy({ $0.isFinite && $0 >= 0 }),
              (credit + (hoursWorked ?? 0) * (hourlyPayEnabled ? (hourlyRate ?? 0) : 0) + (cash - tipOut)).isFinite else {
            saveError = "Enter finite, nonnegative amounts and hours."
            return
        }

        if entryValidation && !skipValidation, let warning = entryWarning(credit: credit, cash: cash, tipOut: tipOut) {
            validationMessage = warning
            return
        }

        // A rate alone earns nothing, so it doesn't make an entry worth saving.
        if credit > 0 || cash > 0 || tipOut > 0 || (hoursWorked ?? 0) > 0 {
            let newShift = Shift(
                date: selectedDate,
                creditTip: credit,
                cashTip: cash,
                barTipOut: tipOut,
                hoursWorked: hoursWorked,
                hourlyRate: hourlyPayEnabled ? (hourlyRate ?? 0) : 0,
                notes: shiftNotesEnabled ? notesInput.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                job: selectedJob
            )
            modelContext.insert(newShift)
            newShift.scheduledEventID = scheduledEventID
            if let pendingReceiptImage {
                guard let name = ReceiptStore.save(pendingReceiptImage, shiftID: newShift.id) else {
                    modelContext.rollback()
                    saveError = "The checkout slip could not be saved. Your entry is still here. Please try again."
                    return
                }
                newShift.receiptImageName = name
            }
            do {
                try modelContext.save()
            } catch {
                ReceiptStore.remove(named: newShift.receiptImageName)
                modelContext.rollback()
                saveError = "Your entry is still here. Please try again. \(error.localizedDescription)"
                return
            }

            if !reduceMotion {
                cashRain = ShiftCashRain()
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            lastSavedShift = newShift
            creditInput = ""
            cashInput = ""
            barTipOutInput = ""
            hoursWorkedInput = ""
            hourlyRateInput = ""
            notesInput = ""
            prefilledHours = nil
            scheduledEventID = nil
            scheduledEventDate = nil
            manuallySelectedJob = false
            pendingReceiptImage = nil

            withAnimation(sheetAnimation) {
                isFormExpanded = false
                isShowingReceiptScanner = false
                formSheetDragOffset = 0
                showUndoToast = true
            }

            undoTask?.cancel()
            undoTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    withAnimation { showUndoToast = false }
                }
            }
        }
    }

    private func entryWarning(credit: Double, cash: Double, tipOut: Double) -> String? {
        if credit >= 2_000 || cash >= 1_000 { return "One of these amounts is unusually high. Check for an accidental extra zero." }
        if tipOut > cash && cash > 0 { return "The tip-out is higher than the cash tips entered." }
        if tipOut >= 500 { return "This tip-out is unusually high. Please confirm it before saving." }
        return nil
    }

    private func moneyString(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Fills Hours Worked from a scheduled shift on the selected day and job.
    /// Hours the person typed are never replaced; hours we filled follow job/date changes.
    private func prefillScheduledHours() {
        guard isFormExpanded, hoursWorkedInput.isEmpty || hoursWorkedInput == prefilledHours else { return }
        let matches = ScheduleStore.shared.events.filter { event in
            !event.allDay && event.end > event.start &&
                Calendar.current.isDate(event.start, inSameDayAs: selectedDate) &&
                (selectedJob == nil || event.jobID == selectedJob?.id)
        }
        guard let event = matches.first(where: { $0.id == scheduledEventID }) ?? matches.first else {
            if prefilledHours != nil {
                hoursWorkedInput = ""
                prefilledHours = nil
            }
            return
        }
        let hours = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"),
            event.end.timeIntervalSince(event.start) / 3600)
        let trimmed = hours.contains(".")
            ? String(hours.reversed().drop { $0 == "0" }.drop { $0 == "." }.reversed())
            : hours
        hoursWorkedInput = trimmed
        prefilledHours = trimmed
    }

    private func chooseAutomaticJob() {
        selectedJob = JobLocationManager.shared.suggestedJob(jobs: jobs, date: selectedDate)
    }

    private func handleLogRoute() {
        guard AppRoute.shared.logRequest != nil else { return }
        closeTopPanel()
        if let event = AppRoute.shared.event {
            selectedDate = event.start
            selectedJob = jobs.first { $0.id == event.jobID }
            scheduledEventID = event.id
            scheduledEventDate = event.start
            manuallySelectedJob = true
        } else if let date = AppRoute.shared.logDate {
            selectedDate = date
            selectedJob = jobs.first { $0.id == AppRoute.shared.logJobID }
                ?? JobLocationManager.shared.suggestedJob(jobs: jobs, date: date)
            manuallySelectedJob = AppRoute.shared.logJobID != nil
            scheduledEventID = nil
            scheduledEventDate = nil
        }
        withAnimation(sheetAnimation) { isFormExpanded = true }
        AppRoute.shared.logRequest = nil
        AppRoute.shared.event = nil
        AppRoute.shared.logDate = nil
        AppRoute.shared.logJobID = nil
    }

    private func handleHistoryRoute() {
        guard AppRoute.shared.historyRequest != nil else { return }
        closeTopPanel()
        dismissLogForm()
        openTopPanel { isShowingHistory = true }
        AppRoute.shared.historyRequest = nil
    }

    private func handleCalendarRoute() {
        guard AppRoute.shared.calendarRequest != nil else { return }
        closeTopPanel()
        dismissLogForm()
        openTopPanel {
            calendarInitialDate = Date()
            isShowingCalendar = true
        }
        AppRoute.shared.calendarRequest = nil
    }

    private func handleTimerStartRoute() {
        guard AppRoute.shared.timerStartRequest != nil else { return }
        Task { await liveShift.start(job: selectedJob ?? jobs.first(where: \.isDefault) ?? jobs.first) }
        AppRoute.shared.timerStartRequest = nil
    }

    private func handleTimerStopRoute() {
        guard AppRoute.shared.timerStopRequest != nil else { return }
        Task { await finishLiveShift() }
        AppRoute.shared.timerStopRequest = nil
    }

    private func finishLiveShift() async {
        guard let active = liveShift.current else { return }
        closeTopPanel()
        let durationHours = max(0.25, Date().timeIntervalSince(active.startedAt) / 3600.0)
        selectedDate = active.startedAt
        selectedJob = jobs.first { $0.id == active.jobID } ?? selectedJob
        manuallySelectedJob = true
        scheduledEventID = nil
        scheduledEventDate = nil
        hoursWorkedInput = moneyString(durationHours)
        activeField = .credit
        await liveShift.stop()
        withAnimation(sheetAnimation) { isFormExpanded = true }
    }

    private func undoLastSave() {
        guard let shiftToUndo = lastSavedShift else { return }
        let receiptName = shiftToUndo.receiptImageName
        modelContext.delete(shiftToUndo)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = "The shift could not be undone. Please try again. \(error.localizedDescription)"
            return
        }

        ReceiptStore.remove(named: receiptName)
        undoTask?.cancel()

        lastSavedShift = nil
        withAnimation {
            showUndoToast = false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

private struct FirstJobCard: View {
    let onAddJob: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "briefcase.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Your First Job")
                    .font(.title3.bold())
                Text("Tell TipTrack where you work so your tips are sorted by job. You can add more anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onAddJob) {
                Text("Add a Job")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.13), lineWidth: 1.25))
    }
}

/// Shows which amount the number pad is typing into.
private struct BlinkingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.blue)
            .frame(width: 2, height: 17)
            .phaseAnimator(reduceMotion ? [true] : [true, false]) { cursor, visible in
                cursor.opacity(visible ? 1 : 0)
            } animation: { _ in
                .easeInOut(duration: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct ShiftCashRain: Identifiable {
    let id = UUID()
    let startedAt = Date()
}

private struct ShiftCashRainView: View {
    let burst: ShiftCashRain

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(burst.startedAt)
                ZStack {
                    ForEach(0..<30) { index in
                        let delay = Double((index * 7) % 30) * 0.035
                        let duration = 1.4 + Double(index % 4) * 0.1
                        let progress = min(1, max(0, (elapsed - delay) / duration))
                        let startX = geometry.size.width * (Double((index * 13) % 30) + 0.5) / 30
                        let sway = sin(progress * .pi * 2 + Double(index)) * 18
                        Image(systemName: "banknote.fill")
                            .font(.system(size: CGFloat(23 + index % 4 * 3)))
                            .foregroundStyle(index.isMultiple(of: 2) ? Color.green : Color.mint)
                            .rotationEffect(.degrees(Double(index * 37) + progress * (index.isMultiple(of: 2) ? 100 : -100)))
                            .opacity(elapsed >= delay && progress < 1 ? min(1, progress / 0.06) * 0.9 : 0)
                            .position(
                                x: startX + sway,
                                y: -50 + (geometry.size.height + 100) * pow(progress, 1.25)
                            )
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
    }
}

private struct LogEntrySheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Puts the app name on the left beside the settings cog as plain text: on iOS 26
    /// and later the toolbar would otherwise wrap it in the cog's glass bubble.
    @ViewBuilder
    func appTitleToolbar(_ title: some View) -> some View {
        if #available(iOS 26.0, *) {
            toolbar {
                ToolbarItem(placement: .topBarLeading) { title }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            toolbar {
                ToolbarItem(placement: .topBarLeading) { title }
            }
        }
    }
}

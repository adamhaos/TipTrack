import SwiftData
import SwiftUI
import UIKit

// MARK: - History
struct WeeklyHistoryView: View {
    var onClose: (() -> Void)? = nil
    var isExpanded = true
    var onCompactHeightChange: ((CGFloat) -> Void)? = nil
    /// Asks the hosting panel to grow to full height before a week opens inside it.
    var onRequestExpand: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }, sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    
    @State private var deletionError: String?
    @State private var cardsAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedWeekForBreakdown: (key: String, date: Date, shifts: [Shift])? = nil
    
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: textSize >= .xxLarge ? 1 : 2)
    }
    
    private var sixWeeksAgo: Date {
        let calendar = Calendar.preferredWeek
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: -5, to: start) ?? start
    }
    
    private var recentWeeklyGroups: [(key: String, date: Date, shifts: [Shift])] {
        let cal = Calendar.preferredWeek
        let recentShifts = shifts.filter { $0.date >= sixWeeksAgo }
        
        let grouped = Dictionary(grouping: recentShifts) { shift in
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: shift.date)
            return "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
        }
        
        return grouped.map { key, weekShifts in
            let firstDate = weekShifts.map(\.date).min() ?? Date()
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstDate)
            comps.weekday = cal.firstWeekday
            let mondayDate = cal.date(from: comps) ?? firstDate
            return (key: key, date: mondayDate, shifts: weekShifts)
        }.sorted { $0.date > $1.date }
    }
    
    private var olderMonthlyGroups: [(key: String, date: Date, shifts: [Shift])] {
        let cal = Calendar.current
        let olderShifts = shifts.filter { $0.date < sixWeeksAgo }
        
        let grouped = Dictionary(grouping: olderShifts) { shift in
            let comps = cal.dateComponents([.year, .month], from: shift.date)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }
        
        return grouped.map { key, monthShifts in
            let firstDate = monthShifts.map(\.date).min() ?? Date()
            let comps = cal.dateComponents([.year, .month], from: firstDate)
            let monthDate = cal.date(from: comps) ?? firstDate
            return (key: key, date: monthDate, shifts: monthShifts)
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if shifts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.tertiary)
                        Text("No History Yet")
                            .font(.title3)
                            .bold()
                        Text("Logged shifts will automatically group by week and month here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 32)
                } else {
                    VStack(alignment: .leading, spacing: isExpanded ? 20 : 14) {
                        if !recentWeeklyGroups.isEmpty {
                            Text("Recent weeks")
                                .font(.headline)
                                .bold()
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: columns, spacing: 12) {
                                let visibleWeeks = Array(recentWeeklyGroups.prefix(isExpanded ? recentWeeklyGroups.count : (textSize.isAccessibilitySize ? 1 : 2)))
                                ForEach(Array(visibleWeeks.enumerated()), id: \.element.key) { index, week in
                                    Button {
                                        onRequestExpand?()
                                        selectedWeekForBreakdown = week
                                    } label: {
                                        VStack(alignment: .leading, spacing: isExpanded ? 12 : 8) {
                                            HStack {
                                                Text(week.date.formatted(.dateTime.month(.abbreviated).day()))
                                                    .font(.subheadline.weight(.semibold))
                                                Spacer(minLength: 0)
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                            }
                                            RollingCurrencyText(amount: week.shifts.reduce(0) { $0 + $1.totalEarnings })
                                                .font(.title2.weight(.bold)).monospacedDigit()
                                                .lineLimit(1).minimumScaleFactor(0.75)
                                            weekWorkSummary(week.shifts)
                                            Divider()
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text("Credit").foregroundStyle(.secondary)
                                                    Text(week.shifts.reduce(0) { $0 + $1.creditEarnings }, format: .currency(code: "USD"))
                                                        .foregroundStyle(.blue).fontWeight(.semibold)
                                                }
                                                Spacer(minLength: 4)
                                                VStack(alignment: .trailing, spacing: 3) {
                                                    Text("Cash").foregroundStyle(.secondary)
                                                    Text(week.shifts.reduce(0) { $0 + $1.netCash }, format: .currency(code: "USD"))
                                                        .foregroundStyle(.green).fontWeight(.semibold)
                                                }
                                            }.font(.caption2).monospacedDigit()
                                        }
                                        .padding(isExpanded ? 16 : 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                        .contentShape(RoundedRectangle(cornerRadius: 20))
                                    }
                                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                                    .contextMenu {
                                        Button("Delete Week", systemImage: "trash", role: .destructive) { deleteShifts(week.shifts) }
                                    }
                                    // Cards fade in one after another when History opens.
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared || reduceMotion ? 0 : 14)
                                    .animation(reduceMotion ? nil : .smooth(duration: 0.4).delay(Double(index) * 0.05),
                                               value: cardsAppeared)

                                }
                            }
                            .padding(.horizontal)
                            .onAppear { cardsAppeared = true }
                        }
                        
                        if isExpanded && !olderMonthlyGroups.isEmpty {
                            Text("Months")
                                .font(.headline)
                                .bold()
                                .padding(.horizontal)
                                .padding(.top, 10)
                            
                            VStack(spacing: 12) {
                                ForEach(olderMonthlyGroups, id: \.key) { month in
                                    DisclosureGroup {
                                        VStack(spacing: 8) {
                                            ForEach(month.shifts) { shift in
                                                HStack {
                                                    VStack(alignment: .leading) {
                                                        Text(shift.date.formatted(.dateTime.weekday().month().day()))
                                                            .font(.subheadline)
                                                            .bold()
                                                        if let job = shift.job {
                                                            Label(job.name, systemImage: job.iconSymbolName)
                                                                .font(.caption2)
                                                                .foregroundColor(Color(hex: job.colorHex))
                                                        }
                                                        if let hours = shift.hoursWorked, let hourly = shift.hourlyAverage {
                                                            Text("\(hours.formatted(.number.precision(.fractionLength(0...2)))) hrs · \(hourly.formatted(.currency(code: "USD")))/hr")
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    Spacer()
                                                    Text(shift.totalEarnings, format: .currency(code: "USD"))
                                                        .font(.subheadline)
                                                        .bold()
                                                        .monospacedDigit()
                                                }
                                                .padding(.vertical, 4)
                                                Divider()
                                            }
                                        }
                                        .padding(.top, 8)
                                    } label: {
                                        let creditTotal = month.shifts.reduce(0) { $0 + $1.creditEarnings }
                                        let netCashTotal = month.shifts.reduce(0) { $0 + $1.netCash }
                                        let barTipOutTotal = month.shifts.reduce(0) { $0 + $1.barTipOut }
                                        let monthTotal = month.shifts.reduce(0) { $0 + $1.totalEarnings }

                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(month.date.formatted(.dateTime.month(.wide).year()))
                                                    .font(.headline)
                                                Text("\(month.shifts.count) shifts")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text("Credit \(creditTotal, format: .currency(code: "USD")) · Cash \(netCashTotal, format: .currency(code: "USD"))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                if barTipOutTotal > 0 {
                                                    Text("Bar out \(barTipOutTotal, format: .currency(code: "USD"))")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Text(monthTotal, format: .currency(code: "USD"))
                                                .font(.headline)
                                                .monospacedDigit()
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding()
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .cornerRadius(14)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, isExpanded ? 12 : 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if !isExpanded { onCompactHeightChange?(height + 128) }
                    }
                }
            }
            .scrollDisabled(!isExpanded)
            .protectEarnings()
            .safeAreaInset(edge: .bottom) { DeletionUndoBar() }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .saveErrorAlert($deletionError)
            .navigationTitle("Recents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { if let onClose { onClose() } else { dismiss() } }
                }
            }
            // Opens inside this panel rather than as a second pane on top of it.
            .navigationDestination(isPresented: Binding(
                get: { selectedWeekForBreakdown != nil },
                set: { if !$0 { selectedWeekForBreakdown = nil } }
            )) {
                if let week = selectedWeekForBreakdown {
                    WeekBreakdownView(week: week, embedded: true)
                }
            }
        }
    }
    
    private func deleteShifts(_ shiftsToDelete: [Shift]) {
        deletionError = ShiftDeletion.remove(shiftsToDelete, context: modelContext)
    }

    /// Shift count and hours, plus the hourly average across shifts with hours logged.
    private func weekWorkSummary(_ weekShifts: [Shift]) -> some View {
        let count = weekShifts.count
        let hours = weekShifts.reduce(0) { $0 + ($1.hoursWorked ?? 0) }
        let hourly = TipTrackSiriRules.hourlyAverage(
            earningsAndHours: weekShifts.map { ($0.totalEarnings, $0.hoursWorked) })
        return VStack(alignment: .leading, spacing: 2) {
            Text(hours > 0
                ? "\(count) \(count == 1 ? "shift" : "shifts") · \(hours.formatted(.number.precision(.fractionLength(0...2)))) hrs"
                : "\(count) \(count == 1 ? "shift" : "shifts")")
            if let hourly {
                Text("\(hourly.formatted(.currency(code: "USD")))/hr")
                    .fontWeight(.semibold)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Month Breakdown
struct MonthBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let month: (key: String, date: Date, shifts: [Shift])
    @State private var shiftToEdit: Shift?

    private struct DayGroup: Identifiable {
        let date: Date
        let shifts: [Shift]
        var id: Date { date }
    }

    private struct WeekGroup: Identifiable {
        let startDate: Date
        let days: [DayGroup]
        var id: Date { startDate }

        var shifts: [Shift] {
            days.flatMap(\.shifts)
        }
    }

    private var activeShifts: [Shift] {
        month.shifts.filter { $0.deletedAt == nil }.sorted { $0.date > $1.date }
    }

    private var groupedWeeks: [WeekGroup] {
        let calendar = Calendar.preferredWeek
        return Dictionary(grouping: activeShifts) { shift in
            let day = calendar.startOfDay(for: shift.date)
            let weekday = calendar.component(.weekday, from: day)
            let daysSinceWeekStart = (weekday - calendar.firstWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: -daysSinceWeekStart, to: day) ?? day
        }
        .map { weekStart, weekShifts in
            let days = Dictionary(grouping: weekShifts) { calendar.startOfDay(for: $0.date) }
                .map { DayGroup(date: $0.key, shifts: $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.date < $1.date }
            return WeekGroup(startDate: weekStart, days: days)
        }
        .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groupedWeeks.isEmpty {
                    ContentUnavailableView("No Shifts This Month", systemImage: "calendar",
                        description: Text("There are no logged shifts for this month."))
                } else {
                    List {
                        Section {
                            HStack {
                                Label("Monthly Total", systemImage: "banknote")
                                Spacer()
                                Text(activeShifts.reduce(0) { $0 + $1.totalEarnings },
                                     format: .currency(code: "USD"))
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                        }

                        ForEach(groupedWeeks) { week in
                            Section {
                                ForEach(week.days) { day in
                                    HStack {
                                        Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 10, leading: 4, bottom: 0, trailing: 0))

                                    ForEach(day.shifts) { shift in
                                        Button { shiftToEdit = shift } label: {
                                            monthlyShiftRow(shift)
                                        }
                                        .buttonStyle(.plain)
                                        .shiftQuickActions(shift) { shiftToEdit = shift }
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                                    }
                                }
                            } header: {
                                weekHeader(week)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .protectEarnings()
            .safeAreaInset(edge: .bottom) { DeletionUndoBar() }
            .navigationTitle(month.date.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shiftToEdit) { EditShiftSheet(shift: $0) }
        }
    }

    private func weekHeader(_ week: WeekGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Week of \(week.startDate.formatted(.dateTime.month(.abbreviated).day()))")

            Spacer()

            Text("\(week.shifts.count) \(week.shifts.count == 1 ? "shift" : "shifts") · \(week.shifts.reduce(0) { $0 + $1.totalEarnings }, format: .currency(code: "USD"))")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func monthlyShiftRow(_ shift: Shift) -> some View {
        HistoryShiftRow(shift: shift)
    }

}

// MARK: - 11. Week Breakdown View & Edit Shift Sheet
struct WeekBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let week: (key: String, date: Date, shifts: [Shift])
    /// Pushed inside another navigation stack, which supplies the back button.
    var embedded = false
    @State private var deletionError: String?
    @State private var shiftToEdit: Shift? = nil
    
    private var daysInWeek: [Date] {
        let cal = Calendar.preferredWeek
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: week.date)
        comps.weekday = cal.firstWeekday
        guard let weekStart = cal.date(from: comps) else { return [] }
        return (0...6).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }
    
    var body: some View {
        if embedded {
            breakdownList
        } else {
            NavigationStack {
                breakdownList
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }

    private var breakdownList: some View {
            List {
                ForEach(daysInWeek, id: \.self) { day in
                    let dailyShifts = week.shifts.filter { $0.deletedAt == nil && Calendar.preferredWeek.isDate($0.date, inSameDayAs: day) }
                    
                    Section(header: Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))) {
                        if dailyShifts.isEmpty {
                            Text("No shifts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        } else {
                            ForEach(dailyShifts) { shift in
                                Button {
                                    shiftToEdit = shift
                                } label: {
                                    HistoryShiftRow(shift: shift)
                                }
                                .buttonStyle(.plain)
                                .shiftQuickActions(shift) { shiftToEdit = shift }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deletionError = ShiftDeletion.remove([shift], context: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .protectEarnings()
            .safeAreaInset(edge: .bottom) { DeletionUndoBar() }
            .saveErrorAlert($deletionError)
            .navigationTitle("Week Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $shiftToEdit) { shift in
                EditShiftSheet(shift: shift)
            }
    }
}

struct EditShiftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.name) private var jobs: [Job]
    
    let shift: Shift
    
    @State private var shiftDate: Date = Date()
    @State private var selectedJob: Job? = nil
    @State private var creditInput: String = ""
    @State private var cashInput: String = ""
    @State private var barTipOutInput: String = ""
    @State private var hoursWorkedInput: String = ""
    @State private var hourlyRateInput: String = ""
    @State private var notesInput: String = ""
    @AppStorage(FeatureKeys.shiftNotes) private var shiftNotesEnabled = false
    @AppStorage(FeatureKeys.hourlyPayEnabled) private var hourlyPayEnabled = true
    @AppStorage(FeatureKeys.receipts) private var receiptFeatures = false
    @State private var receiptImage: UIImage?
    @State private var receiptChanged = false
    @State private var isShowingReceiptScanner = false
    @State private var isShowingShareSummary = false
    @State private var saveError: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShiftDetailsSummary(
                        name: selectedJob?.name ?? "Unassigned",
                        symbol: selectedJob?.iconSymbolName ?? "briefcase.fill",
                        color: selectedJob.map { Color(hex: $0.colorHex) } ?? .accentColor,
                        total: summaryTotal,
                        hours: TipTrackSiriRules.inputAmount(hoursWorkedInput) ?? 0
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section("Shift Details") {
                    DatePicker("Shift Date", selection: $shiftDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Picker("Job", selection: $selectedJob) {
                        Text("None").tag(Job?.none)
                        ForEach(jobs) { job in
                            Label(job.name, systemImage: job.iconSymbolName)
                                .foregroundStyle(Color(hex: job.colorHex)).tag(Job?.some(job))
                        }
                    }
                    
                }

                Section("Tips") {
                    HStack {
                        Text("Credit Tips")
                        Spacer()
                        TextField("0.00", text: $creditInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Cash Tips")
                        Spacer()
                        TextField("0.00", text: $cashInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Tip Out")
                        Spacer()
                        TextField("0.00", text: $barTipOutInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                }

                Section("Hours & Pay") {
                    HStack {
                        Text("Hours Worked")
                        Spacer()
                        TextField("Optional", text: $hoursWorkedInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if hourlyPayEnabled {
                        HStack {
                            Text("Hourly Rate")
                            Spacer()
                            TextField("Optional", text: $hourlyRateInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                // Keep an existing note editable even after notes are turned off.
                if shiftNotesEnabled || !shift.notes.isEmpty {
                    Section("Notes") {
                        TextField("Private party, slow night, covered a shift…", text: $notesInput, axis: .vertical)
                            .lineLimit(1...5)
                    }
                }
                if receiptFeatures {
                    Section("Checkout Slip") {
                        if let receiptImage {
                            Image(uiImage: receiptImage).resizable().scaledToFit().frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button {
                            isShowingReceiptScanner = true
                        } label: {
                            Label(receiptImage == nil ? "Attach or Scan Receipt" : "Replace Receipt", systemImage: "doc.viewfinder")
                        }
                    }
                }
            }
            .listSectionSpacing(.custom(12))
            .contentMargins(.top, 8, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 44)
            .protectEarnings()
            .navigationTitle("Edit Shift")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                shiftDate = shift.date
                selectedJob = shift.job
                creditInput = String(shift.creditTip)
                cashInput = String(shift.cashTip)
                barTipOutInput = String(shift.barTipOut)
                hoursWorkedInput = shift.hoursWorked.map { String($0) } ?? ""
                hourlyRateInput = shift.hourlyRate > 0 ? String(shift.hourlyRate) : ""
                notesInput = shift.notes
                receiptImage = ReceiptStore.image(named: shift.receiptImageName)
            }
            .sheet(isPresented: $isShowingReceiptScanner) {
                ReceiptScannerView(preferredReportType: ShiftReportType(rawValue: selectedJob?.receiptPOS ?? "") ?? .automatic) { scanned in
                    receiptImage = scanned.image
                    receiptChanged = true
                    if let value = scanned.credit { creditInput = String(value) }
                    if let value = scanned.cash { cashInput = String(value) }
                    if let value = scanned.tipOut { barTipOutInput = String(value) }
                    if let value = scanned.hours { hoursWorkedInput = String(value) }
                }
            }
            .alert("Couldn't Save Shift", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "") }
            .sheet(isPresented: $isShowingShareSummary) {
                ShareShiftSummaryView(shift: shift)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingShareSummary = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share Shift Summary")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(PrivacyManager.shared.hidden)
                }
            }
        }
    }

    private var summaryTotal: Double {
        let credit = TipTrackSiriRules.inputAmount(creditInput) ?? 0
        let cash = TipTrackSiriRules.inputAmount(cashInput) ?? 0
        let tipOut = TipTrackSiriRules.inputAmount(barTipOutInput) ?? 0
        let hours = TipTrackSiriRules.inputAmount(hoursWorkedInput) ?? 0
        let rate = hourlyPayEnabled ? (TipTrackSiriRules.inputAmount(hourlyRateInput) ?? 0) : shift.hourlyRate
        let total = credit + cash - tipOut + hours * rate
        return total.isFinite ? total : 0
    }

    private func saveChanges() {
        guard let credit = TipTrackSiriRules.inputAmount(creditInput),
              let cash = TipTrackSiriRules.inputAmount(cashInput),
              let tipOut = TipTrackSiriRules.inputAmount(barTipOutInput),
              let hours = TipTrackSiriRules.inputAmount(hoursWorkedInput),
              let rate = hourlyPayEnabled ? TipTrackSiriRules.inputAmount(hourlyRateInput) : shift.hourlyRate,
              (credit + hours * rate + (cash - tipOut)).isFinite else {
            saveError = "Enter valid, nonnegative amounts and hours before saving."
            return
        }
        let previousReceipt = shift.receiptImageName
        var replacementReceipt: String?
        if receiptChanged, let receiptImage {
            guard let name = ReceiptStore.save(receiptImage, shiftID: UUID()) else {
                saveError = "The checkout slip could not be saved. Your changes are still here. Please try again."
                return
            }
            replacementReceipt = name
        }
        if shift.date != shiftDate || shift.job?.id != selectedJob?.id {
            shift.scheduledEventID = nil
        }
        shift.date = shiftDate
        shift.job = selectedJob
        shift.creditTip = credit
        shift.cashTip = cash
        shift.barTipOut = tipOut
        shift.hoursWorked = hours > 0 ? hours : nil
        shift.hourlyRate = rate
        shift.notes = notesInput.trimmingCharacters(in: .whitespacesAndNewlines)
        shift.sourceFingerprint = nil
        if let replacementReceipt { shift.receiptImageName = replacementReceipt }
        do {
            try modelContext.save()
            if replacementReceipt != nil { ReceiptStore.remove(named: previousReceipt) }
            dismiss()
        } catch {
            ReceiptStore.remove(named: replacementReceipt)
            modelContext.rollback()
            saveError = "Your changes could not be saved. Please try again. \(error.localizedDescription)"
        }
    }

}

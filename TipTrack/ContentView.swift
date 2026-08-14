import SwiftUI
import SwiftData

// MARK: - 1. SwiftData Model
@Model
class Shift {
    var date: Date
    var creditTip: Double
    var cashTip: Double
    var barTipOut: Double
    
    var netCash: Double {
        cashTip - barTipOut
    }
    
    init(date: Date, creditTip: Double, cashTip: Double, barTipOut: Double = 0.0) {
        self.date = date
        self.creditTip = creditTip
        self.cashTip = cashTip
        self.barTipOut = barTipOut
    }
}

// MARK: - 2. Shared Calendar Helper
extension Calendar {
    static var mondayStart: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // 2 = Monday
        return cal
    }
    
    static var mondayToSundayRange: [Date] {
        let today = Date()
        var components = mondayStart.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        components.weekday = 2 // Start at Monday
        
        guard let monday = mondayStart.date(from: components) else { return [] }
        
        return (0...6).compactMap { dayOffset in
            mondayStart.date(byAdding: .day, value: dayOffset, to: monday)
        }
    }
}

// MARK: - 3. Root View with 3 Tabs
enum Tab {
    case history
    case logAndTotals
    case weeklySchedule
}

struct ContentView: View {
    @State private var selectedTab: Tab = .logAndTotals
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WeeklyHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.history)
            
            LogAndTotalsView()
                .tabItem {
                    Label("Log & Totals", systemImage: "dollarsign.circle.fill")
                }
                .tag(Tab.logAndTotals)
            
            WeeklyScheduleView()
                .tabItem {
                    Label("Weekly Schedule", systemImage: "calendar")
                }
                .tag(Tab.weeklySchedule)
        }
    }
}

// MARK: - 4. Tab 1: Weekly History (2-Column Grid Card Layout)
struct WeeklyHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.date, order: .reverse) private var shifts: [Shift]
    
    @State private var showClearConfirmation = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private var weekDays: [Date] { Calendar.mondayToSundayRange }
    
    private var groupedWeeks: [(key: String, date: Date, shifts: [Shift])] {
        let cal = Calendar.mondayStart
        let grouped = Dictionary(grouping: shifts) { shift in
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: shift.date)
            return "\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
        }
        
        return grouped.map { key, weekShifts in
            let firstDate = weekShifts.map(\.date).min() ?? Date()
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstDate)
            comps.weekday = 2
            let mondayDate = cal.date(from: comps) ?? firstDate
            
            return (key: key, date: mondayDate, shifts: weekShifts)
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if groupedWeeks.isEmpty {
                    ContentUnavailableView("No History Yet", systemImage: "tray", description: Text("Logged shifts will be automatically grouped by week here."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(groupedWeeks, id: \.key) { week in
                            let creditTotal = week.shifts.reduce(0) { $0 + $1.creditTip }
                            let netCashTotal = week.shifts.reduce(0) { $0 + $1.netCash }
                            let barTipOutTotal = week.shifts.reduce(0) { $0 + $1.barTipOut }
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Week of")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .bold()
                                
                                Text(week.date.formatted(.dateTime.month(.wide).day().year()))
                                    .font(.subheadline)
                                    .bold()
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Credit:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(creditTotal, format: .currency(code: "USD"))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Net Cash:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(netCashTotal, format: .currency(code: "USD"))
                                            .font(.headline)
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                if barTipOutTotal > 0 {
                                    Text("Bar Out: \(barTipOutTotal, format: .currency(code: "USD"))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Weekly History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    clearButton
                }
            }
            .confirmationDialog("Clear Shifts", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear Current Week Only", role: .destructive, action: clearCurrentWeekShifts)
                Button("Clear All Time Data", role: .destructive, action: clearAllShifts)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Select whether to clear shifts for this week only or purge all recorded data.")
            }
        }
    }
    
    private var clearButton: some View {
        Button(role: .destructive) {
            showClearConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.red)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        }
    }
    
    private func clearCurrentWeekShifts() {
        let currentWeekShifts = shifts.filter { shift in
            weekDays.contains { Calendar.mondayStart.isDate(shift.date, inSameDayAs: $0) }
        }
        for shift in currentWeekShifts {
            modelContext.delete(shift)
        }
        try? modelContext.save()
    }
    
    private func clearAllShifts() {
        for shift in shifts {
            modelContext.delete(shift)
        }
        try? modelContext.save()
    }
}

// MARK: - 5. Tab 2: Log & Totals (No Trash Can, Dynamic Save Button, Compact Layout)
struct LogAndTotalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.date, order: .forward) private var shifts: [Shift]
    
    @State private var selectedDate = Date()
    @State private var creditInput: String = ""
    @State private var cashInput: String = ""
    @State private var barTipOutInput: String = ""
    
    @FocusState private var isInputFocused: Bool
    
    private var weekDays: [Date] { Calendar.mondayToSundayRange }
    
    private var weeklyCreditTotal: Double {
        shifts.filter { shift in
            weekDays.contains { Calendar.mondayStart.isDate(shift.date, inSameDayAs: $0) }
        }.reduce(0) { $0 + $1.creditTip }
    }
    
    private var weeklyNetCashTotal: Double {
        shifts.filter { shift in
            weekDays.contains { Calendar.mondayStart.isDate(shift.date, inSameDayAs: $0) }
        }.reduce(0) { $0 + $1.netCash }
    }
    
    // Checks if at least one entry field has valid input (> 0)
    private var isFormHasData: Bool {
        (Double(creditInput) ?? 0.0 > 0) ||
        (Double(cashInput) ?? 0.0 > 0) ||
        (Double(barTipOutInput) ?? 0.0 > 0)
    }
    
    // Dynamic text for Save Button showing date
    private var saveButtonText: String {
        let formattedDate = selectedDate.formatted(.dateTime.month().day())
        return "Save Shift for \(formattedDate)"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                totalsSummaryView
                
                Divider()
                
                shiftEntryFormView
                
                Spacer()
            }
            .padding(.top, 8)
            .padding(.top, 8)
            .navigationTitle("Tip Tracker")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                    .font(.headline)
                    .padding(.bottom, 10) // Raised slightly higher above number pad
                }
            }
        }
    }
    
    private var totalsSummaryView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Credit Paycheck (Pre Tax):")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.blue)
                    Text(weeklyCreditTotal, format: .currency(code: "USD"))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.9)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(Color.blue.opacity(0.12))
            .cornerRadius(18)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Cash Paycheck (Net):")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.green)
                    Text(weeklyNetCashTotal, format: .currency(code: "USD"))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.8)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(Color.green.opacity(0.12))
            .cornerRadius(18)
        }
        .padding(.horizontal)
    }
    
    private var shiftEntryFormView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Log Shift Income")
                .font(.headline)
            
            DatePicker("Shift Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            
            TextField("Credit Tips ($)", text: $creditInput)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
            
            TextField("Cash Tips ($)", text: $cashInput)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
            
            TextField("Bar Tip Out ($)", text: $barTipOutInput)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
            
            Button(action: saveShift) {
                Text(saveButtonText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isFormHasData ? Color.green : Color.black) // Turns green when data is entered
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .animation(.easeInOut(duration: 0.2), value: isFormHasData)
        }
        .padding(.horizontal)
    }
    
    private func saveShift() {
        let credit = Double(creditInput) ?? 0.0
        let cash = Double(cashInput) ?? 0.0
        let tipOut = Double(barTipOutInput) ?? 0.0
        
        if credit > 0 || cash > 0 || tipOut > 0 {
            let newShift = Shift(date: selectedDate, creditTip: credit, cashTip: cash, barTipOut: tipOut)
            modelContext.insert(newShift)
            
            try? modelContext.save()
            
            creditInput = ""
            cashInput = ""
            barTipOutInput = ""
            isInputFocused = false
        }
    }
}

// MARK: - 6. Tab 3: Weekly Schedule
struct WeeklyScheduleView: View {
    @Query(sort: \Shift.date, order: .forward) private var shifts: [Shift]
    
    private var weekDays: [Date] { Calendar.mondayToSundayRange }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monday to Sunday Breakdown")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 8) {
                    ForEach(weekDays, id: \.self) { day in
                        let dailyShifts = shifts.filter { Calendar.mondayStart.isDate($0.date, inSameDayAs: day) }
                        let dailyCredit = dailyShifts.reduce(0) { $0 + $1.creditTip }
                        let dailyNetCash = dailyShifts.reduce(0) { $0 + $1.netCash }
                        
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(.subheadline)
                                .bold()
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Credit: \(dailyCredit, format: .currency(code: "USD"))")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.blue)
                                Text("Net Cash: \(dailyNetCash, format: .currency(code: "USD"))")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            .navigationTitle("Weekly Schedule")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Shift.self, inMemory: true)
}

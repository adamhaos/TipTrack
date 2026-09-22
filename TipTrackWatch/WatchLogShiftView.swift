import SwiftUI
import WatchKit

struct WatchLogShiftView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = WatchSessionStore.shared
    private let draft: WatchLogDraft
    @State private var jobID: UUID?
    @State private var date: Date
    @State private var credit = ""
    @State private var cash = ""
    @State private var tipOut = ""
    @State private var hours: String

    init(draft: WatchLogDraft) {
        self.draft = draft
        _jobID = State(initialValue: draft.jobID)
        _date = State(initialValue: draft.date)
        _hours = State(initialValue: draft.hours.map { String($0) } ?? "")
    }

    private var values: (credit: Double, cash: Double, tipOut: Double, hours: Double) {
        (Double(credit) ?? 0, Double(cash) ?? 0, Double(tipOut) ?? 0, Double(hours) ?? 0)
    }

    // The last two weeks, newest first; the inline date wheels were too cramped on a watch.
    private var recentDays: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        var days = (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
        let draftDay = Calendar.current.startOfDay(for: draft.date)
        if !days.contains(draftDay) { days.append(draftDay) }
        return days
    }

    // Picks a day while keeping the time of day, so an ended live shift keeps its start time.
    private var dayBinding: Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: date) }, set: { day in
            let time = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            date = Calendar.current.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
                second: time.second ?? 0, of: day) ?? day
        })
    }

    private func dayName(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var saveColor: Color {
        (store.jobs.first { $0.id == jobID } ?? store.defaultJob).map { Color(watchHex: $0.colorHex) } ?? .accentColor
    }

    private var canSave: Bool {
        let v = values
        return v.credit > 0 || v.cash > 0 || v.tipOut > 0 || v.hours > 0
    }

    private var job: WatchJob? {
        store.jobs.first { $0.id == jobID }
    }

    private var total: Double {
        values.credit + values.cash - values.tipOut
    }

    // One fixed page: Job and Date, then the four amounts as a 2×3 grid of tiles, with
    // Save underneath. Tile heights come from the screen so it fits every watch size.
    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 6
            let saveHeight: CGFloat = 34
            let tileHeight = max(34, (geometry.size.height - saveHeight - spacing * 3) / 3)
            VStack(spacing: spacing) {
                Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                    GridRow {
                        NavigationLink {
                            WatchChoiceList(title: "Job", options: store.jobs.map { ($0.id as UUID?, $0.name) },
                                selection: $jobID)
                        } label: {
                            tile("Job", value: job?.name ?? "None")
                        }
                        .disabled(store.jobs.isEmpty)
                        NavigationLink {
                            WatchChoiceList(title: "Date", options: recentDays.map { ($0, dayName($0)) },
                                selection: dayBinding)
                        } label: {
                            tile("Date", value: dayName(Calendar.current.startOfDay(for: date)))
                        }
                    }
                    GridRow {
                        amountTile("Credit", text: $credit)
                        amountTile("Cash", text: $cash)
                    }
                    GridRow {
                        amountTile("Tip Out", text: $tipOut)
                        NavigationLink {
                            WatchKeypadView(title: "Hours", text: $hours, isCurrency: false)
                        } label: {
                            tile("Hours", value: hours.isEmpty ? "—" : hours)
                        }
                    }
                }
                .frame(height: tileHeight * 3 + spacing * 2)
                .buttonStyle(.plain)

                Button(action: save) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(canSave ? "Save \(total.formatted(.currency(code: "USD")))" : "Save Shift")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: saveHeight)
                    // Same color as the Log Shift button that opened this form.
                    .background(saveColor.opacity(canSave ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .navigationTitle("Log Shift")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, value: String) -> some View {
        // Centered, with room on every side, so values sit inside the tile instead of
        // crowding its bottom edge.
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func amountTile(_ title: String, text: Binding<String>) -> some View {
        NavigationLink {
            WatchKeypadView(title: title, text: text, isCurrency: true)
        } label: {
            tile(title, value: (Double(text.wrappedValue) ?? 0).formatted(.currency(code: "USD")))
        }
    }

    private func save() {
        let v = values
        store.log(WatchShiftEntry(id: draft.id, date: date, jobID: jobID, creditTip: v.credit, cashTip: v.cash,
            tipOut: v.tipOut, hoursWorked: v.hours > 0 ? v.hours : nil))
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}

struct WatchKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var text: String
    let isCurrency: Bool
    @State private var entry = ""

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]

    private var display: String {
        let value = entry.isEmpty ? "0" : entry
        return isCurrency ? "$" + value : value
    }

    var body: some View {
        // Keys are sized from the space left under the amount, so the pad fits every watch size.
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let displayHeight: CGFloat = 28
            let keyHeight = max(22, (geometry.size.height - displayHeight - spacing * 4) / 4)
            VStack(spacing: spacing) {
                HStack(spacing: 6) {
                    Text(display)
                        .font(.system(.title3, design: .rounded).monospacedDigit().bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        text = entry
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.footnote.bold())
                            .foregroundStyle(.black)
                            .frame(width: displayHeight, height: displayHeight)
                            .background(Color.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                }
                .frame(height: displayHeight)
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                press(key)
                            } label: {
                                Group {
                                    if key == "⌫" {
                                        Image(systemName: "delete.left")
                                    } else {
                                        Text(key)
                                    }
                                }
                                .font(.system(size: min(20, keyHeight * 0.55), weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(key == "⌫" ? "Delete" : key)
                        }
                    }
                    .frame(height: keyHeight)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entry = text }
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !entry.isEmpty { entry.removeLast() }
        case ".":
            if !entry.contains(".") { entry += entry.isEmpty ? "0." : "." }
        default:
            // Two decimal places and a sane upper bound for one shift.
            if let dot = entry.firstIndex(of: "."), entry.distance(from: dot, to: entry.endIndex) > 2 { return }
            guard entry.count < 7 else { return }
            entry = entry == "0" ? key : entry + key
        }
    }
}

// A short list to pick one value from, for the Job and Date tiles.
struct WatchChoiceList<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        List(options, id: \.0) { option in
            Button {
                selection = option.0
                dismiss()
            } label: {
                HStack {
                    Text(option.1)
                    Spacer()
                    if option.0 == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

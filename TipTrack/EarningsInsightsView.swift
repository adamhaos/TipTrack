import SwiftUI
import SwiftData

extension Shift {
    var earningsRecord: EarningsRecord {
        EarningsRecord(id: id, date: date, earnings: totalEarnings, hours: hoursWorked,
            jobID: job?.id, jobName: job?.name ?? "Unassigned")
    }
}

struct EarningsInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }, sort: \Shift.date, order: .reverse) private var shifts: [Shift]

    var body: some View {
        let records = shifts.map(\.earningsRecord).filter { $0.date <= Date() }
        let calendar = Calendar.preferredWeek
        let best = records.filter { ($0.hours ?? 0) > 0 }.sorted {
            let left = $0.earnings / ($0.hours ?? 1)
            let right = $1.earnings / ($1.hours ?? 1)
            return left == right ? $0.date > $1.date : left > right
        }
        NavigationStack {
            List {
                Section("How am I doing?") {
                    if let comparison = EarningsInsights.comparison(records, now: Date(), calendar: calendar) {
                        let difference = comparison.current - comparison.usual
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(abs(difference), format: .currency(code: "USD")) \(difference >= 0 ? "ahead of" : "behind") your usual pace")
                                    .font(.headline)
                                Text("This week: \(comparison.current, format: .currency(code: "USD")) · Usual: \(comparison.usual, format: .currency(code: "USD"))")
                                    .font(.subheadline).monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: difference >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                                .foregroundStyle(difference >= 0 ? .green : .orange)
                        }
                        Text("Through \(Date().formatted(.dateTime.weekday(.wide))), compared with the same days in \(comparison.weeks) logged weeks from the last four weeks. Based on logged earnings, including wages and tip-out.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Log shifts in at least two of the previous four weeks to see your usual pace.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Best shifts · per hour") {
                    ForEach(Array(best.prefix(3))) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.jobName).font(.headline)
                                Text(record.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\((record.earnings / (record.hours ?? 1)).formatted(.currency(code: "USD")))/hr").bold()
                                Text(record.earnings, format: .currency(code: "USD")).font(.caption).foregroundStyle(.secondary)
                            }.monospacedDigit()
                        }
                    }
                    if best.isEmpty { Text("Add hours to your logged shifts to discover your best shifts.").foregroundStyle(.secondary) }
                }
                rankingSection("Best jobs · per hour", records: records, byWeekday: false, calendar: calendar)
                rankingSection("Best weekdays · per hour", records: records, byWeekday: true, calendar: calendar)
                Section {
                    Text("Rankings use all logged shifts with recorded hours. Job and weekday averages divide total earnings by total hours; shifts without hours are excluded. A small number of shifts may not represent your usual results.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .protectEarnings()
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func rankingSection(_ title: String, records: [EarningsRecord], byWeekday: Bool, calendar: Calendar) -> some View {
        Section(title) {
            ForEach(EarningsInsights.rankings(records, byWeekday: byWeekday, calendar: calendar).prefix(3)) { rank in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rank.name).font(.headline)
                        Text("\(rank.count) \(rank.count == 1 ? "timed shift" : "timed shifts")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(rank.hourly.formatted(.currency(code: "USD")))/hr").bold().monospacedDigit()
                }
            }
            if records.allSatisfy({ ($0.hours ?? 0) <= 0 }) { Text("No shifts with recorded hours yet.").foregroundStyle(.secondary) }
        }
    }
}

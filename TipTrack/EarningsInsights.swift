import Foundation

nonisolated struct EarningsRecord: Sendable, Identifiable {
    let id: UUID
    let date: Date
    let earnings: Double
    let hours: Double?
    let jobID: UUID?
    let jobName: String
}

nonisolated enum EarningsInsights {
    struct Ranking: Identifiable {
        let id: String
        let name: String
        let earnings: Double
        let hours: Double
        let count: Int
        var hourly: Double { earnings / hours }
    }

    struct Comparison {
        let current: Double
        let usual: Double
        let weeks: Int
    }

    static func rankings(_ records: [EarningsRecord], byWeekday: Bool, calendar: Calendar) -> [Ranking] {
        let timed = records.filter { ($0.hours ?? 0) > 0 }
        let groups = Dictionary(grouping: timed) { record in
            byWeekday ? String(calendar.component(.weekday, from: record.date)) : record.jobID?.uuidString ?? "unassigned"
        }
        return groups.map { key, values in
            let name = byWeekday ? calendar.weekdaySymbols[Int(key)! - 1] : values[0].jobName
            return Ranking(id: key, name: name, earnings: values.reduce(0) { $0 + $1.earnings },
                hours: values.reduce(0) { $0 + ($1.hours ?? 0) }, count: values.count)
        }.sorted { $0.hourly == $1.hourly ? $0.id < $1.id : $0.hourly > $1.hourly }
    }

    static func comparison(_ records: [EarningsRecord], now: Date, calendar: Calendar) -> Comparison? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let days = calendar.dateComponents([.day], from: week.start, to: tomorrow).day ?? 1
        var historical: [Double] = []
        for offset in 1...4 {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: week.start),
                  let end = calendar.date(byAdding: .day, value: 7, to: start),
                  let cutoff = calendar.date(byAdding: .day, value: days, to: start) else { continue }
            let logged = records.filter { $0.date >= start && $0.date < end }
            // An entirely unlogged week cannot tell us what the person earned.
            if !logged.isEmpty {
                historical.append(logged.filter { $0.date < cutoff }.reduce(0) { $0 + $1.earnings })
            }
        }
        guard historical.count >= 2 else { return nil }
        return Comparison(current: records.filter { $0.date >= week.start && $0.date < tomorrow }.reduce(0) { $0 + $1.earnings },
            usual: historical.reduce(0, +) / Double(historical.count), weeks: historical.count)
    }
}


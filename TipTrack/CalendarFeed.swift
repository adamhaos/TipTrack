import Foundation

struct ScheduledShift: Codable, Identifiable, Equatable {
    var id: String
    var jobID: UUID
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    /// The feed this shift was downloaded from; nil for caches written before feeds were tracked.
    var feedID: UUID? = nil
}

// Feed parsing is independent of SwiftData and can be tested with fixture calendars.
enum CalendarFeed {
    struct Property {
        var name: String
        var parameters: [String: String]
        var value: String
    }
    enum FeedError: LocalizedError {
        case invalid, unsupportedRecurrence
        var errorDescription: String? {
            switch self {
            case .invalid: "The link did not return a valid iCalendar schedule."
            case .unsupportedRecurrence: "This calendar uses an unsupported repeating-event rule. Use a feed with individual scheduled shifts."
            }
        }
    }
    static func url(_ text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst(9) }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func parse(_ text: String, jobID: UUID, now: Date = Date()) throws -> [ScheduledShift] {
        guard text.contains("BEGIN:VCALENDAR"), text.contains("END:VCALENDAR") else { throw FeedError.invalid }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        var blocks: [[Property]] = []
        var current: [Property]? = nil
        var nested = 0
        for line in normalized.components(separatedBy: "\n") {
            if line == "BEGIN:VEVENT" { current = []; nested = 0; continue }
            if line == "END:VEVENT" { if let current { blocks.append(current) }; current = nil; continue }
            guard current != nil else { continue }
            if line.hasPrefix("BEGIN:") { nested += 1; continue }
            if line.hasPrefix("END:") { nested -= 1; continue }
            guard nested == 0, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon].components(separatedBy: ";")
            var params: [String: String] = [:]
            for parameter in head.dropFirst() {
                let pair = parameter.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            current?.append(Property(name: head[0].uppercased(), parameters: params,
                value: String(line[line.index(after: colon)...])))
        }
        let lower = Calendar.current.date(byAdding: .month, value: -12, to: now) ?? now.addingTimeInterval(-365 * 86400)
        let upper = Calendar.current.date(byAdding: .month, value: 3, to: now) ?? now.addingTimeInterval(90 * 86400)
        var result: [String: ScheduledShift] = [:]
        for block in blocks where !block.contains(where: { $0.name == "RECURRENCE-ID" }) {
            guard !block.contains(where: { $0.name == "STATUS" && $0.value == "CANCELLED" }) else { continue }
            guard let startProp = block.first(where: { $0.name == "DTSTART" }),
                  let start = date(startProp) else { throw FeedError.invalid }
            let allDay = startProp.parameters["VALUE"] == "DATE" || startProp.value.count == 8
            let end = block.first(where: { $0.name == "DTEND" }).flatMap { date($0) } ??
                start.addingTimeInterval(block.first(where: { $0.name == "DURATION" }).flatMap { duration($0.value) } ?? (allDay ? 86400 : 0))
            guard end >= start else { throw FeedError.invalid }
            let uid = block.first(where: { $0.name == "UID" })?.value ?? "\(start.timeIntervalSince1970)-\(block.first(where: { $0.name == "SUMMARY" })?.value ?? "")"
            let title = unescape(block.first(where: { $0.name == "SUMMARY" })?.value ?? "Scheduled shift")
            var starts = [start]
            if let rule = block.first(where: { $0.name == "RRULE" }) {
                starts = try occurrences(start: start, property: startProp, rule: rule.value, until: upper)
            }
            starts += block.filter { $0.name == "RDATE" }.flatMap { dates($0) }
            let excluded = Set(block.filter { $0.name == "EXDATE" }.flatMap { dates($0) })
            for occurrence in starts where occurrence >= lower && occurrence < upper && !excluded.contains(occurrence) {
                let id = "\(jobID.uuidString)|\(uid)|\(occurrence.timeIntervalSince1970)"
                result[id] = ScheduledShift(id: id, jobID: jobID, title: title, start: occurrence,
                    end: occurrence.addingTimeInterval(end.timeIntervalSince(start)), allDay: allDay)
            }
        }
        // Apply modified/cancelled occurrences after their recurring master.
        for block in blocks {
            guard let recurrence = block.first(where: { $0.name == "RECURRENCE-ID" }), let original = date(recurrence),
                  let uid = block.first(where: { $0.name == "UID" })?.value else { continue }
            let id = "\(jobID.uuidString)|\(uid)|\(original.timeIntervalSince1970)"
            let previous = result.removeValue(forKey: id)
            if block.contains(where: { $0.name == "STATUS" && $0.value == "CANCELLED" }) { continue }
            guard let startProp = block.first(where: { $0.name == "DTSTART" }), let start = date(startProp) else { continue }
            let end = block.first(where: { $0.name == "DTEND" }).flatMap { date($0) } ??
                start.addingTimeInterval(previous.map { $0.end.timeIntervalSince($0.start) } ?? 0)
            if start >= lower && start < upper {
                result[id] = ScheduledShift(id: id, jobID: jobID,
                    title: unescape(block.first(where: { $0.name == "SUMMARY" })?.value ?? previous?.title ?? "Scheduled shift"),
                    start: start, end: end, allDay: startProp.value.count == 8)
            }
        }
        return result.values.sorted { $0.start < $1.start }
    }

    private static func resolveTimeZone(identifier: String?) -> TimeZone {
        guard let identifier = identifier, !identifier.isEmpty else { return .current }
        if let tz = TimeZone(identifier: identifier) { return tz }
        let cleaned = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "\"/"))
        if let tz = TimeZone(identifier: cleaned) { return tz }
        let parts = cleaned.split(separator: "/")
        if parts.count >= 2 {
            let lastTwo = parts.suffix(2).joined(separator: "/")
            if let tz = TimeZone(identifier: lastTwo) { return tz }
        }
        return .current
    }

    static func date(_ property: Property) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = property.value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : resolveTimeZone(identifier: property.parameters["TZID"])
        formatter.dateFormat = property.value.count == 8 ? "yyyyMMdd" :
            (property.value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss")
        formatter.isLenient = false
        return formatter.date(from: property.value)
    }
    private static func dates(_ property: Property) -> [Date] {
        property.value.split(separator: ",").compactMap {
            date(Property(name: property.name, parameters: property.parameters, value: String($0)))
        }
    }
    private static func duration(_ text: String) -> TimeInterval? {
        guard text.hasPrefix("P") else { return nil }
        var number = ""; var seconds: Double = 0
        for char in text.dropFirst() {
            if char.isNumber { number.append(char) } else if char != "T" {
                guard let value = Double(number) else { return nil }
                switch char {
                case "W": seconds += value * 604800
                case "D": seconds += value * 86400
                case "H": seconds += value * 3600
                case "M": seconds += value * 60
                case "S": seconds += value
                default: return nil
                }
                number = ""
            }
        }
        return seconds
    }
    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    private static func occurrences(start: Date, property: Property, rule: String, until upper: Date) throws -> [Date] {
        var fields: [String: String] = [:]
        for item in rule.split(separator: ";") {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        let allowed: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "WKST"]
        guard Set(fields.keys).isSubset(of: allowed), let frequency = fields["FREQ"],
              ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(frequency) else { throw FeedError.unsupportedRecurrence }
        let codes = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let dayCodes = fields["BYDAY"]?.components(separatedBy: ",") ?? []
        guard dayCodes.allSatisfy({ codes[$0] != nil }),
              frequency == "WEEKLY" || dayCodes.isEmpty else { throw FeedError.unsupportedRecurrence }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = property.value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0)! : resolveTimeZone(identifier: property.parameters["TZID"])
        cal.firstWeekday = codes[fields["WKST"] ?? "MO"] ?? 2
        let interval = max(1, Int(fields["INTERVAL"] ?? "1") ?? 1)
        let count = max(1, Int(fields["COUNT"] ?? "10000") ?? 10000)
        let end = fields["UNTIL"].flatMap { date(Property(name: "UNTIL", parameters: property.parameters, value: $0)) } ?? upper
        let weekdays = Set(dayCodes.compactMap { codes[$0] })
        let monthDays = fields["BYMONTHDAY"]?.split(separator: ",").compactMap { Int($0) } ?? []
        guard monthDays.allSatisfy({ (1...31).contains($0) }),
              frequency != "WEEKLY" || monthDays.isEmpty else { throw FeedError.unsupportedRecurrence }
        var values: [Date] = []
        var candidate = start
        var inspected = 0
        while candidate <= end && candidate < upper && values.count < count {
            inspected += 1
            guard inspected <= 100000 else { throw FeedError.unsupportedRecurrence }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: candidate)).day ?? 0
            
            guard let startMonthInterval = cal.dateInterval(of: .month, for: start),
                  let candMonthInterval = cal.dateInterval(of: .month, for: candidate),
                  let startWeekInterval = cal.dateInterval(of: .weekOfYear, for: start),
                  let candWeekInterval = cal.dateInterval(of: .weekOfYear, for: candidate) else { break }
            
            let months = cal.dateComponents([.month], from: startMonthInterval.start, to: candMonthInterval.start).month ?? 0
            let weekdayMatches = weekdays.isEmpty ? cal.component(.weekday, from: candidate) == cal.component(.weekday, from: start) :
                weekdays.contains(cal.component(.weekday, from: candidate))
            let dayMatches = monthDays.isEmpty ? cal.component(.day, from: candidate) == cal.component(.day, from: start) :
                monthDays.contains(cal.component(.day, from: candidate))
            let weeks = (cal.dateComponents([.day], from: startWeekInterval.start, to: candWeekInterval.start).day ?? 0) / 7
            let matches: Bool
            switch frequency {
            case "DAILY": matches = days % interval == 0 && (monthDays.isEmpty || monthDays.contains(cal.component(.day, from: candidate)))
            case "WEEKLY": matches = weeks % interval == 0 && weekdayMatches
            case "MONTHLY": matches = months % interval == 0 && dayMatches
            default: matches = months % 12 == 0 && (months / 12) % interval == 0 && dayMatches
            }
            if matches || candidate == start { values.append(candidate) }
            guard let next = cal.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }
        return values
    }
}

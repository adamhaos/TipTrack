import Foundation

enum TipTrackCSV {
    static let header = "Date,Job,Credit Tips,Cash Tips,Bar Tip Out,Net Cash,Total Earnings,Hours Worked,Hourly Rate,Notes"

    struct Row: Identifiable {
        let id = UUID()
        let date: Date
        let jobName: String
        let creditTip: Double
        let cashTip: Double
        let barTipOut: Double
        let hoursWorked: Double?
        let hourlyRate: Double
        var notes: String = ""
    }

    struct ParseResult {
        let rows: [Row]
        let rejectedRowCount: Int
    }

    static func exportFileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "TipTrack_Export_\(formatter.string(from: date)).csv"
    }

    static func exportText(for shifts: [Shift]) -> String {
        var lines = [header]
        let formatter = csvDateFormatter()

        for shift in shifts {
            let jobName = shift.job?.name ?? "Unassigned"
            let hoursWorkedText: String
            if let hoursWorked = shift.hoursWorked {
                hoursWorkedText = amount(hoursWorked)
            } else {
                hoursWorkedText = ""
            }

            let values = [
                formatter.string(from: shift.date),
                quotedField(jobName),
                amount(shift.creditTip),
                amount(shift.cashTip),
                amount(shift.barTipOut),
                amount(shift.netCash),
                amount(shift.totalEarnings),
                hoursWorkedText,
                amount(shift.hourlyRate),
                quotedField(shift.notes)
            ]
            lines.append(values.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) -> ParseResult {
        let normalizedText = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        var rows: [Row] = []
        var rejectedRowCount = 0

        for rawLine in records(in: normalizedText) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            guard let fields = fields(in: line) else {
                rejectedRowCount += 1
                continue
            }
            if fields.first?.caseInsensitiveCompare("Date") == .orderedSame {
                continue
            }

            guard
                fields.count >= 5,
                let date = parseDate(fields[0]),
                let credit = Double(fields[2].trimmingCharacters(in: .whitespaces)),
                let cash = Double(fields[3].trimmingCharacters(in: .whitespaces)),
                let tipOut = Double(fields[4].trimmingCharacters(in: .whitespaces))
            else {
                rejectedRowCount += 1
                continue
            }

            var hoursWorked: Double?
            if fields.count > 7 {
                let hoursText = fields[7].trimmingCharacters(in: .whitespaces)
                if !hoursText.isEmpty {
                    guard let parsedHours = Double(hoursText), parsedHours.isFinite, parsedHours >= 0 else {
                        rejectedRowCount += 1
                        continue
                    }
                    hoursWorked = parsedHours > 0 ? parsedHours : nil
                }
            }
            let rateText = fields.count > 8 ? fields[8].trimmingCharacters(in: .whitespaces) : ""
            guard let hourlyRate = rateText.isEmpty ? 0 : Double(rateText),
                  [credit, cash, tipOut, hourlyRate].allSatisfy({ $0.isFinite && $0 >= 0 }),
                  (credit + (hoursWorked ?? 0) * hourlyRate + (cash - tipOut)).isFinite else {
                rejectedRowCount += 1
                continue
            }

            rows.append(
                Row(
                    date: date,
                    jobName: fields[1].trimmingCharacters(in: .whitespaces),
                    creditTip: credit,
                    cashTip: cash,
                    barTipOut: tipOut,
                    hoursWorked: hoursWorked,
                    hourlyRate: hourlyRate,
                    notes: fields.count > 9 ? fields[9].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                )
            )
        }

        return ParseResult(rows: rows, rejectedRowCount: rejectedRowCount)
    }

    static func rowsForImport(_ rows: [Row], existingShifts: [Shift]) -> [Row] {
        // Index existing shifts once so large imports aren't rows × shifts.
        let knownFingerprints = Set(existingShifts.compactMap(\.sourceFingerprint))
        var shiftsByMinute: [Int: [Shift]] = [:]
        for shift in existingShifts {
            shiftsByMinute[minuteBucket(shift.date), default: []].append(shift)
        }
        var fingerprints = Set<String>()
        return rows.filter { row in
            let key = fingerprint(row)
            guard fingerprints.insert(key).inserted else { return false }
            if knownFingerprints.contains(key) || knownFingerprints.contains(legacyFingerprint(row)) { return false }
            let minute = minuteBucket(row.date)
            let candidates = (minute - 1...minute + 1).flatMap { shiftsByMinute[$0] ?? [] }
            return !candidates.contains { shift in
                abs(shift.date.timeIntervalSince(row.date)) < 60 &&
                    normalizedJob(shift.job?.name ?? "") == normalizedJob(row.jobName) &&
                    abs(shift.creditTip - row.creditTip) < 0.005 &&
                    abs(shift.cashTip - row.cashTip) < 0.005 &&
                    abs(shift.barTipOut - row.barTipOut) < 0.005 &&
                    abs((shift.hoursWorked ?? 0) - (row.hoursWorked ?? 0)) < 0.005 &&
                    abs(shift.hourlyRate - row.hourlyRate) < 0.005
            }
        }
    }

    private static func minuteBucket(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    /// The format stored on shifts imported before missing hours were encoded as 0.
    private static func legacyFingerprint(_ row: Row) -> String {
        let job = row.jobName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(Int(row.date.timeIntervalSince1970 / 60))|\(job)|\(row.creditTip)|\(row.cashTip)|\(row.barTipOut)|\(row.hoursWorked ?? -1)|\(row.hourlyRate)"
    }

    static func fingerprint(_ row: Row) -> String {
        "\(Int(row.date.timeIntervalSince1970 / 60))|\(normalizedJob(row.jobName))|\(row.creditTip)|\(row.cashTip)|\(row.barTipOut)|\(row.hoursWorked ?? 0)|\(row.hourlyRate)"
    }

    private static func normalizedJob(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty || value == "unassigned" ? "unassigned" : value
    }

    private static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let formatters: [DateFormatter] = [
            csvDateFormatter(),
            makeFormatter(format: "yyyy-MM-dd'T'HH:mm:ss"),
            makeFormatter(format: "yyyy-MM-dd'T'HH:mm:ssZ"),
            makeFormatter(format: "yyyy-MM-dd"),
            makeFormatter(format: "MM/dd/yyyy HH:mm"),
            makeFormatter(format: "MM/dd/yyyy"),
            makeFormatter(format: "yyyy/MM/dd HH:mm"),
            makeFormatter(format: "yyyy/MM/dd")
        ]
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static func makeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static func csvDateFormatter() -> DateFormatter {
        makeFormatter(format: "yyyy-MM-dd HH:mm")
    }

    nonisolated private static func amount(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func quotedField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // Keep newlines inside quoted job names so exported CSV can be imported intact.
    private static func records(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var records: [String] = []
        var record = ""
        var quoted = false
        for character in normalized {
            if character == "\"" { quoted.toggle() }
            if character == "\n" && !quoted {
                records.append(record)
                record = ""
            } else {
                record.append(character)
            }
        }
        if !record.isEmpty { records.append(record) }
        return records
    }

    private static func fields(in line: String) -> [String]? {
        let characters = Array(line)
        var fields: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                let nextIndex = index + 1
                if isInsideQuotes,
                   nextIndex < characters.count,
                   characters[nextIndex] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }

            index += 1
        }

        guard !isInsideQuotes else { return nil }
        fields.append(field)
        return fields
    }
}

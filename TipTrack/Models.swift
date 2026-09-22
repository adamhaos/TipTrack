import Foundation
import SwiftData

struct JobCalendarFeed: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Work Schedule"
    var url: String = ""
    var filter: String = ""
}

enum ShiftLoggingReminderTiming: Int, CaseIterable, Identifiable {
    case hourBefore = -60
    case halfHourBefore = -30
    case quarterHourBefore = -15
    case atEnd = 0
    case quarterHourAfter = 15
    case halfHourAfter = 30
    case hourAfter = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hourBefore: "1 hour before shift ends"
        case .halfHourBefore: "30 minutes before shift ends"
        case .quarterHourBefore: "15 minutes before shift ends"
        case .atEnd: "At shift end"
        case .quarterHourAfter: "15 minutes after shift ends"
        case .halfHourAfter: "30 minutes after shift ends"
        case .hourAfter: "1 hour after shift ends"
        }
    }

    static func fireDate(start: Date, end: Date, offsetMinutes: Int, now: Date) -> Date? {
        let fire = end.addingTimeInterval(Double(offsetMinutes) * 60)
        // A before-end reminder belongs during the shift, and past reminders are skipped.
        guard fire > now, offsetMinutes >= 0 || fire >= start else { return nil }
        return fire
    }

    static func message(jobName: String, offsetMinutes: Int) -> String {
        if offsetMinutes < 0 {
            let remaining = offsetMinutes == -60 ? "1 hour" : "\(-offsetMinutes) minutes"
            return "Your shift at \(jobName) ends in \(remaining). Log your tips and hours in TipTrack."
        }
        return "Your scheduled shift at \(jobName) has ended. Add your tips and hours in TipTrack."
    }
}

// MARK: - Models
@Model
final class Job {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#007AFF"
    var iconName: String = "briefcase.fill"
    var isDefault: Bool = false
    var selectionDays: String = ""
    var receiptPOS: String = "Auto Detect"
    var latitude: Double?
    var longitude: Double?
    var locationRadius: Double = 300
    var calendarURL: String = ""
    var calendarFilter: String = ""
    var additionalCalendarsJSON: String = ""
    var endReminder: Bool = false
    var reminderDelay: Int = 15
    
    @Relationship(deleteRule: .nullify, inverse: \Shift.job)
    var shifts: [Shift]?
    
    init(id: UUID = UUID(), name: String, colorHex: String = "#007AFF", isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isDefault = isDefault
    }
}

@Model
final class Shift {
    var id: UUID = UUID()
    var date: Date = Date()
    var creditTip: Double = 0
    var cashTip: Double = 0
    var barTipOut: Double = 0
    var deletedAt: Date?
    var scheduledEventID: String?
    var hoursWorked: Double?
    var hourlyRate: Double = 0
    var receiptImageName: String?
    var sourceFingerprint: String?
    var notes: String = ""
    
    @Relationship
    var job: Job?
    
    var netCash: Double {
        cashTip - barTipOut
    }
    
    var totalEarnings: Double {
        creditEarnings + netCash
    }

    var basePay: Double {
        (hoursWorked ?? 0) * hourlyRate
    }

    var creditEarnings: Double {
        creditTip + basePay
    }

    var hourlyAverage: Double? {
        guard let hoursWorked, hoursWorked > 0 else { return nil }
        return totalEarnings / hoursWorked
    }
    
    init(
        id: UUID = UUID(),
        date: Date,
        creditTip: Double,
        cashTip: Double,
        barTipOut: Double = 0.0,
        hoursWorked: Double? = nil,
        hourlyRate: Double = 0,
        notes: String = "",
        job: Job? = nil
    ) {
        self.id = id
        self.date = date
        self.creditTip = creditTip
        self.cashTip = cashTip
        self.barTipOut = barTipOut
        self.hoursWorked = hoursWorked
        self.hourlyRate = hourlyRate
        self.notes = notes
        self.job = job
    }
}

extension Job {
    var calendarFeeds: [JobCalendarFeed] {
        get {
            var values = (additionalCalendarsJSON.data(using: .utf8))
                .flatMap { try? JSONDecoder().decode([JobCalendarFeed].self, from: $0) } ?? []
            if !calendarURL.isEmpty && !values.contains(where: { $0.url == calendarURL }) {
                values.insert(JobCalendarFeed(name: "Primary Schedule", url: calendarURL, filter: calendarFilter), at: 0)
            }
            return values
        }
        set {
            let cleaned = newValue.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            additionalCalendarsJSON = (try? String(data: JSONEncoder().encode(cleaned), encoding: .utf8)) ?? ""
            calendarURL = cleaned.first?.url ?? ""
            calendarFilter = cleaned.first?.filter ?? ""
        }
    }
}

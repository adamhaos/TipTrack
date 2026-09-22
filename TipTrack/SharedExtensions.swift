import Foundation
import SwiftUI
import UIKit

extension Notification.Name {
    static let tipTrackIntentRoute = Notification.Name("tipTrackIntentRoute")
}

// MARK: - Shared Helpers
extension Color {
    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

private struct TipTrackColorfulThemeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tipTrackColorful: Bool {
        get { self[TipTrackColorfulThemeKey.self] }
        set { self[TipTrackColorfulThemeKey.self] = newValue }
    }
}

enum TipTrackColorPalette {
    static let rainbow: [Color] = [.pink, .orange, .yellow, .green, .mint, .cyan, .purple]
}

extension Calendar {
    /// Weekday numbers (1 = Sunday) in the order of the person's chosen week start.
    static var orderedWeekdays: [Int] {
        let first = preferredWeek.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static var preferredWeek: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = UserDefaults.standard.object(forKey: FeatureKeys.weekStart) as? Int ?? 2
        return cal
    }
    
    static var preferredWeekRange: [Date] {
        let today = Date()
        guard let weekStart = preferredWeek.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        
        return (0...6).compactMap { dayOffset in
            preferredWeek.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
}

extension Job {
    var selectionDaysSummary: String {
        let days = selectionDays.split(separator: ",").compactMap { Int($0) }
        guard !days.isEmpty else { return "Manual selection" }
        if days.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().compactMap { d -> String? in
            guard d >= 1 && d <= 7 else { return nil }
            return symbols[d - 1]
        }.joined(separator: ", ")
    }
}

enum FeatureKeys {
    static let cardOrder = "dashboard.cardOrder"
    static let monthlyFirst = "dashboard.monthlyFirst"
    static let greeting = "dashboard.greeting"
    static let showMonthly = "dashboard.showMonthly"
    static let showWeekly = "dashboard.showWeekly"
    static let showCalendarStrip = "dashboard.showCalendarStrip"
    static let showLiveActivity = "dashboard.showLiveActivity"
    static let showLogShift = "dashboard.showLogShift"
    static let showSpacer1 = "dashboard.showSpacer1"
    static let showSpacer2 = "dashboard.showSpacer2"
    static let showSpacer3 = "dashboard.showSpacer3"
    static let showSpacer4 = "dashboard.showSpacer4"
    static let validation = "entry.validation"
    static let receipts = "entry.receipts"
    static let automaticBackups = "entry.automaticBackups"
    static let calendarEarnings = "calendar.earnings"
    static let preShiftReminder = "calendar.preShiftReminder"
    static let liveTimer = "liveShift.enabled"
    static let spotlight = "system.spotlight"
    static let onboarding = "system.onboarding"
    static let weekStart = "calendar.weekStart"
    static let appLock = "privacy.appLock"
    static let theme = "appearance.theme"
    static let customAccent = "appearance.customAccent"
    static let duplicateProtection = "entry.duplicateProtection"
    static let hourlyPayEnabled = "entry.hourlyPayEnabled"
    static let shiftNotes = "entry.shiftNotes"
    static let alwaysShowInsightsLabel = "system.alwaysShowInsightsLabel"
    static let hourlyRate = "entry.hourlyRate"
    static let watchShowEarnings = "watch.showEarnings"
    static let watchShowTotals = "watch.showTotals"
    static let watchShowLiveTimer = "watch.showLiveTimer"
    static let headlineMetric = "dashboard.headlineMetric"
}

enum DashboardHeadlineMetric: String, CaseIterable, Identifiable {
    case today
    case earnings
    case hours
    case shifts
    case hourlyAverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today's Earnings"
        case .earnings: "Weekly Earnings"
        case .hours: "Hours Worked"
        case .shifts: "Shifts Logged"
        case .hourlyAverage: "Average per Hour"
        }
    }
}

extension DashboardCardID {
    var title: String {
        switch self {
        case .greeting: "Greeting"
        case .calendar: "7-Day Calendar"
        case .monthly: "Monthly Stats"
        case .weekly: "Weekly Totals"
        case .liveActivity: "Live Activity"
        case .logShift: "Log Shift"
        case .spacer1: "Spacer 1"
        case .spacer2: "Spacer 2"
        case .spacer3: "Spacer 3"
        case .spacer4: "Spacer 4"
        }
    }

    var description: String {
        switch self {
        case .greeting: "Shows a time-of-day greeting and your next scheduled shift."
        case .calendar: "Shows a compact Monday–Sunday overview."
        case .monthly: "Shows your totals and trends for the selected month."
        case .weekly: "Shows credit and cash totals for the current week."
        case .liveActivity: "Starts or ends a timed shift and its Live Activity."
        case .logShift: "Opens the form for logging shift income."
        case .spacer1, .spacer2, .spacer4: "Adds 10 points of white space."
        case .spacer3: "Adds 5 points of white space."
        }
    }

    var iconName: String {
        switch self {
        case .greeting: "banknote.fill"
        case .calendar: "calendar"
        case .monthly: "chart.bar.xaxis"
        case .weekly: "coloncurrencysign.square"
        case .liveActivity: "timer"
        case .logShift: "plus.circle.fill"
        case .spacer1, .spacer2, .spacer3, .spacer4: "rectangle.compress.vertical"
        }
    }

    var colorfulColor: Color {
        switch self {
        case .greeting: .pink
        case .calendar: .cyan
        case .monthly: .orange
        case .weekly: .purple
        case .liveActivity: .green
        case .logShift: .blue
        case .spacer1: .mint
        case .spacer2: .indigo
        case .spacer3: .yellow
        case .spacer4: .red
        }
    }


}

enum TipTrackTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case neutral = "Neutral"
    case colorful = "Colorful"
    case ocean = "Ocean"
    case sunset = "Sunset"
    case forest = "Forest"
    case custom = "Custom"
    case highContrast = "High Contrast"
    case jobColor = "Job Color"
    var id: String { rawValue }
}

extension UIColor {
    var tipTrackHex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: nil) else { return "#007AFF" }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

private struct SaveErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("Couldn't Save Changes", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: { Text(message ?? "") }
    }
}

extension View {
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        modifier(SaveErrorAlert(message: message))
    }
}

/// A switch that flips on the first touch, including very quick taps, and when
/// the row's label is tapped. Matches the system switch's size, tint and haptic.
struct InstantSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        InstantSwitchRow(configuration: configuration)
    }
}

private struct InstantSwitchRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            InstantSwitchTrack(isOn: configuration.isOn)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                configuration.isOn.toggle()
            }
        }
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        // VoiceOver and Switch Control see a standard switch.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

private struct InstantSwitchTrack: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(uiColor: .systemFill)))
            .frame(width: 64, height: 28)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(.white)
                    .frame(width: 38, height: 24)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .padding(2)
            }
    }
}

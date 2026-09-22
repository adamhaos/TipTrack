import AppIntents
import Foundation

enum TipTrackControlDestination: String, AppEnum {
    case log, history, calendar, start, stop

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "TipTrack Action")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .log: "Log Shift",
        .history: "View History",
        .calendar: "Shift Calendar",
        .start: "Start Shift",
        .stop: "End Shift"
    ]
}

struct TipTrackControlActionIntent: OpenIntent {
    static let isDiscoverable = false
    static let openAppWhenRun = true
    static let title: LocalizedStringResource = "Open TipTrack3r"
    @Parameter(title: "Action") var target: TipTrackControlDestination

    init() { target = .log }
    init(target: TipTrackControlDestination) { self.target = target }

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.atm.TipTrack")?.set(target.rawValue, forKey: "tiptrack.pendingRoute")
        NotificationCenter.default.post(name: Notification.Name("tipTrackIntentRoute"), object: nil)
        return .result()
    }
}

import AppIntents
import SwiftUI
import WidgetKit

struct TipTrackLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TipTrackControl.log") {
            ControlWidgetButton(action: TipTrackControlActionIntent(target: .log)) {
                Label("Log Shift", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Log Shift")
        .description("Open TipTrack directly to shift entry.")
    }
}

struct TipTrackHistoryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TipTrackControl.history") {
            ControlWidgetButton(action: TipTrackControlActionIntent(target: .history)) {
                Label("Shift History", systemImage: "clock.arrow.circlepath")
            }
        }
        .displayName("Shift History")
        .description("Open your TipTrack shift history.")
    }
}

struct TipTrackCalendarControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TipTrackControl.calendar") {
            ControlWidgetButton(action: TipTrackControlActionIntent(target: .calendar)) {
                Label("Shift Calendar", systemImage: "calendar")
            }
        }
        .displayName("Shift Calendar")
        .description("Open your TipTrack shift calendar.")
    }
}

struct TipTrackStartShiftControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TipTrackControl.start") {
            ControlWidgetButton(action: TipTrackControlActionIntent(target: .start)) {
                Label("Start Shift", systemImage: "timer")
            }
        }
        .displayName("Start Shift")
        .description("Open TipTrack and start the live shift timer.")
    }
}

struct TipTrackEndShiftControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TipTrackControl.stop") {
            ControlWidgetButton(action: TipTrackControlActionIntent(target: .stop)) {
                Label("End Shift", systemImage: "stop.circle.fill")
            }
        }
        .displayName("End Shift")
        .description("Open TipTrack and end the live shift timer.")
    }
}

// Kept under the original kind and parameter name so controls placed before
// the split into dedicated controls keep working after an update.
struct TipTrackControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "TipTrack Control"
    @Parameter(title: "Action", default: .log) var destination: TipTrackControlDestination
}

struct TipTrackLegacyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "TipTrackControl", intent: TipTrackControlConfiguration.self) { configuration in
            ControlWidgetButton(action: TipTrackControlActionIntent(target: configuration.destination)) {
                Label(configuration.destination.controlTitle, systemImage: configuration.destination.controlIcon)
            }
        }
        .displayName("TipTrack")
        .description("Log, start, end, or open a TipTrack screen.")
    }
}

private extension TipTrackControlDestination {
    var controlTitle: LocalizedStringResource {
        switch self {
        case .log: "Log Shift"
        case .history: "Shift History"
        case .calendar: "Shift Calendar"
        case .start: "Start Shift"
        case .stop: "End Shift"
        }
    }

    var controlIcon: String {
        switch self {
        case .log: "plus.circle.fill"
        case .history: "clock.arrow.circlepath"
        case .calendar: "calendar"
        case .start: "timer"
        case .stop: "stop.circle.fill"
        }
    }
}

@main
struct TipTrackControlsBundle: WidgetBundle {
    var body: some Widget {
        TipTrackLogControl()
        TipTrackHistoryControl()
        TipTrackCalendarControl()
        TipTrackStartShiftControl()
        TipTrackEndShiftControl()
        TipTrackLegacyControl()
    }
}

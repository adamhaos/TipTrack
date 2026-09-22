import Foundation
import WidgetKit

struct WidgetShiftSnapshot: Codable, Hashable {
    let id: UUID
    let date: Date
    let creditTip: Double
    let cashTip: Double
    let barTipOut: Double
    let hoursWorked: Double?
    let hourlyRate: Double?
    let jobID: UUID?
    let scheduledEventID: String?

    init(shift: Shift) {
        id = shift.id
        date = shift.date
        creditTip = shift.creditTip
        cashTip = shift.cashTip
        barTipOut = shift.barTipOut
        hoursWorked = shift.hoursWorked
        hourlyRate = shift.hourlyRate
        jobID = shift.job?.id
        scheduledEventID = shift.scheduledEventID
    }
}

private struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let shifts: [WidgetShiftSnapshot]
}

enum WidgetSnapshotWriter {
    private static let appGroup = "group.atm.TipTrack"
    private static let snapshotKey = "tiptrack.widget.snapshot"
    private static let widgetKind = "TipTrackSummaryWidget"

    static func publish(shifts: [Shift]) {
        var snapshots: [WidgetShiftSnapshot] = []
        snapshots.reserveCapacity(shifts.count)
        for shift in shifts {
            snapshots.append(WidgetShiftSnapshot(shift: shift))
        }
        publish(snapshotShifts: snapshots)
    }

    static func publish(snapshotShifts: [WidgetShiftSnapshot]) {
        let hidden = UserDefaults.standard.bool(forKey: "privacyEnabled")
        let snapshot = WidgetSnapshot(generatedAt: Date(), shifts: hidden ? [] : snapshotShifts)
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: appGroup) else { return }

        defaults.set(UserDefaults.standard.object(forKey: FeatureKeys.weekStart) as? Int ?? 2,
            forKey: FeatureKeys.weekStart)
        defaults.set(hidden, forKey: "privacyEnabled")
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

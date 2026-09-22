import ActivityKit
import Foundation
import Observation

nonisolated struct LiveShiftAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var startedAt: Date
        var jobName: String
        var jobColorHex: String?
        var jobIcon: String?
    }
    var shiftID: UUID
}

struct SharedLiveShift: Codable, Equatable {
    var id: UUID
    var startedAt: Date
    var jobID: UUID?
    var jobName: String
}

@MainActor @Observable
final class LiveShiftManager {
    static let shared = LiveShiftManager()
    private let defaults = UserDefaults(suiteName: "group.atm.TipTrack")
    private let key = "tiptrack.liveShift"
    var current: SharedLiveShift?

    private init() {
        if let data = defaults?.data(forKey: key) {
            current = try? JSONDecoder().decode(SharedLiveShift.self, from: data)
        }
    }

    func start(job: Job?, id: UUID = UUID(), startedAt: Date = Date()) async {
        guard current == nil else { return }
        let state = SharedLiveShift(id: id, startedAt: startedAt, jobID: job?.id,
            jobName: job?.name ?? "Work Shift")
        current = state
        persist()
        WatchSyncService.shared.publish()
        guard UserDefaults.standard.bool(forKey: FeatureKeys.liveTimer),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = LiveShiftAttributes(shiftID: state.id)
        let content = ActivityContent(state: LiveShiftAttributes.ContentState(startedAt: state.startedAt,
            jobName: state.jobName, jobColorHex: job?.colorHex, jobIcon: job?.iconName), staleDate: nil)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    @discardableResult
    func stop() async -> SharedLiveShift? {
        let stopped = current
        current = nil
        defaults?.removeObject(forKey: key)
        WatchSyncService.shared.publish()
        for activity in Activity<LiveShiftAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return stopped
    }

    func reloadSharedState() {
        guard let data = defaults?.data(forKey: key) else { current = nil; return }
        current = try? JSONDecoder().decode(SharedLiveShift.self, from: data)
    }

    private func persist() {
        guard let current, let data = try? JSONEncoder().encode(current) else { return }
        defaults?.set(data, forKey: key)
    }
}

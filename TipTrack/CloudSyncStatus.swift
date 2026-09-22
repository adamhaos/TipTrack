import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class CloudSyncStatus: NSObject {
    static let shared = CloudSyncStatus()
    var enabledAtLaunch = false
    var activity = "Waiting for iCloud sync activity."
    var lastUpload: Date?
    var lastDownload: Date?

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(receiveEvent(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification, object: nil)
    }

    @objc nonisolated private func receiveEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return }
        let type = event.type.rawValue
        let end = event.endDate
        let succeeded = event.succeeded
        let error = event.error?.localizedDescription
        Task { @MainActor in
            if let error {
                self.activity = "Sync failed: \(error)"
            } else if end == nil {
                self.activity = type == NSPersistentCloudKitContainer.EventType.export.rawValue
                    ? "Uploading changes…" : "Connecting to iCloud…"
            } else if succeeded {
                if type == NSPersistentCloudKitContainer.EventType.export.rawValue {
                    self.lastUpload = end
                    self.activity = "Last upload completed successfully."
                } else if type == NSPersistentCloudKitContainer.EventType.import.rawValue {
                    self.lastDownload = end
                    self.activity = "Last download completed successfully."
                } else {
                    self.activity = "Connected. Waiting for changes to sync."
                }
            }
        }
    }
}

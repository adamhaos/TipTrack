import Foundation
import CloudKit

// Compile alongside CloudSyncStatus. Builds the errors CloudKit sends for a
// "Failed to modify some records" partial failure and checks the explanation.
@main
struct CloudSyncChecks {
    static func partial(_ items: [(CKError.Code, String)]) -> NSError {
        var byID: [AnyHashable: Error] = [:]
        for (index, item) in items.enumerated() {
            byID[CKRecord.ID(recordName: "record-\(index)")] = NSError(domain: CKErrorDomain,
                code: item.0.rawValue, userInfo: [NSLocalizedDescriptionKey: item.1])
        }
        return NSError(domain: CKErrorDomain, code: CKError.Code.partialFailure.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Failed to modify some records",
            CKPartialErrorsByItemIDKey: byID,
        ])
    }

    static func main() {
        let quota = CloudSyncStatus.describe(partial([
            (.batchRequestFailed, "Atomic failure"), (.quotaExceeded, "Quota exceeded"),
            (.batchRequestFailed, "Atomic failure"),
        ]))
        precondition(quota.summary == "Your iCloud storage is full.")
        precondition(!quota.retriesAutomatically)
        precondition(quota.detail.contains("quotaExceeded"))
        precondition(!quota.detail.contains("batchRequestFailed"))

        let schema = CloudSyncStatus.describe(partial([(.invalidArguments,
            "Cannot create or modify field 'CD_notes' in record 'CD_Shift' in production schema")]))
        precondition(schema.summary.contains("needs an update"))
        precondition(schema.detail.contains("Production"))
        precondition(schema.detail.contains("CD_notes"))

        // A real cause wins over a transient one in the same batch.
        let mixed = CloudSyncStatus.describe(partial([(.serverRecordChanged, "changed"), (.quotaExceeded, "full")]))
        precondition(mixed.summary == "Your iCloud storage is full.")

        let conflict = CloudSyncStatus.describe(partial([(.serverRecordChanged, "record changed")]))
        precondition(conflict.retriesAutomatically)

        // Wrapped one level down, as Core Data sometimes reports it.
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: partial([(.notAuthenticated, "No account")]),
        ])
        precondition(CloudSyncStatus.describe(wrapped).summary.contains("signed in"))

        let plain = CloudSyncStatus.describe(NSError(domain: "Other", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Something odd"]))
        precondition(plain.summary == "iCloud couldn't save some changes.")
        precondition(plain.detail.contains("Something odd"))
        print("Cloud sync checks passed.")
    }
}

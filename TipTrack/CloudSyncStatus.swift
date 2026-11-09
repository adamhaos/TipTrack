import Foundation
import CoreData
import CloudKit
import Observation

/// Why an iCloud transfer failed, in plain words plus the raw CloudKit detail
/// needed to diagnose it.
struct CloudSyncProblem: Equatable {
    /// One line for the Sync screen.
    let summary: String
    /// What the person (or the developer) can do about it.
    let advice: String
    /// True when iCloud retries on its own and nothing needs doing.
    let retriesAutomatically: Bool
    /// The CloudKit codes and server messages, for the copied sync report.
    let detail: String
}

/// The state of iCloud database sync for this app session, kept per transfer
/// direction so a later success clears only the failure it actually fixes.
@MainActor
@Observable
final class CloudSyncStatus: NSObject {
    enum Direction: String, CaseIterable {
        case setup = "Setup", download = "Download", upload = "Upload"
    }

    enum Outcome: Equatable {
        case never
        case running(since: Date)
        case succeeded(at: Date)
        case failed(CloudSyncProblem, at: Date)
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let direction: Direction
        let text: String
    }

    static let shared = CloudSyncStatus()
    nonisolated static let containerID = "iCloud.atm.TipTrack"
    var enabledAtLaunch = false
    private(set) var outcomes: [Direction: Outcome] = [:]
    /// The last successful upload and download, kept even while a later one fails.
    private(set) var lastUpload = UserDefaults.standard.object(forKey: "cloudSync.lastUpload") as? Date {
        didSet { UserDefaults.standard.set(lastUpload, forKey: "cloudSync.lastUpload") }
    }
    private(set) var lastDownload = UserDefaults.standard.object(forKey: "cloudSync.lastDownload") as? Date {
        didSet { UserDefaults.standard.set(lastDownload, forKey: "cloudSync.lastDownload") }
    }
    /// True once a transfer has succeeded in this app session.
    private(set) var transferredThisSession = false
    private(set) var log: [LogEntry] = []

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(receiveEvent(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification, object: nil)
    }

    func outcome(_ direction: Direction) -> Outcome { outcomes[direction] ?? .never }

    /// The failure that still stands (one not cleared by a later success in the
    /// same direction), most serious first.
    var standingProblem: (direction: Direction, problem: CloudSyncProblem, at: Date)? {
        let failures = Direction.allCases.compactMap { direction -> (Direction, CloudSyncProblem, Date)? in
            if case let .failed(problem, date) = outcome(direction) { return (direction, problem, date) }
            return nil
        }
        return failures.first { !$0.1.retriesAutomatically } ?? failures.first
    }

    /// One line describing sync right now.
    var message: String {
        if let failure = standingProblem {
            return "\(failure.direction.rawValue) failed: \(failure.problem.summary)"
        }
        if case .running = outcome(.upload) { return "Uploading changes…" }
        if case .running = outcome(.download) { return "Downloading changes…" }
        if case .running = outcome(.setup) { return "Connecting to iCloud…" }
        if transferredThisSession { return "Last transfer completed successfully." }
        if case .succeeded = outcome(.setup) { return "Connected. Waiting for changes to sync." }
        return "Waiting for iCloud sync activity."
    }

    @objc nonisolated private func receiveEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else { return }
        let direction: Direction = switch event.type {
        case .export: .upload
        case .import: .download
        default: .setup
        }
        let start = event.startDate
        let end = event.endDate
        let succeeded = event.succeeded
        let problem = event.error.map { Self.describe($0 as NSError) }
        Task { @MainActor in
            self.record(direction: direction, start: start, end: end, succeeded: succeeded, problem: problem)
        }
    }

    private func record(direction: Direction, start: Date, end: Date?, succeeded: Bool, problem: CloudSyncProblem?) {
        guard let end else {
            // A transfer starting doesn't hide a failure that is still unresolved.
            if case .failed = outcome(direction) { return }
            outcomes[direction] = .running(since: start)
            return
        }
        if let problem {
            outcomes[direction] = .failed(problem, at: end)
            append(direction, "Failed. \(problem.detail)", at: end)
        } else if succeeded {
            outcomes[direction] = .succeeded(at: end)
            if direction == .upload { lastUpload = end; transferredThisSession = true }
            if direction == .download { lastDownload = end; transferredThisSession = true }
            append(direction, "Succeeded.", at: end)
        } else {
            let unknown = CloudSyncProblem(summary: "iCloud didn't finish the transfer.",
                advice: "TipTrack will try again. Your data on this device is kept.",
                retriesAutomatically: true, detail: "Event ended without success and without an error.")
            outcomes[direction] = .failed(unknown, at: end)
            append(direction, "Failed. \(unknown.detail)", at: end)
        }
    }

    private func append(_ direction: Direction, _ text: String, at date: Date) {
        log.append(LogEntry(date: date, direction: direction, text: text))
        if log.count > 30 { log.removeFirst(log.count - 30) }
    }

    // MARK: - Error interpretation

    /// Turns a CloudKit error, including the per-record errors inside a
    /// "Failed to modify some records" partial failure, into a plain explanation.
    nonisolated static func describe(_ error: NSError) -> CloudSyncProblem {
        let errors = cloudKitErrors(in: error)
        // In a partial failure, records that failed only because their batch was
        // rejected say nothing about the cause; the other errors do.
        let causes = errors.filter { $0.code != .batchRequestFailed && $0.code != .partialFailure }
        let detail = detailText(top: error, causes: causes)
        guard let main = causes.first(where: { !isTransient($0.code) }) ?? causes.first else {
            return CloudSyncProblem(summary: "iCloud couldn't save some changes.",
                advice: "Your data on this device is kept. If this keeps happening, copy the sync report and send it to the developer.",
                retriesAutomatically: false, detail: detail)
        }
        let message = main.localizedDescription.lowercased()
        let mentionsSchema = message.contains("schema") || message.contains("field") || message.contains("record type")
        if [.invalidArguments, .unknownItem, .serverRejectedRequest].contains(main.code) && mentionsSchema {
            return CloudSyncProblem(summary: "TipTrack needs an update to keep syncing.",
                advice: "Your data on this device is kept and uploads once the update is out.",
                retriesAutomatically: false,
                detail: detail + "\nDeveloper: deploy the CloudKit schema to Production in CloudKit Console.")
        }
        switch main.code {
        case .quotaExceeded:
            return CloudSyncProblem(summary: "Your iCloud storage is full.",
                advice: "Free up space or upgrade iCloud storage in iOS Settings > your name > iCloud. Shifts saved here stay on this device and upload once there is room.",
                retriesAutomatically: false, detail: detail)
        case .notAuthenticated:
            return CloudSyncProblem(summary: "This device isn't signed in to iCloud.",
                advice: "Sign in to iCloud in iOS Settings, then make sure TipTrack is allowed under Settings > your name > iCloud.",
                retriesAutomatically: false, detail: detail)
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .serverResponseLost:
            return CloudSyncProblem(summary: "iCloud couldn't be reached.",
                advice: "TipTrack retries on its own once the connection is back.",
                retriesAutomatically: true, detail: detail)
        case .serverRecordChanged:
            return CloudSyncProblem(summary: "Another device changed the same item at the same time.",
                advice: "TipTrack merges the change and retries on its own. If this stays for more than a few minutes, close and reopen TipTrack.",
                retriesAutomatically: true, detail: detail)
        case .accountTemporarilyUnavailable:
            return CloudSyncProblem(summary: "Your iCloud account needs attention.",
                advice: "Open iOS Settings > your name and finish any sign-in or terms prompt.",
                retriesAutomatically: false, detail: detail)
        case .zoneNotFound, .userDeletedZone:
            return CloudSyncProblem(summary: "TipTrack's data in iCloud is missing or was removed.",
                advice: "TipTrack normally uploads this device's data again on its own. Keep the app open for a minute; if this stays, copy the sync report.",
                retriesAutomatically: true, detail: detail)
        case .limitExceeded:
            return CloudSyncProblem(summary: "A change was too large to upload in one go.",
                advice: "TipTrack splits it and retries on its own.",
                retriesAutomatically: true, detail: detail)
        case .permissionFailure, .missingEntitlement, .badContainer:
            return CloudSyncProblem(summary: "This copy of TipTrack can't use iCloud.",
                advice: "Your data on this device is kept. Copy the sync report and send it to the developer; don't delete the app, since shifts that haven't uploaded would be lost.",
                retriesAutomatically: false, detail: detail)
        default:
            return CloudSyncProblem(summary: "iCloud couldn't save some changes.",
                advice: "Your data on this device is kept. If this keeps happening, copy the sync report and send it to the developer.",
                retriesAutomatically: false, detail: detail)
        }
    }

    nonisolated private static func isTransient(_ code: CKError.Code) -> Bool {
        [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
         .serverResponseLost, .serverRecordChanged, .limitExceeded].contains(code)
    }

    /// Every CloudKit error in the chain: the error itself, its underlying errors,
    /// and each per-record error of a partial failure.
    nonisolated private static func cloudKitErrors(in error: NSError, depth: Int = 0) -> [CKError] {
        guard depth < 4 else { return [] }
        var found: [CKError] = []
        if error.domain == CKErrorDomain {
            found.append(CKError(_nsError: error))
        }
        if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for item in partial.values {
                found += cloudKitErrors(in: item as NSError, depth: depth + 1)
            }
        }
        for underlying in error.underlyingErrors {
            found += cloudKitErrors(in: underlying as NSError, depth: depth + 1)
        }
        return found
    }

    nonisolated private static func detailText(top: NSError, causes: [CKError]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for cause in causes {
            var line = "CKError \(cause.code.rawValue) \(name(of: cause.code)): \(cause.localizedDescription)"
            if let wait = cause.retryAfterSeconds { line += " (retry after \(Int(wait))s)" }
            if counts[line] == nil { order.append(line) }
            counts[line, default: 0] += 1
        }
        var lines = ["\(top.domain) \(top.code): \(top.localizedDescription)"]
        lines += order.prefix(5).map { counts[$0, default: 1] > 1 ? "\($0) (×\(counts[$0]!))" : $0 }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func name(of code: CKError.Code) -> String {
        switch code {
        case .quotaExceeded: "quotaExceeded"
        case .notAuthenticated: "notAuthenticated"
        case .networkUnavailable: "networkUnavailable"
        case .networkFailure: "networkFailure"
        case .serviceUnavailable: "serviceUnavailable"
        case .requestRateLimited: "requestRateLimited"
        case .zoneBusy: "zoneBusy"
        case .serverResponseLost: "serverResponseLost"
        case .serverRecordChanged: "serverRecordChanged"
        case .accountTemporarilyUnavailable: "accountTemporarilyUnavailable"
        case .zoneNotFound: "zoneNotFound"
        case .userDeletedZone: "userDeletedZone"
        case .invalidArguments: "invalidArguments"
        case .unknownItem: "unknownItem"
        case .serverRejectedRequest: "serverRejectedRequest"
        case .limitExceeded: "limitExceeded"
        case .permissionFailure: "permissionFailure"
        case .missingEntitlement: "missingEntitlement"
        case .badContainer: "badContainer"
        case .constraintViolation: "constraintViolation"
        case .referenceViolation: "referenceViolation"
        case .assetFileNotFound: "assetFileNotFound"
        case .incompatibleVersion: "incompatibleVersion"
        default: "code"
        }
    }

    // MARK: - Report

    /// Which CloudKit database this install talks to. Builds installed from Xcode
    /// use the Development database and TestFlight/App Store builds use
    /// Production; the two never see each other's data.
    nonisolated static var databaseEnvironment: String {
        if Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil {
            return "Development (installed from Xcode)"
        }
        return "Production (TestFlight or App Store)"
    }

    /// Plain-text report for the "Copy Sync Report" button.
    func report(osVersion: String, device: String, account: String, counts: String?) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var lines = [
            "TipTrack \(version) (\(build)) sync report, \(Date().formatted(date: .abbreviated, time: .standard))",
            "Device: \(device), OS \(osVersion)",
            "Container: \(Self.containerID), database: \(Self.databaseEnvironment)",
            "iCloud account: \(account)",
            "Sync on at launch: \(enabledAtLaunch ? "yes" : "no")",
            "Status: \(message)",
        ]
        if let counts { lines.append("On this device: \(counts)") }
        let stamp = Date.FormatStyle(date: .abbreviated, time: .standard)
        for direction in Direction.allCases {
            let text: String = switch outcome(direction) {
            case .never: "not yet this session"
            case let .running(since): "running since \(since.formatted(stamp))"
            case let .succeeded(at): "succeeded \(at.formatted(stamp))"
            case let .failed(problem, at): "failed \(at.formatted(stamp)): \(problem.summary)"
            }
            lines.append("\(direction.rawValue): \(text)")
        }
        if !log.isEmpty {
            lines.append("")
            lines.append("Recent events:")
            for entry in log.suffix(15) {
                lines.append("\(entry.date.formatted(stamp)) \(entry.direction.rawValue): \(entry.text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

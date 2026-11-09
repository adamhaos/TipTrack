import SwiftUI
import SwiftData
import CloudKit

struct PrivacySettingsView: View {
    @Bindable private var privacy = PrivacyManager.shared
    @AppStorage(FeatureKeys.appLock) private var appLock = false
    @AppStorage(FeatureKeys.spotlight) private var spotlight = true

    var body: some View {
        Form {
            Section {
                Toggle("Require Face ID to Open TipTrack", isOn: $appLock)
            } header: {
                Text("Entire App")
            } footer: {
                Text("Asks for Face ID or your passcode each time you return.")
            }
            Section {
                Toggle("Hide Earnings Until Face ID", isOn: Binding(
                    get: { privacy.enabled },
                    set: { value in Task { await privacy.setEnabled(value) } }
                )).disabled(privacy.authenticating)
                if let message = privacy.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Earnings Only") }
            footer: { Text("Amounts stay hidden, in the app and in widgets, until you unlock them.") }
            Section {
                Toggle("Show in Spotlight Search", isOn: $spotlight)
            } header: { Text("Search") }
            footer: { Text("Lets iPhone search find your jobs and shifts. Stays on this device.") }
        }
        .navigationTitle("Privacy")
    }
}

struct ICloudSyncSection: View {
    @Environment(\.modelContext) private var context
    @AppStorage("cloudSyncEnabled") private var cloudSync = true
    @State private var cloudStatus = "Checking iCloud account…"
    @State private var checkingSync = false
    @State private var saveStatus: String?
    @State private var deviceCounts: (shifts: Int, jobs: Int, scheduleLinks: Int)?
    @State private var copiedReport = false
    private var sync: CloudSyncStatus { .shared }

    private var countsText: String? {
        deviceCounts.map { "\($0.shifts) shifts · \($0.jobs) jobs · \($0.scheduleLinks) schedule links" }
    }

    @ViewBuilder private var syncStatusRows: some View {
        let problem = sync.standingProblem?.problem
        let icon: (name: String, color: Color) = switch problem?.retriesAutomatically {
        case nil: ("checkmark.icloud", .secondary)
        case true?: ("arrow.clockwise.icloud", .orange)
        case false?: ("exclamationmark.icloud", .red)
        }
        Label {
            Text(sync.message)
        } icon: {
            Image(systemName: icon.name).foregroundStyle(icon.color)
        }
        .font(.caption)
        if let problem {
            Text(problem.advice).font(.caption).foregroundStyle(.secondary)
        }
        LabeledContent("Last upload",
            value: sync.lastUpload?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet this session").font(.caption)
        LabeledContent("Last download",
            value: sync.lastDownload?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet this session").font(.caption)
    }

    var body: some View {
        Section {
            Toggle("iCloud Synchronization", isOn: $cloudSync)
            Text(cloudStatus).font(.caption).foregroundStyle(.secondary)
            if sync.enabledAtLaunch {
                syncStatusRows
            } else {
                Text("Sync is off for this app session.").font(.caption).foregroundStyle(.secondary)
            }
            if sync.enabledAtLaunch != cloudSync { Text("Close and reopen TipTrack to apply this change.").font(.caption).foregroundStyle(.orange) }
            Button(checkingSync ? "Checking…" : "Save & Check Sync") {
                Task {
                    checkingSync = true
                    defer { checkingSync = false }
                    do {
                        try context.save()
                        saveStatus = "Local changes saved. iCloud transfers run automatically; this check does not force a download."
                    } catch {
                        saveStatus = "Could not save changes: \(error.localizedDescription)"
                    }
                    countRecords()
                    await updateCloudStatus()
                }
            }.disabled(checkingSync)
            if let saveStatus { Text(saveStatus).font(.caption).foregroundStyle(.secondary) }
            if let countsText {
                LabeledContent("On this device", value: countsText).font(.caption)
            }
            LabeledContent("iCloud database", value: CloudSyncStatus.databaseEnvironment).font(.caption)
            Button(copiedReport ? "Sync Report Copied" : "Copy Sync Report") {
                UIPasteboard.general.string = sync.report(osVersion: UIDevice.current.systemVersion,
                    device: UIDevice.current.model, counts: countsText)
                copiedReport = true
            }
        } header: { Text("iCloud Sync") }
        footer: { Text("Syncs your shifts, jobs (with their schedule links, colors and reminders), app settings and daily reminder times through your private iCloud account. Face ID, hidden earnings, Spotlight, receipt photos and turning reminders on stay on each device. To check sync, compare the counts and iCloud database above on both devices.") }
        .task {
            countRecords()
            await updateCloudStatus()
        }
        .onChange(of: sync.lastDownload) { countRecords() }
    }

    private func countRecords() {
        let shifts = (try? context.fetchCount(FetchDescriptor<Shift>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
        let jobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        deviceCounts = (shifts, jobs.count, jobs.reduce(0) { $0 + $1.calendarFeeds.count })
    }

    private func updateCloudStatus() async {
        do {
            let status = try await CKContainer(identifier: "iCloud.atm.TipTrack").accountStatus()
            switch status {
            case .available: cloudStatus = "Signed in to iCloud. Upload and download activity appears below."
            case .noAccount: cloudStatus = "Sign in to iCloud in iOS Settings to sync."
            case .restricted: cloudStatus = "iCloud access is restricted on this device."
            default: cloudStatus = "iCloud is temporarily unavailable. Your local data is retained."
            }
        } catch {
            cloudStatus = "iCloud check failed: \(error.localizedDescription)"
        }
    }
}

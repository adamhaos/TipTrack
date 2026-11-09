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
    @State private var deviceCounts: (shifts: Int, jobs: Int, scheduleLinks: Int)?
    @State private var copiedReport = false
    private var sync: CloudSyncStatus { .shared }

    private var countsText: String? {
        deviceCounts.map { "\($0.shifts) shifts · \($0.jobs) jobs · \($0.scheduleLinks) schedule links" }
    }

    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    @ViewBuilder private var syncStatusRows: some View {
        let problem = sync.standingProblem?.problem
        let icon: (name: String, color: Color) = switch problem?.retriesAutomatically {
        case true?: ("arrow.clockwise.icloud", .orange)
        case false?: ("exclamationmark.icloud", .red)
        case nil: sync.transferredThisSession ? ("checkmark.icloud", .green) : ("icloud", .secondary)
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
    }

    var body: some View {
        Section {
            Toggle("iCloud Sync", isOn: $cloudSync)
            Text(cloudStatus).font(.caption).foregroundStyle(.secondary)
            if sync.enabledAtLaunch {
                syncStatusRows
            } else {
                Text("Sync is off for this app session.").font(.caption).foregroundStyle(.secondary)
            }
            if sync.enabledAtLaunch != cloudSync {
                Text(sync.enabledAtLaunch ? "Sync is still on. Close and reopen TipTrack to turn it off."
                    : "Sync is still off. Close and reopen TipTrack to turn it on.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button(checkingSync ? "Checking…" : "Refresh Status") {
                Task {
                    checkingSync = true
                    defer { checkingSync = false }
                    // Saving hands any pending edits to iCloud sync.
                    try? context.save()
                    countRecords()
                    await updateCloudStatus()
                }
            }.disabled(checkingSync)
            DisclosureGroup("Sync Details") {
                LabeledContent("Last upload", value: sync.lastUpload?.formatted(Self.dateStyle) ?? "Never")
                LabeledContent("Last download", value: sync.lastDownload?.formatted(Self.dateStyle) ?? "Never")
                if let countsText {
                    LabeledContent("On this device", value: countsText)
                }
                LabeledContent("iCloud database", value: CloudSyncStatus.databaseEnvironment)
                Button(copiedReport ? "Sync Report Copied" : "Copy Sync Report") {
                    UIPasteboard.general.string = sync.report(osVersion: UIDevice.current.systemVersion,
                        device: UIDevice.current.model, account: cloudStatus, counts: countsText)
                    copiedReport = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedReport = false
                    }
                }
            }
            .font(.caption)
        } header: { Text("iCloud Sync") }
        footer: { Text("Syncs shifts, jobs, schedule links, settings and reminder times through your iCloud account. Face ID, hidden earnings, Spotlight and receipt photos stay on each device. Both devices need the same Apple Account.") }
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
            let status = try await CKContainer(identifier: CloudSyncStatus.containerID).accountStatus()
            switch status {
            case .available: cloudStatus = "Signed in to iCloud."
            case .noAccount: cloudStatus = "Sign in to iCloud in iOS Settings to sync."
            case .restricted: cloudStatus = "iCloud access is restricted on this device."
            default: cloudStatus = "iCloud is temporarily unavailable. Your local data is retained."
            }
        } catch {
            cloudStatus = "iCloud check failed: \(error.localizedDescription)"
        }
    }
}

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
    private var sync: CloudSyncStatus { .shared }

    var body: some View {
        Section {
            Toggle("iCloud Synchronization", isOn: $cloudSync)
            Text(cloudStatus).font(.caption).foregroundStyle(.secondary)
            if sync.enabledAtLaunch {
                Text(sync.activity).font(.caption)
                if let date = sync.lastUpload {
                    LabeledContent("Last upload", value: date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
                if let date = sync.lastDownload {
                    LabeledContent("Last download", value: date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
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
                    await updateCloudStatus()
                }
            }.disabled(checkingSync)
            if let saveStatus { Text(saveStatus).font(.caption).foregroundStyle(.secondary) }
        } header: { Text("iCloud Sync") }
        footer: { Text("Keeps your jobs and shifts in sync across your devices through your private iCloud account.") }
        .task { await updateCloudStatus() }
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

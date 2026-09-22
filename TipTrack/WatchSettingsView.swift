import SwiftUI

struct WatchSettingsView: View {
    @Bindable private var watch = WatchSyncService.shared
    @Bindable private var privacy = PrivacyManager.shared
    @AppStorage(FeatureKeys.watchShowEarnings) private var showEarnings = true
    @AppStorage(FeatureKeys.watchShowTotals) private var showTotals = true
    @AppStorage(FeatureKeys.watchShowLiveTimer) private var showLiveTimer = false

    private var status: (text: String, color: Color) {
        if !watch.isPaired { return ("No Apple Watch paired", .secondary) }
        if !watch.isWatchAppInstalled { return ("TipTrack3r isn't installed on your watch", .orange) }
        return watch.isReachable ? ("Connected", .green) : ("Installed · syncs when nearby", .secondary)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Apple Watch") {
                    Text(status.text).foregroundStyle(status.color)
                }
                if let lastSynced = watch.lastSynced {
                    LabeledContent("Last Synced", value: lastSynced.formatted(date: .omitted, time: .shortened))
                }
                Button("Sync Now") { watch.publish() }
                    .disabled(!watch.isWatchAppInstalled)
            } header: {
                Text("Status")
            } footer: {
                if watch.isPaired && !watch.isWatchAppInstalled {
                    Text("Install TipTrack3r from the Watch app on your iPhone, under Available Apps.")
                }
            }

            Section {
                Toggle("Show Earnings", isOn: $showEarnings)
                Toggle("Show Monthly & Weekly Totals", isOn: $showTotals)
                    .disabled(!showEarnings)
            } header: {
                Text("Home Screen")
            } footer: {
                Text(privacy.enabled
                    ? "Earnings are hidden on your watch while Hide Earnings Until Face ID is on."
                    : "Shows today's earnings, and your month and week totals, on your watch.")
            }

            Section {
                Toggle("Show Live Timer", isOn: $showLiveTimer)
            } footer: {
                Text("Adds Start live timer to your watch. A shift that's already running always shows, so you can end it.")
            }
        }
        .navigationTitle("Apple Watch")
        .onChange(of: [showEarnings, showTotals, showLiveTimer]) {
            watch.publish()
        }
        .onAppear { watch.publish() }
    }
}

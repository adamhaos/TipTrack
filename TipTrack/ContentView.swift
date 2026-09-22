import SwiftUI
import SwiftData
import UserNotifications
import AppIntents

// MARK: - Root View
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }, sort: \Shift.date) private var shifts: [Shift]
    @Query(sort: \Job.name) private var jobs: [Job]
    @AppStorage(FeatureKeys.appLock) private var appLock = false
    @AppStorage(FeatureKeys.onboarding) private var gentleOnboarding = true
    @AppStorage(FeatureKeys.theme) private var theme = TipTrackTheme.system.rawValue
    @AppStorage(FeatureKeys.customAccent) private var customAccent = "#007AFF"
    @AppStorage(FeatureKeys.spotlight) private var spotlightEnabled = true
    @AppStorage(FeatureKeys.weekStart) private var weekStart = 2
    // Widget intents run in the extension and can't post an in-process notification,
    // so watch the shared key for routes written while the app is already active.
    @AppStorage("tiptrack.pendingRoute", store: UserDefaults(suiteName: "group.atm.TipTrack"))
    private var observedPendingRoute = ""
    @State private var showOnboarding = false

    private var widgetSnapshotSignature: [WidgetShiftSnapshot] {
        var snapshots: [WidgetShiftSnapshot] = []
        snapshots.reserveCapacity(shifts.count)
        for shift in shifts {
            snapshots.append(WidgetShiftSnapshot(shift: shift))
        }
        return snapshots
    }

    private struct SpotlightSignature: Hashable {
        let enabled: Bool
        let jobs: [String]
        let shifts: [WidgetShiftSnapshot]
    }

    private var spotlightSignature: SpotlightSignature {
        SpotlightSignature(enabled: spotlightEnabled,
            jobs: jobs.map { "\($0.id)|\($0.name)" }, shifts: widgetSnapshotSignature)
    }

    var body: some View {
        ZStack {
            LogAndTotalsView()
            if appLock && !PrivacyManager.shared.unlocked {
                AppLockView().transition(.opacity).zIndex(20)
            }
        }
            .preferredColorScheme(preferredColorScheme)
            .tint(themeAccent)
            .toggleStyle(InstantSwitchToggleStyle())
            .environment(\.tipTrackColorful, TipTrackTheme(rawValue: theme) == .colorful)
            .task {
                TipTrackShortcuts.updateAppShortcutParameters()
                handlePendingWidgetRoute()
                UNUserNotificationCenter.current().delegate = AppRoute.shared
                WidgetSnapshotWriter.publish(shifts: shifts)
                await ScheduleStore.shared.refresh(context: context)
                if gentleOnboarding && !UserDefaults.standard.bool(forKey: "onboarding.completed") {
                    UserDefaults.standard.set(true, forKey: "onboarding.completed")
                    showOnboarding = true
                }
            }
            .task(id: spotlightSignature) {
                // Debounce so a burst of edits reindexes once.
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                await TipTrackSpotlightIndexer.update(jobs: jobs, shifts: shifts)
            }
            .task(id: widgetSnapshotSignature) {
                // Rewriting the full backup CSV is costly; wait for edits to settle.
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                AutomaticBackupManager.runIfNeeded(shifts: shifts)
            }
            .onChange(of: widgetSnapshotSignature) {
                WidgetSnapshotWriter.publish(snapshotShifts: widgetSnapshotSignature)
                WatchSyncService.shared.publish()
                Task { await ScheduleStore.shared.scheduleReminders(context: context) }
            }
            .onChange(of: ScheduleStore.shared.events) {
                WatchSyncService.shared.publish()
            }
            .onChange(of: weekStart) {
                WidgetSnapshotWriter.publish(shifts: shifts)
                WatchSyncService.shared.publish()
            }
            .onChange(of: PrivacyManager.shared.enabled) {
                WidgetSnapshotWriter.publish(shifts: shifts)
                WatchSyncService.shared.publish()
            }
            .onChange(of: jobs.map { "\($0.id.uuidString)|\($0.name)|\($0.colorHex)|\($0.isDefault)" }) {
                TipTrackShortcuts.updateAppShortcutParameters()
                WatchSyncService.shared.publish()
            }
            .onChange(of: PrivacyManager.shared.unlocked) {
                if PrivacyManager.shared.unlocked {
                    handlePendingWidgetRoute()
                    TipTrackShortcuts.updateAppShortcutParameters()
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    handlePendingWidgetRoute()
                    Task {
                        await ScheduleStore.shared.refresh(context: context)
                        LiveShiftManager.shared.reloadSharedState()
                    }
                } else if scenePhase == .background {
                    PrivacyManager.shared.unlocked = false
                }
            }
            .onOpenURL(perform: routeWidgetURL)
            .onReceive(NotificationCenter.default.publisher(for: .tipTrackIntentRoute)) { _ in
                handlePendingWidgetRoute()
            }
            .onChange(of: observedPendingRoute) {
                // A locked app re-stores the route until unlock; don't loop on that write.
                guard !observedPendingRoute.isEmpty, !appLock || PrivacyManager.shared.unlocked else { return }
                handlePendingWidgetRoute()
            }
            .sheet(isPresented: $showOnboarding) {
                GentleOnboardingView()
            }
    }

    private func handlePendingWidgetRoute() {
        let defaults = UserDefaults(suiteName: "group.atm.TipTrack")
        let route = defaults?.string(forKey: "tiptrack.pendingRoute") ?? ""
        guard !route.isEmpty else { return }
        defaults?.removeObject(forKey: "tiptrack.pendingRoute")
        openRoute(route)
    }

    private func routeWidgetURL(_ url: URL) {
        guard url.scheme == "tiptrack",
              let route = url.host,
              ["log", "history", "calendar", "start", "stop"].contains(route) else { return }
        openRoute(route)
    }

    private func openRoute(_ route: String) {
        if appLock && !PrivacyManager.shared.unlocked {
            UserDefaults(suiteName: "group.atm.TipTrack")?.set(route, forKey: "tiptrack.pendingRoute")
            return
        }
        switch route {
        case "log": AppRoute.shared.openLog()
        case "history": AppRoute.shared.openHistory()
        case "calendar": AppRoute.shared.openCalendar()
        case "start": AppRoute.shared.openTimerStart()
        case "stop": AppRoute.shared.openTimerStop()
        default: break
        }
    }

    private var themeAccent: Color {
        switch TipTrackTheme(rawValue: theme) ?? .system {
        case .neutral: .gray
        case .colorful: .purple
        case .ocean: .cyan
        case .sunset: .orange
        case .forest: .green
        case .custom: Color(hex: customAccent)
        case .dark: .mint
        case .light: .blue
        case .highContrast: .primary
        case .jobColor: jobs.first(where: \.isDefault).map { Color(hex: $0.colorHex) } ?? .blue
        case .system: .blue
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch TipTrackTheme(rawValue: theme) ?? .system {
        case .dark: .dark
        case .light: .light
        default: nil
        }
    }
}

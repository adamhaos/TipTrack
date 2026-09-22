import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit

@MainActor
final class TipTrackAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            queue(item)
            return false
        }
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void) {
        completionHandler(handle(shortcutItem))
    }

    @discardableResult
    private func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch item.type {
        case "atm.TipTrack.log": AppRoute.shared.openLog()
        case "atm.TipTrack.history": AppRoute.shared.openHistory()
        default: return false
        }
        return true
    }

    private func queue(_ item: UIApplicationShortcutItem) {
        let route: String?
        switch item.type {
        case "atm.TipTrack.log": route = "log"
        case "atm.TipTrack.history": route = "history"
        default: route = nil
        }
        guard let route else { return }
        UserDefaults(suiteName: "group.atm.TipTrack")?.set(route, forKey: "tiptrack.pendingRoute")
    }
}

@main
struct TipTrackerApp: App {
    @UIApplicationDelegateAdaptor(TipTrackAppDelegate.self) private var appDelegate
    let container: ModelContainer?
    let startupError: String?

    init() {
        let schema = Schema([Shift.self, Job.self])
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["TIPTRACK_SCREENSHOT_DEMO"] == "1" {
            do {
                let demo = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                ])
                let defaults = UserDefaults.standard
                defaults.set(false, forKey: "cloudSyncEnabled")
                defaults.set(false, forKey: FeatureKeys.automaticBackups)
                defaults.set(false, forKey: FeatureKeys.spotlight)
                defaults.set(true, forKey: "onboarding.completed")
                defaults.set(true, forKey: FeatureKeys.receipts)
                defaults.set(true, forKey: FeatureKeys.liveTimer)
                defaults.set(false, forKey: FeatureKeys.hourlyPayEnabled)
                let restaurant = Job(name: "Harbor & Vine", colorHex: "#007AFF", isDefault: true)
                let cafe = Job(name: "Sunday Coffee", colorHex: "#FF9500")
                demo.mainContext.insert(restaurant)
                demo.mainContext.insert(cafe)
                let calendar = Calendar.current
                for offset in 0..<110 {
                    guard offset % 7 != 1 && offset % 7 != 4,
                          let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
                    demo.mainContext.insert(Shift(date: date,
                        creditTip: Double(135 + (offset * 37) % 180) + 0.75,
                        cashTip: Double(32 + (offset * 11) % 80),
                        barTipOut: Double(9 + offset % 13),
                        hoursWorked: 5.5 + Double(offset % 4) * 0.5,
                        job: offset % 3 == 0 ? cafe : restaurant))
                }
                if ProcessInfo.processInfo.environment["TIPTRACK_STRESS_DEMO"] == "1" {
                    let longName = Job(name: "The Restaurant With a Very Long Job Name", colorHex: "#AF52DE")
                    demo.mainContext.insert(longName)
                    for index in 0..<36 {
                        demo.mainContext.insert(Shift(date: Date(),
                            creditTip: Double(10 + index), cashTip: 15, barTipOut: 5,
                            hoursWorked: 0.5, job: index % 2 == 0 ? longName : restaurant))
                    }
                }
                try demo.mainContext.save()
                container = demo
                startupError = nil
                TipTrackIntentStore.register(demo)
                WatchSyncService.shared.activate(container: demo)
            } catch {
                container = nil
                startupError = "Could not prepare screenshot demo: \(error.localizedDescription)"
            }
            return
        }
        #endif
        let automatic = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        let legacy = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        let storeURL = FileManager.default.fileExists(atPath: automatic.url.path) ? automatic.url :
            (FileManager.default.fileExists(atPath: legacy.path) ? legacy : automatic.url)
        let enabled = UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true
        CloudSyncStatus.shared.enabledAtLaunch = enabled
        let config = ModelConfiguration(schema: schema, url: storeURL,
            cloudKitDatabase: enabled ? .private("iCloud.atm.TipTrack") : .none)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
            if let container {
                TipTrackIntentStore.register(container)
                WatchSyncService.shared.activate(container: container)
            }
            startupError = nil
        } catch {
            container = nil
            startupError = "Your saved data has been kept. TipTrack could not open its database: \(error.localizedDescription)"
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView().modelContainer(container)
            } else {
                ContentUnavailableView("Unable to Open TipTrack", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupError ?? "Please try opening the app again."))
            }
        }
        .backgroundTask(.appRefresh("atm.TipTrack.scheduleRefresh")) {
            if let container {
                await ScheduleStore.shared.backgroundRefresh(container: container)
            }
        }
    }
}

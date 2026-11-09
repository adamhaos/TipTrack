import Foundation

/// Mirrors app preferences through iCloud key-value storage, so a second or new
/// device picks up the same dashboard, entry, calendar and appearance settings.
/// Jobs (with their schedule links, colors and reminders) and shifts sync on their
/// own through CloudKit; this covers the settings that live outside the database.
///
/// The daily reminder's time, weekdays and Time Sensitive choice sync too, so
/// every device reminds at the same time.
///
/// Device-only choices stay local: Face ID lock, hidden earnings, Spotlight,
/// whether iCloud sync is on, and whether daily reminders are turned on (each
/// device needs its own notification permission, and a device that is denied
/// would otherwise switch reminders off everywhere).
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()

    static let syncedKeys: [String] = [
        FeatureKeys.cardOrder, FeatureKeys.greeting, FeatureKeys.showMonthly, FeatureKeys.showWeekly,
        FeatureKeys.showCalendarStrip, FeatureKeys.showLiveActivity, FeatureKeys.showLogShift,
        FeatureKeys.showSpacer1, FeatureKeys.showSpacer2, FeatureKeys.showSpacer3, FeatureKeys.showSpacer4,
        FeatureKeys.headlineMetric, FeatureKeys.validation, FeatureKeys.receipts,
        FeatureKeys.automaticBackups, FeatureKeys.calendarEarnings, FeatureKeys.preShiftReminder,
        "preShiftReminderMinutes", FeatureKeys.liveTimer, FeatureKeys.onboarding, FeatureKeys.weekStart,
        FeatureKeys.theme, FeatureKeys.customAccent, FeatureKeys.duplicateProtection,
        FeatureKeys.hourlyPayEnabled, FeatureKeys.shiftNotes, FeatureKeys.alwaysShowInsightsLabel,
        FeatureKeys.hourlyRate, FeatureKeys.watchShowEarnings, FeatureKeys.watchShowTotals,
        FeatureKeys.watchShowLiveTimer, "automaticJobSelection", "insightsDiscoveryCount",
        "onboarding.completed",
    ] + reminderKeys

    /// The daily reminder schedule; a change from another device reschedules
    /// this device's reminders.
    static let reminderKeys: [String] = [NotificationManager.DefaultsKey.reminderTime,
        NotificationManager.DefaultsKey.activeDays, NotificationManager.DefaultsKey.isTimeSensitive]

    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    private var started = false
    private var applyingRemote = false

    private init() {}

    var isEnabled: Bool {
        local.object(forKey: "cloudSyncEnabled") as? Bool ?? true
    }

    /// Starts syncing for this launch when iCloud sync is on, matching the database.
    func start() {
        guard !started, isEnabled else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { self?.pull(keys: keys) }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: local, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        cloud.synchronize()
        // Settings already in iCloud came from another device and win; a setting only
        // this device has goes up for the others.
        pull(keys: nil)
        push()
    }

    /// Copies iCloud's values into this device's settings, which updates the screens
    /// reading them.
    private func pull(keys: [String]?) {
        let wanted = keys.map { Set($0).intersection(Self.syncedKeys) } ?? Set(Self.syncedKeys)
        applyingRemote = true
        defer { applyingRemote = false }
        var applied: [String] = []
        for key in wanted {
            guard let value = cloud.object(forKey: key) else { continue }
            if !Self.same(local.object(forKey: key), value) {
                local.set(value, forKey: key)
                applied.append(key)
            }
        }
        if !Set(applied).isDisjoint(with: Self.reminderKeys) {
            NotificationManager.shared.reloadSyncedSchedule()
        }
    }

    /// Sends settings changed on this device up to iCloud.
    private func push() {
        guard !applyingRemote else { return }
        var changed = false
        for key in Self.syncedKeys {
            guard let value = local.object(forKey: key) else { continue }
            if !Self.same(cloud.object(forKey: key), value) {
                cloud.set(value, forKey: key)
                changed = true
            }
        }
        if changed {
            cloud.synchronize()
        }
    }

    private static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): (lhs as AnyObject).isEqual(rhs)
        default: false
        }
    }
}

import Foundation
import UserNotifications
import Observation

/// A MainActor-isolated manager that handles requesting local notification permissions
/// and scheduling custom reminders to log tips.
@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()

    private enum DefaultsKey {
        static let isReminderEnabled = "isReminderEnabled"
        static let isTimeSensitive = "isTimeSensitive"
        static let reminderTime = "reminderTime"
        static let activeDays = "activeDays"
    }
    
    /// Whether the log reminder notification is enabled by the user.
    var isReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isReminderEnabled, forKey: DefaultsKey.isReminderEnabled)
            Task {
                await updateNotificationScheduling()
            }
        }
    }
    
    /// Whether the reminder notification should bypass Do Not Disturb / Focus modes.
    var isTimeSensitive: Bool {
        didSet {
            UserDefaults.standard.set(isTimeSensitive, forKey: DefaultsKey.isTimeSensitive)
            if isReminderEnabled {
                Task {
                    await updateNotificationScheduling()
                }
            }
        }
    }
    
    /// The daily time at which the notification should be delivered.
    var reminderTime: Date {
        didSet {
            UserDefaults.standard.set(reminderTime, forKey: DefaultsKey.reminderTime)
            if isReminderEnabled {
                Task {
                    await updateNotificationScheduling()
                }
            }
        }
    }
    
    /// Active days of the week for notifications (Calendar weekday integers: 1 = Sun, 2 = Mon, ..., 7 = Sat).
    var activeDays: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(activeDays), forKey: DefaultsKey.activeDays)
            if isReminderEnabled {
                Task {
                    await updateNotificationScheduling()
                }
            }
        }
    }
    
    /// Tracks if the application has notification permission.
    var isAuthorized: Bool = false

    /// The current system-level notification authorization state.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether iOS allows this app to deliver time-sensitive notifications.
    var timeSensitiveSetting: UNNotificationSetting = .notSupported
    
    private init() {
        self.isReminderEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.isReminderEnabled)
        self.isTimeSensitive = UserDefaults.standard.bool(forKey: DefaultsKey.isTimeSensitive)
        
        if let storedDate = UserDefaults.standard.object(forKey: DefaultsKey.reminderTime) as? Date {
            self.reminderTime = storedDate
        } else {
            var components = DateComponents()
            components.hour = 20
            components.minute = 0
            self.reminderTime = Calendar.current.date(from: components) ?? Date()
        }
        
        if let storedDays = UserDefaults.standard.array(forKey: DefaultsKey.activeDays) as? [Int] {
            self.activeDays = Set(storedDays)
        } else {
            self.activeDays = Set(1...7)
        }
        
        Task {
            await checkAuthorization()
        }
    }
    
    /// Checks current system notification authorization status.
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        updateAuthorizationState(from: settings)
        
        if !isAuthorized && isReminderEnabled {
            isReminderEnabled = false
        }
    }
    
    /// Requests notification permissions from the system.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            )

            let settings = await UNUserNotificationCenter.current().notificationSettings()
            updateAuthorizationState(from: settings)

            if !granted {
                isReminderEnabled = false
            }
            return granted
        } catch {
            authorizationStatus = .denied
            isAuthorized = false
            isReminderEnabled = false
            return false
        }
    }
    
    private var scheduling = false
    private var pendingScheduling = false

    /// Schedules or cancels notification requests for each selected active weekday.
    func updateNotificationScheduling() async {
        guard !scheduling else { pendingScheduling = true; return }
        scheduling = true
        defer { scheduling = false }
        repeat {
            pendingScheduling = false
            await applyNotificationScheduling()
        } while pendingScheduling
    }

    private func applyNotificationScheduling() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (1...7).map { "tip_reminder_day_\($0)" })
        
        guard isReminderEnabled else { return }
        
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        updateAuthorizationState(from: settings)
        if settings.authorizationStatus == .notDetermined {
            let granted = await requestAuthorization()
            if !granted { return }
        } else if settings.authorizationStatus == .denied {
            isAuthorized = false
            isReminderEnabled = false
            return
        } else {
            isAuthorized = true
        }
        
        guard isReminderEnabled else { return }
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: reminderTime)
        
        for weekday in activeDays {
            let content = UNMutableNotificationContent()
            content.title = "Time to log your tips! 💰"
            content.body = "Keep your Tip Track up to date. Open the app to log today's shift earnings."
            content.sound = .default
            
            if isTimeSensitive && timeSensitiveSetting == .enabled {
                content.interruptionLevel = .timeSensitive
            }
            
            var dateComponents = DateComponents()
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.weekday = weekday
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "tip_reminder_day_\(weekday)", content: content, trigger: trigger)
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("Failed to schedule notification for weekday \(weekday): \(error.localizedDescription)")
            }
        }
    }

    private func updateAuthorizationState(from settings: UNNotificationSettings) {
        authorizationStatus = settings.authorizationStatus
        timeSensitiveSetting = settings.timeSensitiveSetting

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined, .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
}

import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct AppearanceSettingsView: View {
    @AppStorage(FeatureKeys.cardOrder) private var storedCardOrder = ""
    @AppStorage(FeatureKeys.greeting) private var showGreeting = false
    @AppStorage(FeatureKeys.showMonthly) private var showMonthly = true
    @AppStorage(FeatureKeys.showWeekly) private var showWeekly = true
    @AppStorage(FeatureKeys.showCalendarStrip) private var showCalendarStrip = true
    @AppStorage(FeatureKeys.showLiveActivity) private var showLiveActivity = false
    @AppStorage(FeatureKeys.showLogShift) private var showLogShift = true
    @AppStorage(FeatureKeys.showSpacer1) private var showSpacer1 = true
    @AppStorage(FeatureKeys.showSpacer2) private var showSpacer2 = false
    @AppStorage(FeatureKeys.showSpacer3) private var showSpacer3 = true
    @AppStorage(FeatureKeys.showSpacer4) private var showSpacer4 = false
    @AppStorage(FeatureKeys.theme) private var theme = TipTrackTheme.system.rawValue
    @AppStorage(FeatureKeys.customAccent) private var customAccent = "#007AFF"
    @AppStorage(FeatureKeys.headlineMetric) private var headlineMetric = DashboardHeadlineMetric.today.rawValue

    @State private var cards: [DashboardCardID] = []

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(TipTrackTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                if theme == TipTrackTheme.custom.rawValue {
                    ColorPicker("App Accent", selection: Binding(
                        get: { Color(hex: customAccent) },
                        set: { customAccent = UIColor($0).tipTrackHex }
                    ), supportsOpacity: false)
                }
            } header: {
                Text("Color & Theme")
            } footer: {
                Text("Changes the app's colors. System follows your iPhone's light or dark mode, Colorful gives each homepage card its own color, and Job Color uses your default job's color.")
            }

            Section {
                Picker("Headline Metric", selection: $headlineMetric) {
                    ForEach(DashboardHeadlineMetric.allCases) { metric in
                        Text(metric.title).tag(metric.rawValue)
                    }
                }
            } header: {
                Text("Home Headline")
            } footer: {
                Text("The big number at the top of your homepage, such as today's earnings.")
            }

            Section {
                ForEach(cards) { card in
                    Toggle(isOn: visibilityBinding(for: card)) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: card.iconName)
                                .foregroundStyle(
                                    theme == TipTrackTheme.colorful.rawValue
                                        ? card.colorfulColor
                                        : Color.accentColor
                                )
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title)
                                Text(card.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(
                        theme == TipTrackTheme.colorful.rawValue
                            ? card.colorfulColor
                            : Color.accentColor
                    )
                }
                .onMove(perform: moveCards)
            } header: {
                HStack {
                    Text("Homepage")
                    Spacer()
                    EditButton()
                        .textCase(nil)
                }
            } footer: {
                Text("Turn cards on or off to choose what the homepage shows. Tap Edit to drag them into a new order.")
            }

            Section {
                Button("Reset Appearance to Default", action: resetAppearance)
            } footer: {
                Text("Puts the theme, top number and homepage cards back to how they started. Your shifts aren't affected.")
            }
        }
        .navigationTitle("Appearance")
        .onAppear {
            cards = DashboardCardID.ordered(from: storedCardOrder)
        }
    }

    private func moveCards(from source: IndexSet, to destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
        storedCardOrder = cards.map(\.rawValue).joined(separator: ",")
    }

    private func resetAppearance() {
        storedCardOrder = ""
        showGreeting = false
        showMonthly = true
        showWeekly = true
        showCalendarStrip = true
        showLiveActivity = false
        showLogShift = true
        showSpacer1 = true
        showSpacer2 = false
        showSpacer3 = true
        showSpacer4 = false
        theme = TipTrackTheme.system.rawValue
        customAccent = "#007AFF"
        headlineMetric = DashboardHeadlineMetric.today.rawValue
        cards = DashboardCardID.ordered(from: "")
    }

    private func visibilityBinding(for card: DashboardCardID) -> Binding<Bool> {
        switch card {
        case .greeting: $showGreeting
        case .calendar: $showCalendarStrip
        case .monthly: $showMonthly
        case .weekly: $showWeekly
        case .liveActivity: $showLiveActivity
        case .logShift: $showLogShift
        case .spacer1: $showSpacer1
        case .spacer2: $showSpacer2
        case .spacer3: $showSpacer3
        case .spacer4: $showSpacer4
        }
    }
}

struct SmartEntrySettingsView: View {
    @AppStorage(FeatureKeys.validation) private var entryValidation = true
    @AppStorage(FeatureKeys.receipts) private var receiptFeatures = false
    @AppStorage(FeatureKeys.hourlyPayEnabled) private var hourlyPayEnabled = true
    @AppStorage(FeatureKeys.shiftNotes) private var shiftNotes = false
    @AppStorage(FeatureKeys.liveTimer) private var liveTimer = false

    var body: some View {
        Form {
            Section {
                Toggle("Hourly Pay Per Shift", isOn: $hourlyPayEnabled)
                Toggle("Shift Notes", isOn: $shiftNotes)
            } header: {
                Text("Extra Fields")
            } footer: {
                Text("Hourly pay adds a rate field so your base pay counts toward earnings. Notes adds a short note to each shift, like “Private party.”")
            }
            Section {
                Toggle("Live Shift Timer", isOn: $liveTimer)
            } header: {
                Text("Shift Timer")
            } footer: {
                Text("Start a timer when you clock in, from the app, a widget or Control Center. When you log the shift, its hours fill in for you.")
            }
            Section {
                Toggle("Checkout Slip Scanner", isOn: $receiptFeatures)
            } header: {
                Text("Slip Scanner")
            } footer: {
                Text("Adds a Scan Checkout Slip button to Log Shift that reads your tips and tip-out from a photo of your checkout slip. You check the numbers before saving.")
            }
            Section {
                Toggle("High-Value Entry Alerts", isOn: $entryValidation)
            } header: {
                Text("Mistake Check")
            } footer: {
                Text("Asks you to confirm before saving an amount that looks unusually large, to catch typos like an extra zero.")
            }
        }
        .navigationTitle("Logging Options")
    }
}

struct CalendarFeatureSettingsView: View {
    @AppStorage(FeatureKeys.weekStart) private var weekStart = 2
    @AppStorage(FeatureKeys.calendarEarnings) private var calendarEarnings = true

    var body: some View {
        Form {
            Section {
                Picker("Week Starts On", selection: $weekStart) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
            } header: {
                Text("Weeks")
            } footer: {
                Text("Decides where each week begins for weekly totals, the calendar, widgets and Siri.")
            }
            Section {
                Toggle("Show Earnings on Past Days", isOn: $calendarEarnings)
            } header: {
                Text("Calendar")
            } footer: {
                Text("Shows what you made under each past day on the calendar. Turn off for a cleaner calendar with just your shifts.")
            }
        }
        .navigationTitle("Calendar & Weeks")
    }
}

/// Every reminder TipTrack can send, in one place.
struct RemindersSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.name) private var jobs: [Job]
    @AppStorage(FeatureKeys.preShiftReminder) private var preShiftReminder = false
    @AppStorage("preShiftReminderMinutes") private var reminderMinutes = 30
    @Bindable private var notifications = NotificationManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Daily Tip Reminder", isOn: $notifications.isReminderEnabled)
                if notifications.isReminderEnabled {
                    DatePicker("Time", selection: $notifications.reminderTime, displayedComponents: .hourAndMinute)
                    HStack(spacing: 7) {
                        ForEach(Calendar.orderedWeekdays, id: \.self) { weekday in
                            Button {
                                if notifications.activeDays.contains(weekday) {
                                    notifications.activeDays.remove(weekday)
                                } else {
                                    notifications.activeDays.insert(weekday)
                                }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(notifications.activeDays.contains(weekday) ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                                    .foregroundStyle(notifications.activeDays.contains(weekday) ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                            .accessibilityAddTraits(notifications.activeDays.contains(weekday) ? .isSelected : [])
                        }
                    }
                    Toggle("Show During Focus", isOn: $notifications.isTimeSensitive)
                    if notifications.timeSensitiveSetting == .disabled {
                        Link("Allow Time Sensitive Notifications in Settings",
                            destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                            .font(.caption)
                    }
                }
            } header: {
                Text("Every Day")
            } footer: {
                Text(notifications.isReminderEnabled
                    ? "A nudge at this time on the days you pick. Show During Focus lets it through a Focus like Do Not Disturb."
                    : "A nudge at the same time each day to log your tips, whether or not you have a schedule.")
            }

            Section {
                Toggle("Before My Shift Starts", isOn: $preShiftReminder)
                if preShiftReminder {
                    Picker("Remind Me", selection: $reminderMinutes) {
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("2 hours before").tag(120)
                    }
                }
            } header: {
                Text("Scheduled Shifts")
            } footer: {
                Text("A heads-up before each shift starts, using the schedule calendars added to your jobs.")
            }

            Section {
                if jobs.isEmpty {
                    Text("Add a job first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(jobs) { job in
                        ShiftEndReminderSettingsRow(job: job) {
                            Task {
                                if job.endReminder {
                                    _ = await NotificationManager.shared.requestAuthorization()
                                }
                                await ScheduleStore.shared.scheduleReminders(context: context)
                            }
                        }
                    }
                }
            } header: {
                Text("Log Your Shift")
            } footer: {
                Text("Reminds you to log tips around the end of each scheduled shift, per job. Skips shifts you've already logged.")
            }
        }
        .navigationTitle("Reminders")
        .task { await notifications.checkAuthorization() }
        .onChange(of: preShiftReminder) { _, enabled in
            Task {
                if enabled { _ = await NotificationManager.shared.requestAuthorization() }
                await ScheduleStore.shared.scheduleReminders(context: context)
            }
        }
        .onChange(of: reminderMinutes) { _, _ in
            Task { await ScheduleStore.shared.scheduleReminders(context: context) }
        }
    }
}

private struct ShiftEndReminderSettingsRow: View {
    @Bindable var job: Job
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { job.endReminder },
                set: { enabled in
                    job.endReminder = enabled
                    onChange()
                }
            )) {
                Label {
                    Text(job.name)
                } icon: {
                    Image(systemName: job.iconSymbolName)
                        .foregroundStyle(Color(hex: job.colorHex))
                }
            }
            .disabled(job.calendarFeeds.isEmpty && !job.endReminder)

            if job.calendarFeeds.isEmpty {
                Text("Add a schedule calendar to this job in Jobs to use this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if job.endReminder {
                Picker("Reminder Timing", selection: Binding(
                    get: { job.reminderDelay },
                    set: { delay in
                        job.reminderDelay = delay
                        onChange()
                    }
                )) {
                    ForEach(ShiftLoggingReminderTiming.allCases) { timing in
                        Text(timing.title).tag(timing.rawValue)
                    }
                }
            }
        }
    }
}

struct SystemGuidanceSettingsView: View {
    @AppStorage(FeatureKeys.onboarding) private var onboarding = true
    @AppStorage(FeatureKeys.alwaysShowInsightsLabel) private var alwaysShowInsightsLabel = false
    @State private var showingWelcomeGuide = false

    var body: some View {
        Form {
            Section {
                siriPhrase("How much did I make today in Tip Tracker?")
                siriPhrase("What was my best shift in Tip Tracker?")
                siriPhrase("Show my tip history in Tip Tracker")
                if let shortcuts = URL(string: "shortcuts://") {
                    Link(destination: shortcuts) {
                        Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                    }
                }
            } header: {
                Text("Siri")
            } footer: {
                Text("Siri can answer questions about your earnings but can't log shifts. Ask about today, this week, last month, a specific job and more.")
            }

            Section {
                Label("Touch and hold your Home Screen, tap Edit, then Add Widget and search TipTrack.", systemImage: "square.grid.2x2")
                    .font(.subheadline)
                Label("Touch and hold a TipTrack widget, then Edit Widget to change its period and style.", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
            } header: {
                Text("Widgets")
            } footer: {
                Text("Widgets show your earnings on the Home Screen or Lock Screen without opening the app.")
            }

            Section {
                Button("Show Welcome Guide") {
                    showingWelcomeGuide = true
                }
                Toggle("Welcome Guide for New Installs", isOn: $onboarding)
                Toggle("Always Show Insights Label", isOn: $alwaysShowInsightsLabel)
            } header: {
                Text("Help")
            } footer: {
                Text("Show Welcome Guide replays the intro tour any time. The Insights label is the word next to the Insights button on the homepage; it normally hides after you've used it a few times.")
            }
        }
        .navigationTitle("Siri, Widgets & Help")
        .sheet(isPresented: $showingWelcomeGuide) { GentleOnboardingView() }
    }

    private func siriPhrase(_ phrase: String) -> some View {
        Label("“\(phrase)”", systemImage: "mic.fill")
            .font(.subheadline)
    }
}

extension Notification.Name {
    static let showTipTrackOnboarding = Notification.Name("showTipTrackOnboarding")
}

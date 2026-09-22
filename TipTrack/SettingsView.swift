import SwiftData
import SwiftUI

struct SettingsView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    NavigationLink { JobsSettingsView() } label: {
                        SettingsDestinationLabel(title: "Jobs",
                            subtitle: "Schedules, default job and automatic selection",
                            icon: "briefcase.fill", color: .brown)
                    }
                    NavigationLink { CalendarFeatureSettingsView() } label: {
                        SettingsDestinationLabel(title: "Calendar",
                            subtitle: "Week start and daily earnings",
                            icon: "calendar", color: .blue)
                    }
                    NavigationLink { RemindersSettingsView() } label: {
                        SettingsDestinationLabel(title: "Reminders",
                            subtitle: "Daily and scheduled shift reminders",
                            icon: "bell.fill", color: .red)
                    }
                    NavigationLink { SmartEntrySettingsView() } label: {
                        SettingsDestinationLabel(title: "Smart Entry",
                            subtitle: "Timer, hourly pay, notes and scanning",
                            icon: "wand.and.stars", color: .orange)
                    }
                }

                Section("Data") {
                    NavigationLink { DataManagementSettingsView() } label: {
                        SettingsDestinationLabel(title: "Sync, Import & Export", subtitle: "iCloud, backups, CSV and deleted shifts",
                            icon: "arrow.up.arrow.down.circle.fill", color: .green)
                    }
                    NavigationLink { PrivacySettingsView() } label: {
                        SettingsDestinationLabel(title: "Privacy", subtitle: "Face ID, hidden earnings and Spotlight",
                            icon: "faceid", color: .gray)
                    }
                }

                Section("Extra Features & Help") {
                    NavigationLink { AppearanceSettingsView() } label: {
                        SettingsDestinationLabel(title: "Appearance",
                            subtitle: "Theme, headline and homepage cards",
                            icon: "paintpalette.fill", color: .purple)
                    }
                    NavigationLink { WatchSettingsView() } label: {
                        SettingsDestinationLabel(title: "Apple Watch",
                            subtitle: "Earnings, live timer and sync",
                            icon: "applewatch", color: .pink)
                    }
                    NavigationLink { SystemGuidanceSettingsView() } label: {
                        SettingsDestinationLabel(title: "Siri, Widgets & Help",
                            subtitle: "Siri, widgets and the welcome guide",
                            icon: "questionmark.circle.fill", color: .yellow)
                    }
                }
            }
            .listSectionSpacing(12)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { if let onClose { onClose() } else { dismiss() } }
                }
            }
        }
    }

}

private struct DataManagementSettingsView: View {
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }) private var shifts: [Shift]
    @State private var isShowingImport = false
    @AppStorage(FeatureKeys.automaticBackups) private var automaticBackups = true
    @State private var exportText = ""

    var body: some View {
        Form {
            ICloudSyncSection()

            Section {
                Toggle("Daily Automatic Backups", isOn: $automaticBackups)
            } header: {
                Text("Automatic CSV Backups")
            } footer: {
                Text("Keeps a CSV of your shifts for each of the last seven days in TipTrack's folder in the Files app.")
            }

            Section("Import Shifts") {
                Button {
                    isShowingImport = true
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            }

            Section("Export Shifts") {
                ShareLink(
                    item: exportText,
                    preview: SharePreview("TipTrack Shift Export.csv", image: Image(systemName: "tablecells"))
                ) {
                    Label("Export All Shifts to CSV", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                NavigationLink { DeletedShiftsView() } label: {
                    Label("Deleted Shifts", systemImage: "trash")
                }
            } header: {
                Text("Recently Deleted")
            } footer: {
                Text("Restore shifts you've removed.")
            }
        }
        .protectEarnings()
        .navigationTitle("Sync, Import & Export")
        // Built once rather than on every render, which rebuilt the whole CSV each time.
        .task(id: shifts.count) {
            exportText = TipTrackCSV.exportText(for: shifts)
        }
        .sheet(isPresented: $isShowingImport) {
            ImportCSVView()
        }
    }
}

private struct JobsSettingsView: View {
    @Query(sort: \Job.name) private var jobs: [Job]
    @AppStorage("automaticJobSelection") private var automaticJobSelection = false
    @State private var jobToEdit: Job?

    var body: some View {
        Form {
            Section {
                Toggle("Automatic Job Selection", isOn: $automaticJobSelection)
            } footer: {
                Text("Picks the job when you log a shift, using your schedule, each job's days and workplace location.")
            }

            if jobs.isEmpty {
                ContentUnavailableView(
                    "No Jobs Yet",
                    systemImage: "briefcase",
                    description: Text("Add a job to set its name, color, schedule and more.")
                )
            } else {
                Section {
                    ForEach(jobs) { job in
                        Button { jobToEdit = job } label: { JobRow(job: job) }
                            .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Tap a job to edit its details, schedule and automatic selection.")
                }
            }

            Section {
                Button {
                    jobToEdit = Job(name: "")
                } label: {
                    Label("Add New Job", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Jobs")
        .sheet(item: $jobToEdit) { job in
            EditJobView(job: job)
        }
    }
}

private struct JobRow: View {
    let job: Job

    private var detail: String {
        let count = job.calendarFeeds.count
        let schedule = count == 0 ? "No schedule" : "\(count) schedule calendar\(count == 1 ? "" : "s")"
        return job.isDefault ? "Default · \(schedule)" : schedule
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.iconSymbolName)
                .font(.headline)
                .foregroundStyle(Color(hex: job.colorHex))
                .frame(width: 34, height: 34)
                .background(Color(hex: job.colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SettingsDestinationLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

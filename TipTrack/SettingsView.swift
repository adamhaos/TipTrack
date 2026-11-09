import SwiftData
import SwiftUI
import WatchConnectivity

struct SettingsView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { JobsSettingsView() } label: {
                        SettingsDestinationLabel(title: "Jobs",
                            subtitle: "Your workplaces, their schedules and which one is picked when you log",
                            icon: "briefcase.fill", color: .brown)
                    }
                    NavigationLink { SmartEntrySettingsView() } label: {
                        SettingsDestinationLabel(title: "Logging Options",
                            subtitle: "Extra fields and tools on the Log Shift screen",
                            icon: "wand.and.stars", color: .orange)
                    }
                    NavigationLink { RemindersSettingsView() } label: {
                        SettingsDestinationLabel(title: "Reminders",
                            subtitle: "Nudges to log your tips and heads-ups before shifts",
                            icon: "bell.fill", color: .red)
                    }
                } header: {
                    Text("Logging Shifts")
                }

                Section {
                    NavigationLink { DataManagementSettingsView() } label: {
                        SettingsDestinationLabel(title: "Sync, Import & Export",
                            subtitle: "iCloud, daily backups, CSV files and deleted shifts",
                            icon: "arrow.up.arrow.down.circle.fill", color: .green)
                    }
                    NavigationLink { PrivacySettingsView() } label: {
                        SettingsDestinationLabel(title: "Privacy",
                            subtitle: "Face ID lock, hidden earnings and search",
                            icon: "faceid", color: .gray)
                    }
                } header: {
                    Text("Your Data")
                }

                Section {
                    NavigationLink { AppearanceSettingsView() } label: {
                        SettingsDestinationLabel(title: "Appearance",
                            subtitle: "Theme, the top number and which homepage cards show",
                            icon: "paintpalette.fill", color: .purple)
                    }
                    NavigationLink { CalendarFeatureSettingsView() } label: {
                        SettingsDestinationLabel(title: "Calendar & Weeks",
                            subtitle: "First day of the week and earnings on the calendar",
                            icon: "calendar", color: .blue)
                    }
                } header: {
                    Text("Display")
                }

                Section {
                    // An Apple Watch pairs only with iPhone, so iPad leaves this out.
                    if WCSession.isSupported() {
                        NavigationLink { WatchSettingsView() } label: {
                            SettingsDestinationLabel(title: "Apple Watch",
                                subtitle: "What your watch shows, and syncing to it",
                                icon: "applewatch", color: .pink)
                        }
                    }
                    NavigationLink { SystemGuidanceSettingsView() } label: {
                        SettingsDestinationLabel(title: "Siri, Widgets & Help",
                            subtitle: "What to ask Siri, adding widgets and the welcome guide",
                            icon: "questionmark.circle.fill", color: .yellow)
                    }
                } header: {
                    Text("More")
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

    /// Changes whenever anything that appears in the export changes, including edits that
    /// arrive from iCloud while this screen is open. Much cheaper than rebuilding the CSV.
    private var exportSignature: Int {
        var hasher = Hasher()
        for shift in shifts {
            hasher.combine(shift.id)
            hasher.combine(shift.date)
            hasher.combine(shift.creditTip)
            hasher.combine(shift.cashTip)
            hasher.combine(shift.barTipOut)
            hasher.combine(shift.hoursWorked)
            hasher.combine(shift.hourlyRate)
            hasher.combine(shift.notes)
            hasher.combine(shift.job?.name)
        }
        return hasher.finalize()
    }

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

            Section {
                Button {
                    isShowingImport = true
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Import Shifts")
            } footer: {
                Text("Adds shifts from a spreadsheet file, like an export from TipTrack or another app. You'll see a preview before anything is saved.")
            }

            Section {
                ShareLink(
                    item: exportText,
                    preview: SharePreview("TipTrack Shift Export.csv", image: Image(systemName: "tablecells"))
                ) {
                    Label("Export All Shifts to CSV", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Export Shifts")
            } footer: {
                Text("Makes a spreadsheet of every shift you can save to Files, email or open in Numbers or Excel.")
            }

            Section {
                NavigationLink { DeletedShiftsView() } label: {
                    Label("Deleted Shifts", systemImage: "trash")
                }
            } header: {
                Text("Recently Deleted")
            } footer: {
                Text("Shifts you delete wait here so you can bring them back.")
            }
        }
        .protectEarnings()
        .navigationTitle("Sync, Import & Export")
        // Built once rather than on every render, which rebuilt the whole CSV each time.
        .task(id: exportSignature) {
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
                    // The first job becomes the default, as it does from the dashboard.
                    jobToEdit = Job(name: "", isDefault: jobs.isEmpty)
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

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftData
import SwiftUI

/// Everything about one job on a single screen: details, schedule and automatic selection.
struct EditJobView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Job.name) private var jobs: [Job]
    @AppStorage(FeatureKeys.receipts) private var receiptFeatures = false
    @Bindable private var location = JobLocationManager.shared
    @Bindable private var schedule = ScheduleStore.shared

    let job: Job

    @State private var name: String
    @State private var colorHex: String
    @State private var iconName: String
    @State private var makeDefault: Bool
    @State private var receiptPOS: ShiftReportType
    @State private var feeds: [JobCalendarFeed]
    @State private var days: Set<Int>
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var radius: Double
    @State private var capturingLocation = false
    @State private var isSaving = false
    @State private var isConfirmingDeletion = false
    @State private var saveError: String?

    init(job: Job) {
        self.job = job
        _name = State(initialValue: job.name)
        _colorHex = State(initialValue: job.colorHex)
        _iconName = State(initialValue: job.iconName)
        _makeDefault = State(initialValue: job.isDefault)
        _receiptPOS = State(initialValue: ShiftReportType(rawValue: job.receiptPOS) ?? .automatic)
        _feeds = State(initialValue: job.calendarFeeds)
        _days = State(initialValue: Set(job.selectionDays.split(separator: ",").compactMap { Int($0) }))
        _latitude = State(initialValue: job.latitude)
        _longitude = State(initialValue: job.longitude)
        _radius = State(initialValue: job.locationRadius)
    }

    private var isNewJob: Bool { job.modelContext == nil }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                defaultSection
                scheduleSection
                automaticSelectionSection
                if receiptFeatures { receiptSection }

                if !isNewJob {
                    Section {
                        Button("Delete Job", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                    }
                }
            }
            .navigationTitle(isNewJob ? "New Job" : "Edit Job")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't Update Job", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "") }
            .confirmationDialog("Delete Job?", isPresented: $isConfirmingDeletion) {
                Button("Delete \(job.name)", role: .destructive) {
                    deleteJob()
                }
            } message: {
                Text("Shifts you've logged for \(job.name) stay in your history.")
            }
            .onChange(of: location.location) { _, value in
                guard capturingLocation, let value else { return }
                latitude = value.coordinate.latitude
                longitude = value.coordinate.longitude
                capturingLocation = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(trimmedName.isEmpty || isSaving || location.requesting)
                }
            }
        }
    }

    // MARK: Sections

    private var detailsSection: some View {
        Section("Job") {
            TextField("Job Name", text: $name)
            NavigationLink {
                JobIconPicker(selection: $iconName, color: Color(hex: colorHex))
            } label: {
                HStack {
                    Text("Icon")
                    Spacer()
                    Image(systemName: JobIconCatalog.symbolName(for: iconName)).foregroundStyle(Color(hex: colorHex))
                    Text(JobIconCatalog.title(for: iconName)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Color")
                HStack(spacing: 12) {
                    ForEach(JobColorPalette.hexValues, id: \.self) { hex in
                        colorButton(for: hex)
                    }
                }
                ColorPicker("Custom Color", selection: customColor, supportsOpacity: false)
            }
            .padding(.vertical, 4)
        }
    }

    private var defaultSection: some View {
        Section {
            Toggle("Default Job", isOn: $makeDefault)
                .disabled(job.isDefault)
        } footer: {
            Text(job.isDefault
                ? "To change the default, turn it on for another job."
                : "Selected automatically when you log a new shift.")
        }
    }

    private var scheduleSection: some View {
        Section {
            ForEach($feeds) { $feed in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Calendar name", text: $feed.name)
                            .font(.subheadline.weight(.semibold))
                        Button(role: .destructive) {
                            feeds.removeAll { $0.id == feed.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(feed.name)")
                    }
                    TextField("https://… or webcal://…", text: $feed.url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Only events containing… (optional)", text: $feed.filter)
                }
                .padding(.vertical, 4)
            }
            Button {
                feeds.append(JobCalendarFeed(name: feeds.isEmpty ? "Work Schedule" : "Additional Schedule"))
            } label: {
                Label("Add Schedule Calendar", systemImage: "plus.circle.fill")
            }
            if let status = schedule.status[job.id] {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if let help = URL(string: "https://kb.7shifts.com/hc/en-us/articles/4861793532691-Sync-Your-7shifts-Schedule-with-Google-and-Apple-Calendar") {
                Link("How to get a 7shifts calendar link", destination: help)
                    .font(.caption)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Paste the calendar subscription link (.ics or webcal) from your scheduling app.")
        }
    }

    private var automaticSelectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Days")
                HStack(spacing: 7) {
                    ForEach(Calendar.orderedWeekdays, id: \.self) { day in
                        let selected = days.contains(day)
                        Button {
                            if selected { days.remove(day) } else { days.insert(day) }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(selected ? Color(hex: colorHex) : Color.secondary.opacity(0.15), in: Circle())
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)

            if latitude == nil {
                Button(location.requesting ? "Finding Location…" : "Use My Current Location") {
                    capturingLocation = true
                    location.request()
                }
                .disabled(location.requesting)
            } else {
                Picker(selection: $radius) {
                    Text("150 m").tag(150.0)
                    Text("300 m").tag(300.0)
                    Text("500 m").tag(500.0)
                    Text("1 km").tag(1000.0)
                } label: {
                    Label("Workplace Saved", systemImage: "mappin.circle.fill")
                }
                Button("Remove Location", role: .destructive) {
                    latitude = nil
                    longitude = nil
                }
            }
            if let message = location.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Automatic Selection")
        } footer: {
            Text("With Automatic Job Selection on, TipTrack picks this job on these days or near this workplace.")
        }
    }

    private var receiptSection: some View {
        Section {
            Picker("POS System", selection: $receiptPOS) {
                ForEach(ShiftReportType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
        } header: {
            Text("Checkout Slips")
        } footer: {
            Text("The report format used when scanning this job's slips.")
        }
    }

    // MARK: Helpers

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) },
            set: { colorHex = UIColor($0).tipTrackHex }
        )
    }

    private func colorButton(for hex: String) -> some View {
        Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 32, height: 32)
                .overlay {
                    Circle()
                        .stroke(Color.primary, lineWidth: colorHex == hex ? 3 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Job color")
        .accessibilityValue(colorHex == hex ? "Selected" : "Not selected")
    }

    private func saveChanges() async {
        guard !trimmedName.isEmpty else { return }
        let cleanedFeeds = feeds.map {
            let feedName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return JobCalendarFeed(
                id: $0.id,
                name: feedName.isEmpty ? "Work Schedule" : feedName,
                url: $0.url.trimmingCharacters(in: .whitespacesAndNewlines),
                filter: $0.filter.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.filter { !$0.url.isEmpty }
        guard cleanedFeeds.allSatisfy({ CalendarFeed.url($0.url) != nil }) else {
            saveError = "Each schedule calendar needs a valid https:// or webcal:// link."
            return
        }

        isSaving = true
        defer { isSaving = false }
        let scheduleChanged = cleanedFeeds != job.calendarFeeds
        job.name = trimmedName
        job.colorHex = colorHex
        job.iconName = iconName
        job.receiptPOS = receiptPOS.rawValue
        job.calendarFeeds = cleanedFeeds
        // Logging reminders need a schedule to fire from.
        if cleanedFeeds.isEmpty { job.endReminder = false }
        job.selectionDays = days.sorted().map(String.init).joined(separator: ",")
        job.latitude = latitude
        job.longitude = longitude
        job.locationRadius = radius

        if isNewJob {
            modelContext.insert(job)
        }
        if makeDefault {
            job.isDefault = true
            for existingJob in jobs {
                existingJob.isDefault = existingJob.id == job.id
            }
        }

        if persistChanges() && scheduleChanged {
            Task { await schedule.refresh(context: modelContext) }
        }
    }

    private func deleteJob() {
        if job.isDefault, let replacement = jobs.first(where: { $0.id != job.id }) {
            replacement.isDefault = true
        }
        modelContext.delete(job)
        persistChanges()
    }

    @discardableResult
    private func persistChanges() -> Bool {
        do {
            try modelContext.save()
            dismiss()
            return true
        } catch {
            modelContext.rollback()
            saveError = "Your changes could not be saved. Please try again. \(error.localizedDescription)"
            return false
        }
    }
}

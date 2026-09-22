import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSV Import
struct ImportCSVView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.name) private var jobs: [Job]
    @Query(filter: #Predicate<Shift> { $0.deletedAt == nil }) private var existingShifts: [Shift]
    @AppStorage(FeatureKeys.duplicateProtection) private var duplicateProtection = true

    @State private var rawText = ""
    @State private var parsedRows: [TipTrackCSV.Row] = []
    @State private var isShowingFileImporter = false
    @State private var selectedFileName: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                fileSection
                pasteSection

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(parsedRows.isEmpty ? .red : .secondary)
                    }
                }

                if !parsedRows.isEmpty {
                    previewSection
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(parsedRows.count))") {
                        importParsedShifts()
                    }
                    .disabled(parsedRows.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                switch result {
                case .success(let url):
                    loadCSVFile(from: url)
                case .failure(let error):
                    statusMessage = "Could not open the CSV file: \(error.localizedDescription)"
                }
            }
        }
    }

    private var fileSection: some View {
        Section {
            Button {
                isShowingFileImporter = true
            } label: {
                Label("Choose CSV File", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)

            if let selectedFileName {
                Label(selectedFileName, systemImage: "doc.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Import a File")
        } footer: {
            Text("Expected columns: \(TipTrackCSV.header)")
        }
    }

    private var pasteSection: some View {
        Section("Or Paste CSV Text") {
            TextEditor(text: $rawText)
                .frame(minHeight: 110)
                .padding(8)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)

            Button {
                parseCSV()
            } label: {
                Label("Read Pasted CSV", systemImage: "tablecells")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var previewSection: some View {
        Section("Recognized Shifts (\(parsedRows.count))") {
            ForEach(parsedRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.date.formatted(.dateTime.month().day().year().hour().minute()))
                            .font(.subheadline)
                            .bold()

                        if !row.jobName.isEmpty {
                            Text(row.jobName)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(jobColor(for: row.jobName).opacity(0.2))
                                .foregroundStyle(jobColor(for: row.jobName))
                                .cornerRadius(4)
                        }
                    }

                    HStack {
                        Text("Credit: \(row.creditTip, format: .currency(code: "USD"))")
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("Cash: \(row.cashTip, format: .currency(code: "USD"))")
                            .foregroundStyle(.green)
                        if row.barTipOut > 0 {
                            Spacer()
                            Text("Tip Out: \(row.barTipOut, format: .currency(code: "USD"))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption.bold())

                    if let hoursWorked = row.hoursWorked {
                        Text("Hours: \(hoursWorked.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func loadCSVFile(from url: URL) {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            rawText = try String(contentsOf: url, encoding: .utf8)
            selectedFileName = url.lastPathComponent
            parseCSV()
        } catch {
            parsedRows = []
            statusMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func parseCSV() {
        let result = TipTrackCSV.parse(rawText)
        parsedRows = result.rows

        if result.rows.isEmpty {
            statusMessage = "No valid shifts were found. Make sure the file uses the TipTrack CSV format."
        } else if result.rejectedRowCount > 0 {
            statusMessage = "Found \(result.rows.count) shifts. Skipped \(result.rejectedRowCount) invalid row(s)."
        } else {
            let duplicates = duplicateProtection
                ? result.rows.count - TipTrackCSV.rowsForImport(result.rows, existingShifts: existingShifts).count : 0
            statusMessage = duplicates > 0
                ? "Ready to import \(result.rows.count - duplicates) new shifts. \(duplicates) likely duplicate\(duplicates == 1 ? "" : "s") will be skipped."
                : "Ready to import \(result.rows.count) shifts."
        }
    }

    private func importParsedShifts() {
        var jobsByName = Dictionary(
            jobs.map { (normalized($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var newJobCount = 0

        let rowsToImport = duplicateProtection
            ? TipTrackCSV.rowsForImport(parsedRows, existingShifts: existingShifts) : parsedRows
        let skippedDuplicates = parsedRows.count - rowsToImport.count
        for row in rowsToImport {
            let job = jobForImport(
                named: row.jobName,
                jobsByName: &jobsByName,
                newJobCount: &newJobCount
            )

            let imported = Shift(
                    date: row.date,
                    creditTip: row.creditTip,
                    cashTip: row.cashTip,
                    barTipOut: row.barTipOut,
                    hoursWorked: row.hoursWorked,
                    hourlyRate: row.hourlyRate,
                    notes: row.notes,
                    job: job)
            imported.sourceFingerprint = TipTrackCSV.fingerprint(row)
            modelContext.insert(imported)
        }

        do {
            try modelContext.save()
            if skippedDuplicates == parsedRows.count {
                statusMessage = "Nothing was imported because every row already exists."
            } else {
                dismiss()
            }
        } catch {
            modelContext.rollback()
            statusMessage = "The shifts were read, but could not be saved: \(error.localizedDescription)"
        }
    }

    private func jobForImport(
        named name: String,
        jobsByName: inout [String: Job],
        newJobCount: inout Int
    ) -> Job? {
        let key = normalized(name)
        guard !key.isEmpty, key != "unassigned" else { return nil }

        if let existingJob = jobsByName[key] {
            return existingJob
        }

        let colorIndex = (jobs.count + newJobCount) % JobColorPalette.hexValues.count
        let job = Job(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: JobColorPalette.hexValues[colorIndex],
            isDefault: jobs.isEmpty && newJobCount == 0
        )
        modelContext.insert(job)
        jobsByName[key] = job
        newJobCount += 1
        return job
    }

    private func jobColor(for name: String) -> Color {
        jobs.first { normalized($0.name) == normalized(name) }
            .map { Color(hex: $0.colorHex) } ?? .secondary
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}

import CoreSpotlight
import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
enum AutomaticBackupManager {
    static func runIfNeeded(shifts: [Shift]) {
        let setting = UserDefaults.standard.object(forKey: FeatureKeys.automaticBackups) as? Bool ?? true
        guard setting else { return }
        let stamp = Date().formatted(.iso8601.year().month().day())
        do {
            let folder = URL.documentsDirectory.appendingPathComponent("TipTrack Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("TipTrack-Automatic-\(stamp).csv")
            try TipTrackCSV.exportText(for: shifts).write(to: file, atomically: true, encoding: .utf8)
            let files = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "csv" }
                .sorted {
                    let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return left > right
                }
            for old in files.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
            UserDefaults.standard.set(stamp, forKey: "backup.lastDate")
        } catch {
            // A failed automatic backup never interrupts logging or modifies existing data.
        }
    }
}

@MainActor
enum TipTrackSpotlightIndexer {
    private static let domain = "atm.TipTrack.content"

    static func update(jobs: [Job], shifts: [Shift]) async {
        // On unless the person turns it off in Privacy.
        guard UserDefaults.standard.object(forKey: FeatureKeys.spotlight) as? Bool ?? true else {
            try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
            return
        }
        let jobItems = jobs.map { job in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = job.name
            attributes.contentDescription = "TipTrack job"
            attributes.keywords = ["TipTrack", "job", "work"]
            attributes.contentURL = URL(string: "tiptrack://log")
            return CSSearchableItem(uniqueIdentifier: "job.\(job.id.uuidString)", domainIdentifier: domain,
                attributeSet: attributes)
        }
        let shiftItems = shifts.filter { $0.deletedAt == nil }.map { shift in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = "\(shift.job?.name ?? "Shift") · \(shift.date.formatted(date: .abbreviated, time: .omitted))"
            attributes.contentDescription = "Logged shift in TipTrack"
            attributes.keywords = ["TipTrack", "shift", shift.job?.name ?? "work"]
            attributes.contentURL = URL(string: "tiptrack://history")
            return CSSearchableItem(uniqueIdentifier: "shift.\(shift.id.uuidString)", domainIdentifier: domain,
                attributeSet: attributes)
        }
        // Replace the domain so deleted or renamed records cannot remain searchable.
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !Task.isCancelled else { return }
        try? await CSSearchableIndex.default().indexSearchableItems(jobItems + shiftItems)
    }
}

struct GentleOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Short enough to read without scrolling; scrolls only at very large text sizes.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to TipTrack3r")
                        .font(.largeTitle.bold())
                    Text("Track every tip in a few taps.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 18) {
                    onboardingRow("Log a Shift", "Tap Log Shift, pick a job and enter your tips.", "plus.circle.fill", .blue)
                    onboardingRow("See Your Earnings", "Weekly and monthly totals, plus Insights on your best shifts.", "chart.bar.fill", .green)
                    onboardingRow("Add Your Schedule", "Link your work calendar to a job for upcoming shifts and reminders.", "calendar", .red)
                    onboardingRow("Synced & Backed Up", "Your shifts sync to your other devices with iCloud and back up daily.", "icloud.fill", .indigo)
                    onboardingRow("Make It Yours", "Pick a theme and homepage cards in Settings.", "paintpalette.fill", .purple)
                    onboardingRow("Ask Siri", "“How much did I make today in Tip Tracker?”", "mic.fill", .orange)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button {
                UserDefaults.standard.set(true, forKey: "onboarding.completed")
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
        }
    }

    private func onboardingRow(_ title: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(color, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

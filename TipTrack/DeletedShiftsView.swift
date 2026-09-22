import SwiftUI
import SwiftData

enum ShiftDeletion {
    static func remove(_ shifts: [Shift], context: ModelContext) -> String? {
        let now = Date()
        for shift in shifts { shift.deletedAt = now }
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return "Your shifts were kept unchanged. Please try again. \(error.localizedDescription)"
        }
    }
    static func restore(_ shifts: [Shift], context: ModelContext) -> String? {
        for shift in shifts { shift.deletedAt = nil }
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return "Your shifts were kept unchanged. Please try again. \(error.localizedDescription)"
        }
    }
}
struct DeletedShiftsView: View {
    @Environment(\.modelContext) private var context
    // Fetched by hand instead of with @Query: a live query here kept the store reporting
    // changes, which re-rendered Settings underneath, which rebuilt this view and its
    // query, so the app spun at full CPU until iOS killed it. Nothing can delete a shift
    // while this screen is showing, so reloading on appear and after a restore is enough.
    @State private var shifts: [Shift] = []
    @State private var saveError: String?

    private func reload() {
        let descriptor = FetchDescriptor<Shift>(predicate: #Predicate { $0.deletedAt != nil })
        shifts = ((try? context.fetch(descriptor)) ?? [])
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                ForEach(shifts) { shift in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(shift.date, style: .date)
                            Text(shift.job?.name ?? "Unassigned").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            saveError = ShiftDeletion.restore([shift], context: context)
                            reload()
                        }
                    }
                }
            } footer: { Text("Deleted shifts stay here until you restore them. They are excluded from totals, exports, and widgets.") }
            if shifts.isEmpty { Text("No deleted shifts") }
        }.navigationTitle("Deleted Shifts")
            .saveErrorAlert($saveError)
            .onAppear(perform: reload)
    }
}
struct DeletionUndoBar: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Shift> { $0.deletedAt != nil }, sort: \Shift.deletedAt, order: .reverse)
    private var shifts: [Shift]
    @State private var clock = Date()

    private var latestDeletion: Date? { shifts.first?.deletedAt }
    private var isRecent: Bool {
        guard let latestDeletion else { return false }
        return clock.timeIntervalSince(latestDeletion) < 5
    }

    @State private var saveError: String?

    var body: some View {
        Group {
            if let latest = latestDeletion, isRecent {
                // Same capsule as the "Shift Saved · Undo" toast after logging a shift.
                Button {
                    let batch = shifts.filter { $0.deletedAt == latest }
                    saveError = ShiftDeletion.restore(batch, context: context)
                } label: {
                    HStack(spacing: 8) {
                        Text("Shift Deleted")
                            .foregroundStyle(.white)
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .foregroundStyle(.yellow)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shift deleted. Undo")
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .saveErrorAlert($saveError)
        .animation(.easeOut(duration: 0.2), value: isRecent)
        .task(id: latestDeletion) {
            clock = Date()
            guard let latestDeletion else { return }
            let remaining = max(0, 5 - Date().timeIntervalSince(latestDeletion))
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            clock = Date()
        }
    }
}

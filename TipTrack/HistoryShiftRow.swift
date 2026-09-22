import SwiftData
import SwiftUI

/// A compact dashboard-style card; tapping opens the full shift details.
struct HistoryShiftRow: View {
    let shift: Shift
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var iconSize = 34.0

    private var jobColor: Color {
        shift.job.map { Color(hex: $0.colorHex) } ?? .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shift.job?.iconSymbolName ?? "briefcase.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(jobColor)
                .frame(width: iconSize, height: iconSize)
                .background(jobColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                if textSize.isAccessibilitySize {
                    restaurant
                    total
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        restaurant
                        Spacer(minLength: 0)
                        total
                    }
                }
                workDetails
                if !shift.notes.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "note.text")
                            .accessibilityHidden(true)
                        Text(shift.notes)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(jobColor.opacity(0.65))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .foregroundStyle(.primary)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(jobColor.opacity(colorScheme == .dark ? 0.08 : 0.04))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(jobColor.opacity(0.28), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint("View and edit full shift details")
    }

    private var restaurant: some View {
        Text(shift.job?.name ?? "Unassigned")
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var total: some View {
        Text(shift.totalEarnings, format: .currency(code: "USD"))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Total earnings \(shift.totalEarnings.formatted(.currency(code: "USD")))")
    }

    private var workDetails: some View {
        HStack(spacing: 6) {
            if let hours = shift.hoursWorked, hours > 0 {
                Text("\(hours.formatted(.number.precision(.fractionLength(0...2)))) hrs")
                if let hourly = shift.hourlyAverage {
                    Text("·").accessibilityHidden(true)
                    Text("\(hourly.formatted(.currency(code: "USD")))/hr")
                        .accessibilityLabel("Average earnings \(hourly.formatted(.currency(code: "USD"))) per hour")
                }
            } else {
                Text("Hours not added")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Long-press actions for any shift row: edit, duplicate or delete.
private struct ShiftQuickActions: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let shift: Shift
    let onEdit: () -> Void
    @State private var saveError: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    saveError = ShiftDeletion.remove([shift], context: modelContext)
                }
            }
            .saveErrorAlert($saveError)
    }

    /// Copies the amounts, hours, job and note to a new shift on the same day.
    private func duplicate() {
        let copy = Shift(date: shift.date, creditTip: shift.creditTip, cashTip: shift.cashTip,
            barTipOut: shift.barTipOut, hoursWorked: shift.hoursWorked, hourlyRate: shift.hourlyRate,
            notes: shift.notes, job: shift.job)
        modelContext.insert(copy)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = "The shift could not be duplicated. Please try again. \(error.localizedDescription)"
        }
    }
}

extension View {
    func shiftQuickActions(_ shift: Shift, onEdit: @escaping () -> Void) -> some View {
        modifier(ShiftQuickActions(shift: shift, onEdit: onEdit))
    }
}

import SwiftUI

struct CalendarDayEntryCard: View {
    let jobName: String
    let color: Color
    var symbolName: String = "briefcase.fill"
    let headline: String
    let detail: String
    let actionLabel: String
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbolName).font(.caption).foregroundStyle(color).frame(width: 14)
                Text(jobName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(headline)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack {
                Text(actionLabel).font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: actionLabel == "Logged" ? "checkmark" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.primary.opacity(0.7))
        }
        .foregroundStyle(.primary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.4), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

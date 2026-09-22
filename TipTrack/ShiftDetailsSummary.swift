import SwiftUI

struct ShiftDetailsSummary: View {
    let name: String
    let symbol: String
    let color: Color
    let total: Double
    let hours: Double
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if textSize.isAccessibilitySize {
                identity
                earnings
            } else {
                HStack(alignment: .center, spacing: 12) {
                    identity
                    Spacer(minLength: 4)
                    earnings
                }
            }
            if hours > 0 {
                Text("\(hours.formatted(.number.precision(.fractionLength(0...2)))) hours worked · \((total / hours).formatted(.currency(code: "USD")))/hr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Add hours to see earnings per hour.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.3), lineWidth: 1))
    }

    private var identity: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(name).font(.headline).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var earnings: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("TOTAL EARNINGS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(total, format: .currency(code: "USD"))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

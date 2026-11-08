import SwiftUI
import UIKit

// MARK: - Shared Motion

/// A dollar amount whose digits roll to each new value.
struct RollingCurrencyText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let amount: Double

    var body: some View {
        Text(amount, format: .currency(code: "USD"))
            .contentTransition(reduceMotion ? .identity : .numericText(value: amount))
            // Rolls when a shift is saved, but not when a swipe swaps in another period.
            .transaction(value: amount) { transaction in
                if !reduceMotion && !transaction.disablesAnimations {
                    transaction.animation = .snappy(duration: 0.4)
                }
            }
    }
}

/// Shrinks slightly while pressed, for keys and tappable cards.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

enum CardTurn {
    /// Swaps in another period with no motion: the text and numbers stay put and
    /// just change.
    @MainActor
    static func switchInPlace(_ change: () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

extension View {
    /// Swipe left for the next period and right for the previous one. Runs alongside
    /// taps and vertical scrolling, and ignores drags that are mostly up or down.
    func periodSwipe(canGoForward: Bool = true, onPrevious: @escaping () -> Void,
                     onNext: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    switch CalendarNavigation.swipe(width: value.translation.width,
                        height: value.translation.height,
                        predictedWidth: value.predictedEndTranslation.width) {
                    case .next?:
                        if canGoForward { onNext() }
                        else { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5) }
                    case .previous?: onPrevious()
                    case nil: break
                    }
                }
        )
    }

    /// The card look shared by the dashboard stats. The shadow sits on the background
    /// shape only, so the card's text isn't rendered offscreen to draw it.
    func dashboardCardBackground(colorful: Bool) -> some View {
        background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(
            colorful ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.13),
            lineWidth: colorful ? 1.5 : 1.25
        ))
    }
}

/// A dollar amount at a fixed size. It only becomes a sideways scroller when it is too
/// wide to fit, so on most cards it holds still under a swipe.
struct OverflowCurrency: View {
    let amount: Double
    let size: CGFloat
    let alignment: Alignment

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label
            ScrollView(.horizontal, showsIndicators: false) { label }
                .defaultScrollAnchor(alignment == .trailing ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var label: some View {
        RollingCurrencyText(amount: amount)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Summary Components
struct IncomeRatioBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false
    let credit: Double
    let netCash: Double
    
    private var creditRatio: Double {
        let total = credit + netCash
        return total > 0 ? min(1, max(0, credit / total)) : 0.5
    }

    private var hasEarnings: Bool { credit + netCash > 0 }
    private let creditGradient = LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
    private let cashGradient = LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)

    private var creditPercentage: Int {
        guard credit + netCash > 0 else { return 0 }
        return min(100, max(0, Int((creditRatio * 100).rounded())))
    }

    private var cashPercentage: Int {
        guard credit + netCash > 0 else { return 0 }
        return 100 - creditPercentage
    }
    
    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                ratioLabel(
                    percentage: creditPercentage,
                    title: "Credit",
                    amount: credit,
                    color: .blue,
                    alignment: .leading
                )

                Spacer()

                ratioLabel(
                    percentage: cashPercentage,
                    title: "Cash",
                    amount: netCash,
                    color: .green,
                    alignment: .trailing
                )
            }

            GeometryReader { geo in
                Group {
                    if !hasEarnings {
                        // Gray placeholder, so empty periods keep the same card height.
                        Rectangle().fill(Color.secondary.opacity(0.25))
                    } else if creditRatio >= 1 || creditRatio <= 0 {
                        // One full-width segment: an empty second segment left a gap that
                        // cut off the rounded end.
                        Rectangle().fill(creditRatio >= 1 ? creditGradient : cashGradient)
                    } else {
                        HStack(spacing: 2) {
                            Rectangle()
                                .fill(creditGradient)
                                .frame(width: max(0, (geo.size.width - 2) * creditRatio))
                            Rectangle()
                                .fill(cashGradient)
                        }
                    }
                }
                .transaction(value: creditRatio) { transaction in
                    if !reduceMotion && !transaction.disablesAnimations {
                        transaction.animation = .smooth(duration: 0.5)
                    }
                }
                .mask(alignment: .leading) {
                    Capsule().frame(width: filled ? geo.size.width : 0)
                }
            }
            .frame(height: 8)
            .onAppear {
                guard !filled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(0.1)) { filled = true }
            }
        }
    }

    private func ratioLabel(
        percentage: Int,
        title: String,
        amount: Double,
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text("\(percentage)% \(title)")
                .font(.caption)
                .bold()
                .foregroundStyle(hasEarnings ? color : .secondary)

            Text(amount, format: .currency(code: "USD"))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// The small caption over a stats card, naming the job when the dashboard shows only one.
func periodCaption(_ period: String, jobName: String?) -> String {
    guard let jobName, !jobName.isEmpty else { return period }
    return "\(period) · \(jobName)"
}

// MARK: - Monthly Stats Card
struct MonthlyStatsCard: View {
    @Environment(\.tipTrackColorful) private var colorfulTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shifts: [Shift]
    let month: Date
    /// The job the dashboard is showing, or nil for all jobs.
    var jobName: String? = nil
    let canGoForward: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onOpenHistory: () -> Void
    let onReturnToToday: () -> Void
    
    private struct MonthTotals {
        var credit = 0.0
        var netCash = 0.0
        var tipOut = 0.0
        var count = 0
        var timedHours = 0.0
        var timedEarnings = 0.0
        var total: Double { credit + netCash }
        var averageHourly: Double? { timedHours > 0 ? timedEarnings / timedHours : nil }
    }

    /// Adds up the month in one pass; the card reads several totals on every update.
    private var totals: MonthTotals {
        var totals = MonthTotals()
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return totals }
        for shift in shifts where interval.start <= shift.date && shift.date < interval.end {
            totals.credit += shift.creditEarnings
            totals.netCash += shift.netCash
            totals.tipOut += shift.barTipOut
            totals.count += 1
            if let hours = shift.hoursWorked, hours > 0 {
                totals.timedHours += hours
                totals.timedEarnings += shift.totalEarnings
            }
        }
        return totals
    }

    var body: some View {
        let totals = totals
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                Text(periodCaption(month.formatted(.dateTime.month(.abbreviated).year()), jobName: jobName))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("Monthly Stats")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                }
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("TOTAL EARNINGS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    OverflowCurrency(amount: totals.total, size: 22, alignment: .trailing)
                        .frame(height: 30)

                    periodDetails(count: totals.count, averageHourly: totals.averageHourly)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    periodMetric(title: "Monthly Credit", amount: totals.credit, color: .blue)
                    periodMetric(title: "Monthly Net Cash", amount: totals.netCash, color: .green)
                }

                if totals.tipOut > 0 {
                    Text("Tip Out: \(totals.tipOut, format: .currency(code: "USD"))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                IncomeRatioBar(credit: totals.credit, netCash: totals.netCash)
            }
        }

        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .dashboardCardBackground(colorful: colorfulTheme)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpenHistory)
        .periodSwipe(canGoForward: canGoForward,
            onPrevious: { slide(to: .leading, onPreviousMonth) },
            onNext: { slide(to: .trailing, onNextMonth) })
        .accessibilityAction(named: "View monthly history", onOpenHistory)
        .accessibilityAction(named: "Previous month") { slide(to: .leading, onPreviousMonth) }
        .accessibilityAction(named: "Next month") { if canGoForward { slide(to: .trailing, onNextMonth) } }
        .overlay(alignment: .top) {
            if canGoForward {
                ReturnToTodayBubble(period: "month") { slide(to: .trailing, onReturnToToday) }
                    .offset(y: -10)
            }
        }
    }

    private func slide(to edge: Edge, _ action: @escaping () -> Void) {
        CardTurn.switchInPlace(action)
    }

    private func periodDetails(count: Int, averageHourly: Double?) -> some View {
        HStack(spacing: 5) {
            Text("\(count) \(count == 1 ? "shift" : "shifts")")
            if let averageHourly {
                Text("·")
                Text("\(averageHourly, format: .currency(code: "USD"))/hr")
            }
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func periodMetric(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            OverflowCurrency(amount: amount, size: 20, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.24), lineWidth: 1))
    }

}

// MARK: - Current Week Summary
struct CurrentWeekSummaryCard: View {
    @Environment(\.tipTrackColorful) private var colorfulTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let dateRange: String
    /// The job the dashboard is showing, or nil for all jobs.
    var jobName: String? = nil
    let credit: Double
    let netCash: Double
    let shiftCount: Int
    let averageHourly: Double?
    let canGoForward: Bool
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onOpenWeek: () -> Void
    let onReturnToToday: () -> Void

    private var total: Double {
        credit + netCash
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                Text(periodCaption(dateRange, jobName: jobName))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Weekly Stats")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                }
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("TOTAL EARNINGS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    OverflowCurrency(amount: total, size: 22, alignment: .trailing)
                        .frame(height: 30)

                    periodDetails
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    weeklyMetric(title: "Weekly Credit", amount: credit, color: .blue)
                    weeklyMetric(title: "Weekly Net Cash", amount: netCash, color: .green)
                }

                IncomeRatioBar(credit: credit, netCash: netCash)
            }
        }

        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .dashboardCardBackground(colorful: colorfulTheme)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenWeek)
        .periodSwipe(canGoForward: canGoForward,
            onPrevious: { slide(to: .leading, onPreviousWeek) },
            onNext: { slide(to: .trailing, onNextWeek) })
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the displayed week breakdown")
        .accessibilityAction(named: "Previous week") { slide(to: .leading, onPreviousWeek) }
        .accessibilityAction(named: "Next week") { if canGoForward { slide(to: .trailing, onNextWeek) } }
        .overlay(alignment: .top) {
            if canGoForward {
                ReturnToTodayBubble(period: "week") { slide(to: .trailing, onReturnToToday) }
                    .offset(y: -10)
            }
        }
    }

    private func slide(to edge: Edge, _ action: @escaping () -> Void) {
        CardTurn.switchInPlace(action)
    }

    private func weeklyMetric(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            OverflowCurrency(amount: amount, size: 20, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.24), lineWidth: 1))
    }

    private var periodDetails: some View {
        HStack(spacing: 5) {
            Text("\(shiftCount) \(shiftCount == 1 ? "shift" : "shifts")")
            if let averageHourly {
                Text("·")
                Text("\(averageHourly, format: .currency(code: "USD"))/hr")
            }
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

}

// MARK: - 6. Custom 4x3 Currency Numpad
struct CustomNumpadView: View {
    let onKeyPress: (String) -> Void
    
    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onKeyPress(key)
                        } label: {
                            Text(key)
                                .font(.title2)
                                .bold()
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(UIColor.secondarySystemFill))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.92))
                    }
                }
            }
        }
    }
}

private struct ReturnToTodayBubble: View {
    let period: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Today", systemImage: "arrow.uturn.forward")
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.35)))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Return to current \(period)")
    }
}

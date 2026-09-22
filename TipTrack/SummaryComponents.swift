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
            .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: amount)
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

/// Turns a card edge-on, swaps its content, then turns the new content in from
/// the other side, like flipping between cards in a wallet.
enum CardTurn {
    @MainActor
    static func perform(_ turn: Binding<Double>, forward: Bool, reduceMotion: Bool,
                        change: @escaping () -> Void) {
        guard !reduceMotion else {
            change()
            return
        }
        let direction: Double = forward ? 1 : -1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeIn(duration: 0.18)) {
            turn.wrappedValue = -90 * direction
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                change()
                turn.wrappedValue = 90 * direction
            }
            // Same spring as the wallet-card flip this is modeled on.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                turn.wrappedValue = 0
            }
        }
    }
}

extension View {
    func cardTurn(_ degrees: Double) -> some View {
        rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
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
                .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: creditRatio)
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

// MARK: - Monthly Stats Card
struct MonthlyStatsCard: View {
    @Environment(\.tipTrackColorful) private var colorfulTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn: Double = 0
    let shifts: [Shift]
    let month: Date
    let canGoForward: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onOpenHistory: () -> Void
    let onReturnToToday: () -> Void
    
    private var selectedMonthShifts: [Shift] {
        shifts.filter {
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }
    
    private var monthlyCredit: Double {
        selectedMonthShifts.reduce(0) { $0 + $1.creditEarnings }
    }
    
    private var monthlyNetCash: Double {
        selectedMonthShifts.reduce(0) { $0 + $1.netCash }
    }
    
    private var monthlyTipOut: Double {
        selectedMonthShifts.reduce(0) { $0 + $1.barTipOut }
    }
    
    private var monthlyTotal: Double {
        monthlyCredit + monthlyNetCash
    }

    private var monthlyAverageHourly: Double? {
        let timedShifts = selectedMonthShifts.filter { ($0.hoursWorked ?? 0) > 0 }
        let hours = timedShifts.reduce(0) { $0 + ($1.hoursWorked ?? 0) }
        let earnings = timedShifts.reduce(0) { $0 + $1.totalEarnings }
        return hours > 0 ? earnings / hours : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { slide(to: .leading, onPreviousMonth) } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .frame(width: 30, height: 30)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                Text(month.formatted(.dateTime.month(.abbreviated).year()))
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        RollingCurrencyText(amount: monthlyTotal)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .defaultScrollAnchor(.trailing)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)

                    periodDetails(count: selectedMonthShifts.count, averageHourly: monthlyAverageHourly)
                }
                Button { slide(to: .trailing, onNextMonth) } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .frame(width: 30, height: 30)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
                .accessibilityLabel("Next month")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    periodMetric(title: "Monthly Credit", amount: monthlyCredit, color: .blue)
                    periodMetric(title: "Monthly Net Cash", amount: monthlyNetCash, color: .green)
                }

                if monthlyTipOut > 0 {
                    Text("Tip Out: \(monthlyTipOut, format: .currency(code: "USD"))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                IncomeRatioBar(credit: monthlyCredit, netCash: monthlyNetCash)
            }
        }

        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(
            colorfulTheme ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.13),
            lineWidth: colorfulTheme ? 1.5 : 1.25
        ))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        .cardTurn(turn)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpenHistory)
        .accessibilityAction(named: "View monthly history", onOpenHistory)
        .overlay(alignment: .top) {
            if canGoForward {
                ReturnToTodayBubble(period: "month") { slide(to: .trailing, onReturnToToday) }
                    .offset(y: -10)
            }
        }
    }

    private func slide(to edge: Edge, _ action: @escaping () -> Void) {
        CardTurn.perform($turn, forward: edge == .trailing, reduceMotion: reduceMotion, change: action)
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

            ScrollView(.horizontal, showsIndicators: false) {
                RollingCurrencyText(amount: amount)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }
            .scrollBounceBehavior(.basedOnSize)
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
    @State private var turn: Double = 0
    let dateRange: String
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
                Button { slide(to: .leading, onPreviousWeek) } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .frame(width: 30, height: 30)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Previous week")

                VStack(alignment: .leading, spacing: 2) {
                Text(dateRange)
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        RollingCurrencyText(amount: total)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .defaultScrollAnchor(.trailing)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)

                    periodDetails
                }
                Button { slide(to: .trailing, onNextWeek) } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .frame(width: 30, height: 30)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.35)
                .accessibilityLabel("Next week")
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
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(
            colorfulTheme ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.13),
            lineWidth: colorfulTheme ? 1.5 : 1.25
        ))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        .cardTurn(turn)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenWeek)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the displayed week breakdown")
        .overlay(alignment: .top) {
            if canGoForward {
                ReturnToTodayBubble(period: "week") { slide(to: .trailing, onReturnToToday) }
                    .offset(y: -10)
            }
        }
    }

    private func slide(to edge: Edge, _ action: @escaping () -> Void) {
        CardTurn.perform($turn, forward: edge == .trailing, reduceMotion: reduceMotion, change: action)
    }

    private func weeklyMetric(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            ScrollView(.horizontal, showsIndicators: false) {
                RollingCurrencyText(amount: amount)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }
            .scrollBounceBehavior(.basedOnSize)
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

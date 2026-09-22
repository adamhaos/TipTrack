import SwiftUI
import UIKit

/// Two comet-like streaks chase each other around the button's outline.
/// Each streak is stacked dashes sharing one head, so the tail fades out behind it.
struct AnimatedLogButtonBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    let color: Color
    var cornerRadius: CGFloat = 18

    private static let loopDuration = 14.0
    // Many faint layers blend into a smooth fade instead of visible steps.
    private static let tailLayers = 10

    var body: some View {
        GeometryReader { geometry in
            let lineWidth: CGFloat = 1.5
            // Sit just inside the button's edge so the streak never pokes past it.
            let inset = lineWidth / 2 + 0.5
            let width = max(0, geometry.size.width - inset * 2)
            let height = max(0, geometry.size.height - inset * 2)
            let radius = max(0, min(cornerRadius - inset, min(width, height) / 2))
            let perimeter = 2 * (width + height - 4 * radius) + 2 * .pi * radius
            // One dash per half perimeter gives exactly two streaks, opposite each other.
            let halfPerimeter = max(1, perimeter / 2)
            let streakLength = halfPerimeter * 0.5

            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { context in
                let phase = reduceMotion ? 0 :
                    -context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.loopDuration) / Self.loopDuration * perimeter

                ZStack {
                    ForEach(0..<Self.tailLayers, id: \.self) { layer in
                        // Shorter layers overlap near the head, so it's brightest there.
                        let length = streakLength * CGFloat(layer + 1) / CGFloat(Self.tailLayers)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                            .inset(by: inset)
                            .stroke(
                                highlight(0.7).opacity(0.08),
                                // Butt caps: round caps on every layer bulge into uneven beads.
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                                   dash: [length, halfPerimeter - length],
                                                   dashPhase: phase - streakLength + length)
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Blend toward white to retain the current button's hue in every theme.
    private func highlight(_ amount: CGFloat) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Color(red: red + (1 - red) * amount,
                     green: green + (1 - green) * amount,
                     blue: blue + (1 - blue) * amount)
    }
}

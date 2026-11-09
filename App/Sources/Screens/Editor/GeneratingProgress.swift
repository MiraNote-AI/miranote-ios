import SwiftUI

/// A bar under the sticker spinner (#185). The backend reports no progress,
/// so the bar runs on the expected time: most of the way by about 8 s (a
/// typical beta sticker), then creeping, never full while still waiting.
/// It goes with the spinner when the stickers land or the wait fails.
struct GeneratingProgress: View {
    @State private var start = Date()

    /// 0.95 * (1 - e^(-t/3)): about 88% at 8 s, 95% at most.
    static func fraction(after seconds: TimeInterval) -> Double {
        0.95 * (1 - exp(-max(0, seconds) / 3))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let fraction = Self.fraction(after: context.date.timeIntervalSince(start))
            Capsule()
                .fill(Palette.ink.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: 160 * fraction)
                }
                .frame(width: 160, height: 6)
                .accessibilityElement()
                .accessibilityLabel("Making the sticker")
                .accessibilityValue(Text("\(Int(fraction * 100)) percent"))
                .accessibilityIdentifier("sticker.progress")
        }
    }
}

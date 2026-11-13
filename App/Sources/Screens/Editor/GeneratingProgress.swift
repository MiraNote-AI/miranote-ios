import SwiftUI

/// A bar under the sticker spinner (#185). The backend reports no progress,
/// so the bar runs on the expected time: most of the way by about 8 s (a
/// typical beta sticker), then creeping, never full while still waiting.
/// When the stickers land it runs to full in `fill`, then goes with the
/// spinner; on a failed wait it just goes.
struct GeneratingProgress: View {
    /// When this sticker started. The scene keeps it, so the bar does not
    /// start over when the Make tab or the keyboard rebuilds this view.
    let since: Date
    /// When the stickers landed: the bar runs from where it stood to full.
    let finishedAt: Date?

    static let fill: TimeInterval = {
        #if DEBUG
        // UI tests stretch it with `-STICKER_FILL_MS <ms>` to read the run to full.
        let override = UserDefaults.standard.integer(forKey: "STICKER_FILL_MS")
        if override > 0 { return Double(override) / 1000 }
        #endif
        return 0.2
    }()

    /// 0.95 * (1 - e^(-t/3)): about 88% at 8 s, 95% at most.
    static func fraction(after seconds: TimeInterval) -> Double {
        0.95 * (1 - exp(-max(0, seconds) / 3))
    }

    private func fraction(at now: Date) -> Double {
        guard let finishedAt else { return Self.fraction(after: now.timeIntervalSince(since)) }
        let reached = Self.fraction(after: finishedAt.timeIntervalSince(since))
        let filled = min(1, now.timeIntervalSince(finishedAt) / Self.fill)
        return reached + (1 - reached) * filled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let fraction = fraction(at: context.date)
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
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("sticker.progress")
        }
    }
}

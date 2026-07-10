import SwiftUI

/// A static audio waveform -- vertical bars with a fixed, natural-looking
/// height pattern (deterministic for snapshot QA).
struct WaveformView: View {
    var barCount: Int = 40
    var tint: Color = Palette.ink
    var maxHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { idx in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: height(idx))
            }
        }
    }

    private func height(_ idx: Int) -> CGFloat {
        let pattern: [CGFloat] = [0.3, 0.55, 0.8, 1, 0.6, 0.35, 0.7, 0.95, 0.5, 0.25, 0.65, 0.85, 0.45, 0.2]
        return max(4, pattern[idx % pattern.count] * maxHeight)
    }
}

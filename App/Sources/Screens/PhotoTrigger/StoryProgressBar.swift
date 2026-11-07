import SwiftUI

/// The story's top bar: one thin segment per photo, the played ones full,
/// the current one filling as it plays.
struct StoryProgressBar: View {
    let count: Int
    let index: Int
    /// How far through the current photo, 0...1.
    let fraction: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { segment in
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.white)
                                .frame(width: proxy.size.width * fill(for: segment))
                        }
                    }
                    .frame(height: 2.5)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityElement()
        .accessibilityLabel("Photo \(index + 1) of \(count)")
    }

    private func fill(for segment: Int) -> Double {
        if segment < index { return 1 }
        if segment > index { return 0 }
        return min(max(fraction, 0), 1)
    }
}

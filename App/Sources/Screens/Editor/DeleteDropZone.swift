import SwiftUI

/// Handoff screen 22: while an element is dragged, the whole bottom dock
/// turns into the delete zone -- everything below the canvas deletes, so
/// the sign covers all of it. It deepens once the finger is over it. Purely
/// a sign: the canvas decides on release, so it takes no touches.
struct DeleteDropZone: View {
    let armed: Bool

    /// The handoff's #D86C5D reads at 2.3:1 on its blush; darkened along its
    /// hue to pass 4.5:1 on both blushes (6.6:1 resting, 5.2:1 armed).
    private static let red = Color(hex: 0x7F2E22)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Self.red)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.warmWhite))
            VStack(alignment: .leading, spacing: 2) {
                // The canvas clips the dragged element at its edge, so once
                // the finger is over the zone the words carry the moment.
                Text(armed ? "Release to delete" : "Drop here to delete")
                    .font(Sans.font(size: 14, weight: 600))
                    .foregroundStyle(Self.red)
                Text(armed ? "Undo brings it back" : "Release outside the canvas")
                    .font(Sans.font(size: 11, weight: 500))
                    .foregroundStyle(Palette.ink.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28)
                // Opaque: the dock's controls must not ghost through.
                .fill(Color(hex: armed ? 0xEDB8AE : 0xF3D5CF))
                .overlay(RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Self.red.opacity(armed ? 0.6 : 0.2), lineWidth: 1))
        )
        .scaleEffect(armed ? 1.03 : 1)
        .padding(.horizontal, Metrics.chromeInset)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canvas.deleteZone")
    }
}

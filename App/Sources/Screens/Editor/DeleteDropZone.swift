import SwiftUI

/// Handoff screen 22: while an element is dragged, the bottom dock turns
/// into the delete zone. It deepens once the finger is over it. Purely a
/// sign -- the canvas decides on release, so it takes no touches.
struct DeleteDropZone: View {
    let armed: Bool

    /// The handoff's #D86C5D reads at 2.3:1 on its blush; darkened along its
    /// hue to pass 4.5:1.
    private static let red = Color(hex: 0xA33F30)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Self.red)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.warmWhite))
            VStack(alignment: .leading, spacing: 2) {
                Text("Drop here to delete")
                    .font(Sans.font(size: 14, weight: 600))
                    .foregroundStyle(Self.red)
                Text("Release outside the canvas")
                    .font(Sans.font(size: 11, weight: 500))
                    .foregroundStyle(Palette.ink.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 54)
        .background(
            Capsule()
                .fill(Color(hex: armed ? 0xEDB8AE : 0xF3D5CF).opacity(0.95))
                .overlay(Capsule().strokeBorder(Self.red.opacity(armed ? 0.6 : 0.2), lineWidth: 1))
        )
        .scaleEffect(armed ? 1.03 : 1)
        .padding(.horizontal, Metrics.screenPadding)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canvas.deleteZone")
    }
}

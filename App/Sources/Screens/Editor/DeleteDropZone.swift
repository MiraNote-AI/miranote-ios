import SwiftUI

/// Handoff screen 22: while an element is dragged, the composer slot itself
/// becomes the delete zone -- a translucent blush row over the composer,
/// clipped to its capsule, so the composer ghosts through. The tool bar stays
/// in view. Purely a sign: the canvas decides on release (anywhere below the
/// card deletes), so it takes no touches. Over the zone, the lifted
/// element's own frame turns red (LiftedElementLayer).
///
/// The handoff draws a microphone in the icon well -- a copy of the sound
/// option row it was made from; a bin is what this row means.
struct DeleteDropZone: View {
    /// The handoff's coral; 2.3:1 on the blush, as drawn (fidelity bar,
    /// 2026-10-15) -- the second line carries the meaning at 4.6:1.
    static let red = Color(hex: 0xD86C5D)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // The row is drawn 368 x 55 at (-1, -2.6) of the 342 x 54
                // composer, so its right end is cut by the capsule.
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: 0xF3D5CF).opacity(0.88))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.75), lineWidth: 1.2))
                    .frame(width: geo.size.width + 26.2, height: 55.35)
                    .offset(x: -1, y: -2.59)
                Circle()
                    .fill(Palette.paper)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color(hex: 0x29221F))
                    )
                    .offset(x: 12.24, y: 5.83)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Drop here to delete")
                        .font(Sans.font(size: 14.5, weight: 700))
                        .foregroundStyle(Self.red)
                        .frame(height: 18)
                    Text("Release outside the canvas")
                        .font(Sans.font(size: 11, weight: 500))
                        .foregroundStyle(Color(hex: 0x7D786F))
                        .frame(height: 13)
                        .padding(.top, 3.6)
                }
                .offset(x: 60.37, y: 7.04)
            }
        }
        .frame(height: 54)
        .clipShape(Capsule())
        .padding(.horizontal, Metrics.chromeInset)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canvas.deleteZone")
    }
}

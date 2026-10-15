import MiraNoteKit
import SwiftUI

/// Handoff screen 07: what Mira changed, what she kept, and the choice --
/// a 96 pt glass sheet over the bottom of the canvas card, 4 pt wider than
/// the card on each side. It waits for Keep or Revert; an edit or a new ask
/// also moves on (MiraCanvasCoordinator.canvasDidChange).
struct MiraResultSheet: View {
    let receipt: MiraReceipt
    /// A turn that changed nothing offers no Revert.
    let canRevert: Bool
    var onRevert: () -> Void
    var onKeep: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 24)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(receipt.changed)
                .font(Sans.font(size: 13, weight: 700))
                .foregroundStyle(Palette.ink)
                .frame(height: 16)
                .padding(.top, 12)
                .accessibilityIdentifier("mira.receipt")
            Text(receipt.kept)
                .font(Sans.font(size: 10, weight: 400))
                .foregroundStyle(Self.kept)
                .frame(height: 13)
                .padding(.top, 5)
                .accessibilityIdentifier("mira.kept")
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if canRevert {
                    Button(action: onRevert) {
                        Text("Revert")
                            .font(Sans.font(size: 10, weight: 700))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 78, height: 30)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.58))
                                    .overlay(Capsule().strokeBorder(Self.revertRim, lineWidth: 1))
                            )
                            .minimumHitTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mira.revert")
                }
                Button(action: onKeep) {
                    Text("Keep")
                        .font(Sans.font(size: 10, weight: 700))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 82, height: 30)
                        .background(Capsule().fill(Palette.ink))
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mira.keep")
            }
            .padding(.top, 7)
        }
        .lineLimit(1)
        .padding(.leading, 17)
        .padding(.trailing, 19)
        .frame(height: 96, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GlassSurface(
                shape: Self.shape,
                tint: Color.white.opacity(0.66),
                rim: Color.white.opacity(0.5),
                highlight: false,
                shadowOpacity: 0.1,
                shadowRadius: 7,
                shadowY: 12
            )
        )
        .accessibilityElement(children: .contain)
    }

    /// The handoff's warm grey for the kept line.
    private static let kept = Color(hex: 0x8F7E76)
    private static let revertRim = Color(hex: 0x8F7E76).opacity(0.22)
}

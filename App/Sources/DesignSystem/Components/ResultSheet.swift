import MiraNoteKit
import SwiftUI

/// The applied-result sheet -- Mira's change (screen 07) and an attached
/// take ("Sound is attached.", screen 09): a 104 pt frosted white card,
/// r24, floating inside the canvas card like every sheet over it (the
/// caller pads it onto the chrome line), with a Bold 15 headline, a
/// Regular 12 line in #8F7E76, and Revert / Keep pills, 32 tall, at its
/// trailing edge. It waits for the choice; nothing keeps it by timer.
struct ResultSheet: View {
    static let height: CGFloat = 104

    let title: String
    let detail: String
    var titleID: String?
    var detailID: String?
    /// A change that changed nothing offers no Revert.
    var canRevert = true
    var revertID: String
    var keepID: String
    var onRevert: () -> Void
    var onKeep: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 24)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy: title)
                .font(Sans.font(size: 15, weight: 700))
                .foregroundStyle(Palette.ink)
                .padding(.top, 13)
                .accessibilityIdentifier(titleID ?? "")
            Text(copy: detail)
                .font(Sans.font(size: 12, weight: 400))
                .foregroundStyle(Self.warmGrey)
                .padding(.top, 5)
                .accessibilityIdentifier(detailID ?? "")
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if canRevert {
                    Button(action: onRevert) {
                        Text("Revert")
                            .font(Sans.font(size: 14, weight: 700))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 84, height: 32)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.58))
                                    .overlay(Capsule().strokeBorder(Self.warmGrey.opacity(0.22), lineWidth: 1))
                            )
                            .minimumHitTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(revertID)
                }
                Button(action: onKeep) {
                    Text("Keep")
                        .font(Sans.font(size: 14, weight: 700))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 84, height: 32)
                        .background(Capsule().fill(Palette.ink))
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(keepID)
            }
            .padding(.bottom, 12)
        }
        .lineLimit(1)
        .padding(.leading, 17)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height, alignment: .top)
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

    /// The handoff's warm grey for the detail line.
    private static let warmGrey = Color(hex: 0x8F7E76)
}

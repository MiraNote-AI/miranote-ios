import SwiftUI

/// The handoff's applied-result sheet (screen 09, "Sound is attached."): a
/// 96 pt frosted white card, r24, with a Bold 13 headline, a Regular 10
/// line in #8F7E76, and Revert (78) / Keep (82) pills, 30 tall, at its
/// trailing edge. The caller pads it 16 from the screen edge.
struct ResultSheet: View {
    static let height: CGFloat = 96

    let title: String
    let detail: String
    var revertID: String
    var keepID: String
    var onRevert: () -> Void
    var onKeep: () -> Void

    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Sans.font(size: 13, weight: 700))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 8)
            Text(detail)
                .font(Sans.font(size: 10, weight: 400))
                .foregroundStyle(Color(hex: 0x8F7E76))
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action: onRevert) {
                    Text("Revert")
                        .font(Sans.font(size: 10, weight: 700))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 78, height: 30)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.58))
                                .overlay(Capsule().strokeBorder(Color(hex: 0x8F7E76).opacity(0.22), lineWidth: 1))
                        )
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(revertID)
                Button(action: onKeep) {
                    Text("Keep")
                        .font(Sans.font(size: 10, weight: 700))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 82, height: 30)
                        .background(Capsule().fill(Palette.ink))
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(keepID)
            }
        }
        .padding(.top, 13)
        .padding(.leading, 17)
        .padding(.trailing, 19)
        .padding(.bottom, 13)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Self.shape
                .fill(.ultraThinMaterial)
                .overlay(Self.shape.fill(Color.white.opacity(0.66)))
                .overlay(Self.shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                .shadow(color: Palette.ink.opacity(0.1), radius: 7, y: 12)
        )
    }
}

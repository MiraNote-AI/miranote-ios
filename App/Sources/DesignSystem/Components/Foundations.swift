import SwiftUI

/// The three ways to add to a memory page -- the bottom "instrument panel".
/// Sticker creation lives inside the Image panel (v2.1), not on the bar.
enum EditorMode: String, CaseIterable, Identifiable {
    case sound, text, image

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .sound: return "waveform"
        case .text: return "textformat"
        case .image: return "photo"
        }
    }
}

extension View {
    /// Warm-paper full-bleed background, locked to the light appearance the
    /// Flow 7 design assumes.
    func screenBackground() -> some View {
        background(Palette.paper.ignoresSafeArea())
            .preferredColorScheme(.light)
    }
}

/// A soft warm gradient blob used to stand in for a photo, matching the
/// gradient placeholders the Figma frames use.
struct GradientPlaceholder: View {
    var tint: Color = Palette.tan
    var corner: CGFloat = Metrics.imageCorner

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Palette.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: corner)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.55), Palette.cardFill.opacity(0.1)],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        )
                    )
                    .blendMode(.multiply)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Palette.onInk.opacity(0.35))
                    .frame(width: 70, height: 70)
                    .blur(radius: 26)
                    .padding(28)
            }
            .overlay {
                // A quiet glyph so a missing photo reads as "a photo goes
                // here", not as a broken block. Scales with the slot.
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    Image(systemName: "photo")
                        .font(.system(size: max(12, min(26, side * 0.2)), weight: .light))
                        .foregroundStyle(Palette.taupe.opacity(0.45))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

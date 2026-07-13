import SwiftUI

/// The bottom "instrument panel": three ways to add to a memory page, plus
/// the library of saved images/stickers (one Favorites group for now, more
/// groups later). Sticker creation lives inside the Image panel (v2.1),
/// not on the bar.
enum EditorMode: String, CaseIterable, Identifiable {
    case sound, text, image, library

    var id: String { rawValue }

    /// User-facing labels. The saved-material library shows as "Saved":
    /// "Library" on screen would collide with the Image panel's photo-library
    /// chip, which keeps the standard iOS wording.
    var title: String {
        self == .library ? "Saved" : rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .sound: return "waveform"
        case .text: return "textformat"
        case .image: return "photo"
        case .library: return "square.grid.2x2"
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
                        .accessibilityIdentifier("image.placeholder")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

import SwiftUI

/// The handoff's "Mira dictation strip": a 30 pt capsule with the forest
/// mic well, "Mira Dictation", a detail line and "Hold". One component for
/// every surface that dictates -- the text accessory (screens 11-20) and the
/// Mira canvas chat (screen 06); the two only differ in their glass.
/// Press and release are reported once each; callers decide what a press
/// means and attach their own accessibility.
struct DictationStrip: View {
    enum Surface {
        /// white@0.54 with a white rim (the text accessory over the page).
        case page
        /// forest@0.06 with a dark rim (riding the dark keyboard, screen 06).
        case keyboard
    }

    var surface: Surface
    let listening: Bool
    /// "accurate voice-to-text" at rest, "Listening...", or why nothing landed.
    let detail: String
    var action = "Hold"
    var onPress: () -> Void
    var onRelease: () -> Void

    @State private var pressed = false

    var body: some View {
        HStack(spacing: 0) {
            Image("mira.dictation.mic")
                .renderingMode(.template)
                .resizable()
                .frame(width: 12, height: 12)
                .foregroundStyle(Palette.onInk)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.forest))
                .scaleEffect(listening ? 1.15 : 1)
                .animation(listening ? .easeInOut(duration: 0.6).repeatForever() : .default, value: listening)
                .padding(.trailing, 8)
            Text("Mira Dictation")
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Palette.ink)
                .frame(width: 104, alignment: .leading)
                .padding(.trailing, 2)
            Text(detail)
                .font(Sans.font(size: 10, weight: 400))
                .foregroundStyle(listening ? Palette.forest : Self.warmGrey)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(action)
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Palette.forest)
                .frame(minWidth: 34)
                .padding(.trailing, 13)
        }
        .padding(.leading, 9)
        .frame(height: 30)
        .background(background)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    onPress()
                }
                .onEnded { _ in
                    pressed = false
                    onRelease()
                }
        )
    }

    @ViewBuilder private var background: some View {
        switch surface {
        case .page:
            // No material here: over the scrimmed page a blur reads whiter
            // than the drawn white@0.54 (screens 11-20).
            Capsule()
                .fill(Color.white.opacity(0.54))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
                .shadow(color: Palette.ink.opacity(0.10), radius: 6, y: 12)
        case .keyboard:
            GlassSurface(
                shape: Capsule(),
                tint: Palette.forest.opacity(0.06),
                rim: Color.black.opacity(0.42),
                highlight: false,
                shadowOpacity: 0.10, shadowRadius: 6, shadowY: 12
            )
        }
    }

    /// The handoff's warm grey detail line (#8F7E76).
    private static let warmGrey = Color(hex: 0x8F7E76)
}

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
    /// The system took the touch (the first mic-permission alert, a call,
    /// the app leaving): the press ends without a release.
    var onCancel: () -> Void

    @State private var pressed = false
    /// Counts presses, so a late cancel never ends a newer press.
    @State private var pressCount = 0
    /// The press as the gesture system sees it: it lets go even when
    /// onEnded never comes.
    @GestureState private var touching = false

    var body: some View {
        HStack(spacing: 0) {
            Image("mira.dictation.mic")
                .renderingMode(.template)
                .resizable()
                .frame(width: 14, height: 14)
                .foregroundStyle(Palette.onInk)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.forest))
                .scaleEffect(listening ? 1.15 : 1)
                .animation(listening ? .easeInOut(duration: 0.6).repeatForever() : .default, value: listening)
                .padding(.trailing, 8)
            Text("Mira Dictation")
                .font(Sans.font(size: 13, weight: 700))
                .foregroundStyle(Palette.ink)
                .fixedSize()
                .padding(.trailing, 12)
            Text(detail)
                .font(Sans.font(size: 13, weight: 400))
                .foregroundStyle(listening ? Palette.forest : Self.warmGrey)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(action)
                .font(Sans.font(size: 14, weight: 700))
                .foregroundStyle(Palette.forest)
                .frame(minWidth: 34)
                .padding(.trailing, 13)
        }
        .padding(.leading, 7)
        // 36 tall for 13-14 pt words (the handoff's 30 held 10 pt).
        .frame(height: 36)
        .background(background)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    pressCount += 1
                    onPress()
                }
                .onEnded { _ in
                    pressed = false
                    onRelease()
                }
        )
        .onChange(of: touching) { _, down in
            guard !down else { return }
            let press = pressCount
            Task { @MainActor in
                // onEnded, when it comes, has run by now -- and a new press
                // that began meanwhile is not this one's to cancel.
                guard pressed, pressCount == press else { return }
                pressed = false
                onCancel()
            }
        }
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

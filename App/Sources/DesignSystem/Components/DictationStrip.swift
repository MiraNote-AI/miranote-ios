import SwiftUI

/// The handoff's "Mira dictation strip" of the Mira canvas chat (screen
/// 06): a 30 pt capsule with the forest mic well, "Mira Dictation", a detail
/// line and "Hold", riding the dark keyboard. Press and release are reported
/// once each; callers decide what a press means and attach their own
/// accessibility.
struct DictationStrip: View {
    let listening: Bool
    /// "accurate voice-to-text" at rest, "Listening...", or why nothing landed.
    let detail: String
    var action = "Hold"
    var onPress: () -> Void
    var onRelease: () -> Void
    /// The system took the touch (the first mic-permission alert, a call,
    /// the app leaving): the press ends without a release.
    var onCancel: () -> Void

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
            Text(copy: action)
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
        .holdToTalk(onPress: onPress, onRelease: onRelease, onCancel: onCancel)
    }

    /// forest@0.06 with a dark rim, riding the dark keyboard.
    private var background: some View {
        GlassSurface(
            shape: Capsule(),
            tint: Palette.forest.opacity(0.06),
            rim: Color.black.opacity(0.42),
            highlight: false,
            shadowOpacity: 0.10, shadowRadius: 6, shadowY: 12
        )
    }

    /// The handoff's warm grey detail line (#8F7E76).
    private static let warmGrey = Color(hex: 0x8F7E76)
}

extension View {
    /// Hold to talk on any mic: press and release are reported once each.
    /// The system taking the touch (the first mic-permission alert, a call,
    /// Control Center, the app leaving) ends the press without a release:
    /// `onCancel`.
    func holdToTalk(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(HoldToTalk(onPress: onPress, onRelease: onRelease, onCancel: onCancel))
    }
}

private struct HoldToTalk: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    var onCancel: () -> Void

    @State private var pressed = false
    /// Counts presses, so a late cancel never ends a newer press.
    @State private var pressCount = 0
    /// The press as the gesture system sees it: it lets go even when
    /// onEnded never comes.
    @GestureState private var touching = false
    #if DEBUG
    /// The test hook took this touch: the finger, still down, presses
    /// nothing more until it lifts.
    @State private var taken = false
    #endif

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { _ in
                        guard !pressed else { return }
                        #if DEBUG
                        guard !taken else { return }
                        #endif
                        pressed = true
                        pressCount += 1
                        onPress()
                        #if DEBUG
                        cancelTouchIfAsked(press: pressCount)
                        #endif
                    }
                    .onEnded { _ in
                        // A press the system took (or the test hook) is over.
                        guard pressed else { return }
                        pressed = false
                        onRelease()
                    }
            )
            .onChange(of: touching) { _, down in
                guard !down else { return }
                #if DEBUG
                taken = false
                #endif
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

    #if DEBUG
    /// -UITEST only: `-STRIP_TOUCH_CANCEL_AFTER <ms>` takes the press's touch
    /// away mid-press, as the system does (#218): the cancel branch runs and
    /// the finger's later lift reports nothing.
    private func cancelTouchIfAsked(press: Int) {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        let delay = UserDefaults.standard.integer(forKey: "STRIP_TOUCH_CANCEL_AFTER")
        guard delay > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delay))
            guard pressed, pressCount == press else { return }
            pressed = false
            taken = true
            onCancel()
        }
    }
    #endif
}

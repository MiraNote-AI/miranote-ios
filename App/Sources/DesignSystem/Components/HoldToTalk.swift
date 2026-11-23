import SwiftUI

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

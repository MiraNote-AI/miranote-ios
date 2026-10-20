import SwiftUI

/// The handoff's 54 pt glass composer: its leading content from x 17 and an
/// ink 52x34 action pill (Go, Apply, Add; Generate is 74) at x 271 of 342 --
/// 19 from the trailing edge, vertically centered. The canvas, the
/// Background tool and every tool page (screens 23-36) use this one.
struct ComposerCapsule<Leading: View>: View {
    let action: String
    let actionID: String
    let canAct: Bool
    var actionWidth: CGFloat = 52
    let onAct: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 8) {
            leading()
            Button(action: onAct) {
                Text(action)
                    .font(.miraComposerAction)
                    .foregroundStyle(Palette.onInk)
                    // A margin inside the pill for the 16 pt label.
                    .padding(.horizontal, 14)
                    .frame(minWidth: actionWidth)
                    .frame(height: 34)
                    .background(Capsule().fill(Palette.ink))
                    .minimumHitTarget()
            }
            // The handoff draws the pill in full ink at rest: it stays
            // disabled with nothing to send, but is not greyed out.
            .buttonStyle(ComposerActionStyle())
            .disabled(!canAct)
            .accessibilityIdentifier(actionID)
        }
        .padding(.leading, 17)
        .padding(.trailing, 19)
        .frame(height: 54)
        .background(GlassCapsule())
        .padding(.horizontal, Metrics.chromeInset)
    }
}

/// The composer while the Background tool is open (screen 05): words that
/// describe a backdrop, and Apply asks Mira to paint it for this page; with
/// no words Apply returns to the canvas. Never a dead pill: while Apply's
/// painting is on its way it reads Stop.
struct BackgroundApplyBar: View {
    @Binding var words: String
    var focus: FocusState<Bool>.Binding
    var painting: Bool
    /// The trimmed words, "" when none were typed.
    var onApply: (String) -> Void
    var onStop: () -> Void
    /// When Apply started: Stop sits on the same spot, so a double tap must
    /// not stop the painting it just started.
    @State private var appliedAt = Date.distantPast

    var body: some View {
        ComposerCapsule(action: painting ? "Stop" : "Apply", actionID: "background.apply", canAct: true,
                        onAct: painting ? stop : apply) {
            TextField("", text: $words, prompt: Text("Apply to this page").foregroundStyle(Palette.muted))
                .font(.miraComposer)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.go)
                .focused(focus)
                .onSubmit(apply)
                .disabled(painting)
                .accessibilityLabel("Describe a background for this page")
                .accessibilityIdentifier("background.apply.input")
        }
    }

    private func apply() {
        guard !painting else { return }
        let sent = words.trimmingCharacters(in: .whitespacesAndNewlines)
        words = ""
        focus.wrappedValue = false
        appliedAt = Date()
        onApply(sent)
    }

    private func stop() {
        guard Date().timeIntervalSince(appliedAt) > 0.5 else { return }
        onStop()
    }
}

/// The composer's action pill as drawn: no disabled dimming, a light press.
private struct ComposerActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
    }
}

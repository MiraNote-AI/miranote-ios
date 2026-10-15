import SwiftUI

/// The handoff's 54 pt glass composer: its leading content from x 17 and an
/// ink 52x34 action pill (Go, Apply) at x 271 of 342 -- 19 from the
/// trailing edge, vertically centered.
struct ComposerCapsule<Leading: View>: View {
    let action: String
    let actionID: String
    let canAct: Bool
    let onAct: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 8) {
            leading()
            Button(action: onAct) {
                Text(action)
                    .font(.miraComposerAction)
                    .foregroundStyle(Palette.onInk)
                    .frame(minWidth: 52)
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
/// describe a backdrop, and Apply asks Mira to paint it for this page.
struct BackgroundApplyBar: View {
    @Binding var words: String
    var focus: FocusState<Bool>.Binding
    var canApply: Bool
    var onApply: (String) -> Void

    var body: some View {
        ComposerCapsule(action: "Apply", actionID: "background.apply", canAct: canApply && !trimmed.isEmpty,
                        onAct: apply) {
            TextField("", text: $words, prompt: Text("Apply to this page").foregroundStyle(Palette.muted))
                .font(.miraComposer)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.go)
                .focused(focus)
                .onSubmit(apply)
                .accessibilityLabel("Describe a background for this page")
                .accessibilityIdentifier("background.apply.input")
        }
    }

    private var trimmed: String { words.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func apply() {
        guard canApply, !trimmed.isEmpty else { return }
        let sent = trimmed
        words = ""
        focus.wrappedValue = false
        onApply(sent)
    }
}

/// The composer's action pill as drawn: no disabled dimming, a light press.
struct ComposerActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
    }
}

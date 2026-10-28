import MiraNoteKit
import SwiftUI

/// Handoff screen 06, the Mira canvas chat: a frosted scrim over the canvas
/// and the dock, the question being typed in a dark capsule, Mira's panel
/// with the four quick actions, and the "Mira Dictation" strip riding on the
/// keyboard. The nav pills stay on top: Canvas (on glass) and Done both
/// close the chat; a draft stays in the composer.
struct MiraChatOverlay: View {
    @Binding var prompt: String
    var focus: FocusState<Bool>.Binding
    var dictation: DictationStripState
    var onUndo: () -> Void
    var undoEnabled: Bool
    var onSend: () -> Void
    var onQuickAction: (String) -> Void
    var onClose: () -> Void
    var onHoldStart: () -> Void
    var onHoldEnd: () -> Void
    /// The system took the touch mid-hold: the take stops, nothing kept.
    var onHoldCancel: () -> Void
    /// Starts or ends the take in one activation (assistive technologies).
    var onToggle: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // The design's "story canvas dim glass scrim": blur 8 under
            // paper@0.38. A tap on it closes the chat.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.paper.opacity(0.38))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                TopBar(
                    leading: "Canvas",
                    trailing: "Done",
                    onLeading: onClose,
                    onTrailing: onClose,
                    onUndo: onUndo,
                    undoEnabled: undoEnabled,
                    leadingOnGlass: true
                )
                questionCapsule
                    .padding(.top, 12 - Metrics.navToCanvas)
                miraPanel
                    // A tap on the panel lowers the keyboard; the quick
                    // actions still act.
                    .onTapGesture { focus.wrappedValue = false }
                    .padding(.top, 25)
                Spacer(minLength: 0)
                DictationStrip(
                    surface: .keyboard,
                    listening: dictation == .listening,
                    detail: dictation.detail,
                    action: dictation == .listening ? "Release" : "Hold",
                    onPress: onHoldStart,
                    onRelease: onHoldEnd,
                    onCancel: onHoldCancel
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mira Dictation")
                .accessibilityValue(dictation.detail)
                .accessibilityHint(dictation == .listening
                    ? Text("Ends the dictation.")
                    : Text("Hold to talk, or tap to start; your words land in the question."))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onToggle() }
                .accessibilityIdentifier("mira.dictation")
                .padding(.horizontal, Metrics.chromeInset)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: Question

    /// The live question: Medium 17 white words on ink, 253 wide against
    /// the trailing inset. Return sends.
    private var questionCapsule: some View {
        HStack {
            Spacer(minLength: 0)
            // Single line: the keyboard's Send is the system Return
            // (onSubmit); a paste never sends -- only the key does.
            TextField(
                "",
                text: $prompt,
                prompt: Text("Ask Mira anything").foregroundStyle(Color.white.opacity(0.55))
            )
            .font(.miraComposer)
            .foregroundStyle(Color.white)
            .tint(Color.white)
            .submitLabel(.send)
            .onSubmit(onSend)
            .focused(focus)
            // The dark keyboard of the handoff (forest-tinted in the mock).
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 18)
            // 14 as drawn plus the half-leading of lh16 (Josefin's line
            // box is 1.0 em; lineSpacing only adds between lines).
            .padding(.vertical, 16)
            .frame(width: 253, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Palette.ink)
                    .shadow(color: Palette.ink.opacity(0.1), radius: 8, y: 12)
            )
            .accessibilityLabel("Ask Mira")
            .accessibilityIdentifier("mira.input")
        }
        .padding(.horizontal, Metrics.chromeInset)
    }

    // MARK: Mira's panel

    private var miraPanel: some View {
        HStack(alignment: .top, spacing: 2) {
            MiraMark()
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mira can edit this canvas directly.")
                    .font(Sans.font(size: 16, weight: 700))
                    .foregroundStyle(Palette.ink)
                    // Wraps rather than truncates on a narrow phone.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 18)
                    .padding(.top, 17)
                // One literal, so it is looked up in the string catalog.
                // swiftlint:disable:next line_length
                Text("The current page stays attached, so Mira can change color, layout, copy, stickers, or image treatment without starting over.")
                    .font(Sans.font(size: 13, weight: 700))
                    .foregroundStyle(Self.warmGrey)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    // The handoff's lh15 on 11 pt: 2 pt each side (the text is 13 pt now).
                    .padding(.vertical, 2)
                    .padding(.top, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(MiraCanvasCoordinator.quickActions.enumerated()), id: \.offset) { index, action in
                        quickAction(action, primary: index == 0, solid: index == 3)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 17)
            .background(
                GlassSurface(
                    shape: RoundedRectangle(cornerRadius: 26),
                    tint: Color.white.opacity(0.48),
                    rim: Color.white.opacity(0.38),
                    highlight: false,
                    shadowOpacity: 0.1,
                    shadowRadius: 8,
                    shadowY: 12
                )
            )
        }
        .padding(.leading, 24)
        .padding(.trailing, Metrics.chromeInset)
    }

    private func quickAction(_ action: String, primary: Bool, solid: Bool) -> some View {
        Button {
            onQuickAction(action)
        } label: {
            Text(copy: action)
                .font(Sans.font(size: 12, weight: 700))
                .foregroundStyle(primary ? Color.white : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    Capsule()
                        .fill(primary ? Palette.ink : (solid ? Color(hex: 0xF7F6F3) : Color.white.opacity(0.58)))
                        .overlay(Capsule().strokeBorder(
                            primary ? Color(hex: 0x6C6C6C).opacity(0.42) : Color(hex: 0x929292).opacity(0.72),
                            lineWidth: 1
                        ))
                )
                .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mira.action.\(action)")
    }

    /// The handoff's warm grey for the panel's body line.
    private static let warmGrey = Color(hex: 0x8F7E76)
}

/// What the dictation strip says: at rest, listening, or why nothing landed.
enum DictationStripState: Equatable {
    case idle
    case listening
    case transcribing
    case notice(String)

    var detail: String {
        switch self {
        case .idle: return String(appCopy: "accurate voice-to-text")
        case .listening: return String(appCopy: "Listening...")
        case .transcribing: return String(appCopy: "Writing it down...")
        case .notice(let message): return message
        }
    }
}

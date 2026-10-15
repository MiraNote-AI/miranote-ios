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
                    .padding(.top, 25)
                Spacer(minLength: 0)
                DictationStrip(state: dictation, onHoldStart: onHoldStart, onHoldEnd: onHoldEnd)
                    .padding(.horizontal, Metrics.chromeInset)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: Question

    /// The live question: Medium 12 white words on ink, 253 wide against
    /// the trailing inset. Return sends.
    private var questionCapsule: some View {
        HStack {
            Spacer(minLength: 0)
            TextField(
                "",
                text: $prompt,
                prompt: Text("Ask Mira anything").foregroundStyle(Color.white.opacity(0.55)),
                axis: .vertical
            )
            .font(.miraComposer)
            .lineSpacing(4)
            .lineLimit(1...4)
            .foregroundStyle(Color.white)
            .tint(Color.white)
            .submitLabel(.go)
            .focused(focus)
            // A multi-line field takes Return as a new line; here Return
            // sends, as the keyboard's Go key says.
            .onChange(of: prompt) { _, words in
                guard words.contains("\n") else { return }
                prompt = words.replacingOccurrences(of: "\n", with: "")
                onSend()
            }
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
            Circle()
                .fill(Palette.ink)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("M")
                        .font(Sans.font(size: 13, weight: 700))
                        .foregroundStyle(Color.white)
                        .offset(y: 1)
                )
                .padding(.top, 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mira can edit this canvas directly.")
                    .font(Sans.font(size: 14, weight: 700))
                    .foregroundStyle(Palette.ink)
                    .frame(height: 18)
                    .padding(.top, 17)
                Text("The current page stays attached, so Mira can change color, layout, copy, "
                     + "stickers, or image treatment without starting over.")
                    .font(Sans.font(size: 11, weight: 700))
                    .foregroundStyle(Self.warmGrey)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    // lh15 on an 11 pt, 1.0 em line box: 2 pt each side.
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
            Text(action)
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(primary ? Color.white : Palette.ink)
                .lineLimit(1)
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
}

/// The "Mira Dictation" strip (screen 06): press and hold to talk; on
/// release the words land in the question for editing, never sent by
/// themselves.
struct DictationStrip: View {
    let state: DictationStripState
    var onHoldStart: () -> Void
    var onHoldEnd: () -> Void

    @State private var holding = false

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Palette.forest)
                .frame(width: 18, height: 18)
                .overlay(
                    Image("mira.dictation.mic")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 12, height: 12)
                )
                .scaleEffect(state == .listening ? 1.12 : 1)
                .padding(.leading, 9)
            Text("Mira Dictation")
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Palette.ink)
                .frame(width: 104, alignment: .leading)
                .padding(.leading, 8)
            Text(detail)
                .font(Sans.font(size: 10, weight: 400))
                .foregroundStyle(Self.detail)
                .lineLimit(1)
                .padding(.leading, 2)
                .accessibilityIdentifier("mira.dictation.detail")
            Spacer(minLength: 4)
            Text(state == .listening ? "Release" : "Hold")
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Palette.forest)
                .padding(.trailing, 13)
        }
        .frame(height: 30)
        .background(
            GlassSurface(
                shape: Capsule(),
                tint: Palette.forest.opacity(0.06),
                rim: Color.black.opacity(0.42),
                highlight: false,
                shadowOpacity: 0.1,
                shadowRadius: 6,
                shadowY: 12
            )
        )
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    onHoldStart()
                }
                .onEnded { _ in
                    holding = false
                    onHoldEnd()
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mira Dictation")
        .accessibilityHint("Hold to talk; your words land in the question")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("mira.dictation")
    }

    private var detail: String {
        switch state {
        case .idle: return "accurate voice-to-text"
        case .listening: return "Listening..."
        case .transcribing: return "Writing it down..."
        case .notice(let message): return message
        }
    }

    private static let detail = Color(hex: 0x8F7E76)
}

import MiraNoteKit
import SwiftUI

/// Handoff screen 06, the Mira canvas chat: a frosted scrim over the canvas
/// and the dock, Mira's panel with the four quick actions, and the question
/// box at the bottom, riding on the keyboard: the writing chat box's light
/// pill with its mic (team lead, 2026-11-22, option B) -- hold to talk or
/// tap to toggle, Go once there are words. The nav pills stay on top:
/// Canvas (on glass) and Done both close the chat; a draft stays in the
/// composer.
struct MiraChatOverlay: View {
    @Binding var prompt: String
    var focus: FocusState<Bool>.Binding
    /// A take is listening or its press is in progress: the mic stays
    /// (never Go) under the finger.
    let listening: Bool
    /// Listening, the words on their way, or why nothing landed: over the
    /// box, and the mic's VoiceOver value.
    let caption: String?
    var onUndo: () -> Void
    var undoEnabled: Bool
    var onSend: () -> Void
    var onQuickAction: (String) -> Void
    var onClose: () -> Void
    var onHoldStart: () -> Void
    var onHoldEnd: () -> Void
    /// The system took the touch mid-hold: the take ends as if let go (#218).
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
                miraPanel
                    // A tap on the panel lowers the keyboard; the quick
                    // actions still act.
                    .onTapGesture { focus.wrappedValue = false }
                    .padding(.top, 25)
                Spacer(minLength: 0)
                questionBox
            }
        }
    }

    // MARK: Question

    /// The writing chat box, asking Mira about the page: Return or Go
    /// sends; a paste never does.
    private var questionBox: some View {
        WritingChatBox(
            ask: $prompt,
            focus: focus,
            listening: listening,
            // No waveform: the words land in this field, which keeps the
            // keyboard while the mic listens.
            recorder: nil,
            status: caption ?? "",
            canGo: true,
            asking: false,
            onGo: onSend,
            onPress: onHoldStart,
            onRelease: onHoldEnd,
            onCancel: onHoldCancel,
            onToggle: onToggle,
            onEscape: onClose,
            names: .chat
        )
        .padding(.horizontal, Metrics.chromeInset)
        // As the writing box's caption: over the box, taking no room.
        .overlay(alignment: .top) {
            if let caption {
                Text(caption)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Metrics.chromeInset)
                    .padding(.bottom, 6)
                    .frame(height: 0, alignment: .bottom)
                    .transition(.opacity)
                    .accessibilityIdentifier("mira.caption")
            }
        }
        .animation(.easeOut(duration: 0.15), value: caption)
        // 8 above the keyboard, or the home indicator when it is down.
        .padding(.bottom, 8)
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

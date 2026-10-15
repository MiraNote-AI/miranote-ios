import MiraNoteKit
import SwiftUI

/// The card above the Mira bar: conversational replies (with their
/// follow-up chips), image choices and taxonomy failures. At rest it is
/// empty: the handoff draws nothing between the tool bar and the composer
/// (screens 04, 05, 07, 22); a landed change shows as the result sheet over
/// the canvas (MiraResultSheet, screen 07). Never red -- failure is calm
/// and still; waiting is motion elsewhere (bar + element).
struct MiraCard: View {
    @Bindable var coordinator: MiraCanvasCoordinator
    @Bindable var editor: CanvasViewModel
    var onAsk: (String) -> Void
    var onRephrase: () -> Void
    var onRetry: () -> Void

    // A user edit while a receipt shows makes Revert dishonest; CanvasScene
    // tells the coordinator (it is always mounted -- this card is not
    // while a panel or the recorder holds the dock).
    var body: some View {
        content
    }

    @ViewBuilder private var content: some View {
        switch coordinator.phase {
        case .idle, .working, .receipt:
            EmptyView()
        case .reply(_, let chips):
            // The conversation reads as one thread: the transcript scrolls
            // (newest pinned), then the follow-up chips, sitting flush on
            // the input bar. Full messages -- no truncation.
            card {
                HStack {
                    Spacer()
                    Button {
                        coordinator.dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mira.dismissReply")
                }
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(coordinator.conversation) { turn in
                                transcriptRow(turn).id(turn.id)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    .onAppear {
                        if let last = coordinator.conversation.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: coordinator.conversation.count) {
                        guard let last = coordinator.conversation.last else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                chipsRow(chips)
            }
        case .failure(let failure):
            card {
                HStack(alignment: .top, spacing: 8) {
                    avatar
                    Text(failure.message)
                        .font(.miraBody)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("mira.failure")
                }
                HStack(spacing: 8) {
                    ForEach(failure.chips, id: \.self) { chip in
                        Button(chip) { handleFailureChip(chip) }
                            .buttonStyle(SoftPill())
                            .accessibilityIdentifier(chip == "Try again" ? "mira.retry" : "mira.chip.\(chip)")
                    }
                    Spacer()
                }
            }
        case .imageChoices(let images, _, let placement):
            // Two candidates, the human picks ("AI offers, the human
            // shapes"); the xmark discards both without touching paper.
            card {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                        Button {
                            coordinator.placeImageChoice(index, editor: editor)
                        } label: {
                            choiceThumb(for: data, tall: placement == .background)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mira.imageChoice.\(index)")
                    }
                    Spacer()
                    Button {
                        coordinator.discardImageChoices()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mira.imageChoice.dismiss")
                }
            }
        }
    }

    @ViewBuilder private func choiceThumb(for data: Data, tall: Bool) -> some View {
        let width: CGFloat = tall ? 64 : 84
        let height: CGFloat = tall ? 114 : 84
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.tan.opacity(0.4))
                .frame(width: width, height: height)
        }
    }

    private func transcriptRow(_ turn: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if turn.role == .assistant {
                avatar
                Text(ChatMarkdown.attributed(turn.text))
                    .font(.miraBody)
                    .foregroundStyle(Palette.ink)
                    // Full prose, never an ellipsis: height-squeezed Text
                    // truncates unless it may grow vertically.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.miraBody)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Palette.ink))
            }
        }
    }

    private func handleFailureChip(_ chip: String) {
        switch chip {
        case "Try again":
            onRetry()
        case "Rephrase":
            onRephrase()
        default:
            onAsk(chip)
        }
    }

    private var avatar: some View {
        MiraMark()
    }

    private func handleSuggestion(_ chip: String) {
        if chip == MiraCanvasCoordinator.placeReplyChip {
            coordinator.placeReply(editor: editor)
        } else {
            coordinator.askSuggestion(chip, editor: editor)
        }
    }

    @ViewBuilder private func chipsRow(_ chips: [String]) -> some View {
        if chips.isEmpty {
            EmptyView()
        } else if chips.count <= 2 {
            // One or two suggestions fill the row like a designed slot --
            // a lone left-hugging pill read as a leftover.
            HStack(spacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        handleSuggestion(chip)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.forest)
                            Text(chip)
                                .font(.miraLabel)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Palette.onInk)
                                .overlay(
                                    Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                                )
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mira.suggestion.\(chip)")
                }
            }
            .padding(.horizontal, Metrics.chromeInset)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) { handleSuggestion(chip) }
                            .buttonStyle(SoftPill())
                            .accessibilityIdentifier("mira.suggestion.\(chip)")
                    }
                }
                .padding(.horizontal, Metrics.chromeInset)
            }
        }
    }

    /// Handoff screen 06: a soft warm-white card lifted off the page.
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Palette.warmWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                )
                .shadow(color: Palette.ink.opacity(0.08), radius: 20, y: 12)
        )
        .padding(.horizontal, Metrics.chromeInset)
    }
}

/// The unified command bar: the composer at rest -- a tap opens the Mira
/// canvas chat (screen 06), where the words are typed; a draft left there
/// waits here with Go -- and past 400 ms of work the verb-specific working
/// bar with the Stop control (stop refills the prompt, applies nothing).
struct MiraBar: View {
    @Bindable var coordinator: MiraCanvasCoordinator
    @Bindable var editor: CanvasViewModel
    @Binding var prompt: String
    /// "Ask Mira anything"; "Ask Mira to refine..." while a result waits
    /// for Keep or Revert (screen 07) or an element is selected (21); "Ask
    /// Mira to adjust sound..." beside a new take (09).
    var placeholder = "Ask Mira anything"
    var onOpenChat: () -> Void

    var body: some View {
        Group {
            if case .working(let verb) = coordinator.phase {
                workingBar(verb)
            } else {
                inputBar
            }
        }
        .onChange(of: coordinator.refillPrompt) { _, refill in
            if let refill {
                prompt = refill
                coordinator.refillPrompt = nil
            }
        }
    }

    private var inputBar: some View {
        // Handoff composer: Medium 12 words from x 17 and the Go pill. The
        // words are the draft left in the chat, or the placeholder.
        ComposerCapsule(action: "Go", actionID: "mira.go", canAct: canSend, onAct: submit) {
            Button(action: onOpenChat) {
                Text(prompt.isEmpty ? placeholder : prompt)
                    .font(.miraComposer)
                    .foregroundStyle(prompt.isEmpty ? Palette.muted : Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt.isEmpty ? placeholder : prompt)
            .accessibilityHint("Opens the Mira chat")
            .accessibilityIdentifier("mira.composer")
        }
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coordinator.isWorking
    }

    private func workingBar(_ verb: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Palette.onInk)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(verb)
                .font(.miraLabel)
                .foregroundStyle(Palette.onInk)
            Spacer()
            Button("Stop") { coordinator.stop() }
                .font(.miraLabel.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.onInk))
                .buttonStyle(.plain)
                .accessibilityIdentifier("mira.stop")
        }
        .padding(.horizontal, 14)
        // The composer's 54 pt: a shorter working bar moved the tool bar
        // and canvas on every turn longer than 400 ms.
        .frame(minHeight: 54)
        .background(Capsule().fill(Palette.ink))
        .padding(.horizontal, Metrics.chromeInset)
    }

    private func submit() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prompt = ""
        coordinator.ask(trimmed, editor: editor)
    }
}

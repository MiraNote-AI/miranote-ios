import MiraNoteKit
import SwiftUI

/// The card above the Mira bar: idle suggestion chips, conversational
/// replies, the Keep-pattern receipt, and taxonomy failures. Never red --
/// failure is calm and still; waiting is motion elsewhere (bar + element).
struct MiraCard: View {
    @Bindable var coordinator: MiraCanvasCoordinator
    @Bindable var editor: CanvasViewModel
    var onAsk: (String) -> Void
    var onRephrase: () -> Void
    var onRetry: () -> Void

    var body: some View {
        content
            // A user edit while the receipt shows makes Revert dishonest --
            // the receipt keeps itself out of the way.
            .onChange(of: editor.changeCount) {
                coordinator.canvasDidChange(editor)
            }
    }

    @ViewBuilder private var content: some View {
        switch coordinator.phase {
        case .idle:
            chipsRow(coordinator.suggestions(for: editor))
        case .working:
            EmptyView()
        case .reply(_, let chips):
            // The conversation reads as one thread: a short transcript,
            // then the follow-up chips, sitting flush on the input bar.
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
                ForEach(coordinator.conversation.suffix(4)) { turn in
                    transcriptRow(turn)
                }
                chipsRow(chips)
            }
        case .receipt(let receipt):
            // A confirmation stamp, not a chat element (Meng, 2026-07-09):
            // one forest-tinted line with Revert, kept-line dropped, and it
            // keeps by itself after a short window. Tap dismisses.
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.forest)
                Text(receipt.changed)
                    .font(.miraLabel)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("mira.receipt")
                Spacer()
                Button("Revert") { coordinator.revert(editor: editor) }
                    .font(.miraLabel)
                    .foregroundStyle(Palette.forest)
                    .accessibilityIdentifier("mira.revert")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Palette.forest.opacity(0.1))
                    .overlay(
                        Capsule().strokeBorder(Palette.forest.opacity(0.35), lineWidth: Metrics.hairline)
                    )
            )
            .padding(.horizontal, Metrics.screenPadding)
            .onTapGesture { coordinator.dismiss() }
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
        case .imageChoices(let images, _, _):
            // Two candidates, the human picks ("AI offers, the human
            // shapes"); the xmark discards both without touching paper.
            card {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                        Button {
                            coordinator.placeImageChoice(index, editor: editor)
                        } label: {
                            choiceThumb(for: data)
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

    @ViewBuilder private func choiceThumb(for data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.tan.opacity(0.4))
                .frame(width: 84, height: 84)
        }
    }

    private func transcriptRow(_ turn: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if turn.role == .assistant {
                avatar
                Text(ChatMarkdown.attributed(turn.text))
                    .font(.miraBody)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Palette.ink))
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
        Text("M")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.onInk)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Palette.ink))
    }

    private func handleSuggestion(_ chip: String) {
        if chip == MiraCanvasCoordinator.placeReplyChip {
            coordinator.placeReply(editor: editor)
        } else {
            onAsk(chip)
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
            .padding(.horizontal, Metrics.screenPadding)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) { handleSuggestion(chip) }
                            .buttonStyle(SoftPill())
                            .accessibilityIdentifier("mira.suggestion.\(chip)")
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.onInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                )
        )
        .padding(.horizontal, Metrics.screenPadding)
    }
}

/// The unified command bar: an input at rest; past 400 ms of work it becomes
/// the verb-specific working bar with the Stop control (stop refills the
/// prompt, applies nothing).
struct MiraBar: View {
    @Bindable var coordinator: MiraCanvasCoordinator
    @Bindable var editor: CanvasViewModel
    @Binding var prompt: String
    var promptFocus: FocusState<Bool>.Binding

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
        HStack(spacing: 8) {
            TextField("Ask Mira anything", text: $prompt)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.go)
                .focused(promptFocus)
                .onSubmit(submit)
                .accessibilityIdentifier("mira.input")

            Button(action: submit) {
                Text("Go")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isWorking)
            .accessibilityIdentifier("mira.go")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
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
        .padding(.vertical, 9)
        .background(Capsule().fill(Palette.ink))
        .padding(.horizontal, Metrics.screenPadding)
    }

    private func submit() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        prompt = ""
        coordinator.ask(trimmed, editor: editor)
    }
}

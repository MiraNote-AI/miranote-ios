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
        case .reply(let message, let chips):
            card {
                HStack(alignment: .top, spacing: 8) {
                    avatar
                    Text(message)
                        .font(.miraBody)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder private func chipsRow(_ chips: [String]) -> some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) { onAsk(chip) }
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

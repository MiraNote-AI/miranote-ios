import MiraNoteKit
import SwiftUI

/// The MiraNote AI conversation. Opened from the Home quick-capture field with
/// the typed text as the first message; "New memory" hands off to the editor.
struct MiraChatView: View {
    var seed: String?
    var onExit: () -> Void = {}
    var onNewMemory: () -> Void = {}

    @State private var viewModel: ChatViewModel

    init(
        service: ChatService,
        seed: String? = nil,
        onExit: @escaping () -> Void = {},
        onNewMemory: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: ChatViewModel(service: service))
        self.seed = seed
        self.onExit = onExit
        self.onNewMemory = onNewMemory
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            inputBar
        }
        .screenBackground()
        .task { await viewModel.seedIfNeeded(seed) }
    }

    private var header: some View {
        HStack {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Palette.onInk.opacity(0.6)))
            }
            .buttonStyle(.plain)

            Spacer()
            VStack(spacing: 1) {
                Text("MiraNote AI").font(.miraScreenTitle).foregroundStyle(Palette.ink)
                Text("journaling companion")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()

            Button("New memory", action: onNewMemory)
                .buttonStyle(SoftPill())
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if viewModel.isResponding {
                        TypingBubble().id("typing")
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 20)
            }
            .onChange(of: viewModel.messages.count) { scrollToEnd(proxy) }
            .onChange(of: viewModel.isResponding) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isResponding {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.miraBody)
                .foregroundStyle(isUser ? Palette.onInk : Palette.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isUser ? Palette.ink : Palette.cardFill)
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("", text: $viewModel.draft)
                .font(.miraBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.forest)
                .submitLabel(.send)
                .onSubmit { Task { await viewModel.sendDraft() } }
                .overlay(alignment: .leading) {
                    if viewModel.draft.isEmpty {
                        Text("Message MiraNote...")
                            .font(.miraBody)
                            .foregroundStyle(Palette.textSecondary)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                Task { await viewModel.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(viewModel.canSend ? Palette.ink : Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .accessibilityIdentifier("chat.send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Palette.onInk.opacity(0.6))
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 8)
    }
}

/// Three pulsing dots shown while the assistant is composing a reply.
private struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Palette.textSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(animating ? 1 : 0.35)
                        .animation(pulse(index), value: animating)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.cardFill))
            Spacer(minLength: 40)
        }
        .accessibilityHidden(true)
        .onAppear { animating = true }
    }

    private func pulse(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2)
    }
}

import MiraNoteKit
import SwiftUI

/// The MiraNote AI conversation. Opened from the Home quick-capture field
/// with the typed text as the first message; asking Mira to note something
/// down yields a draft card that opens the editor.
struct MiraChatView: View {
    var seed: String?
    var onExit: () -> Void = {}
    /// The header's Canvas pill: leave the chat for a blank page.
    var onOpenCanvas: () -> Void = {}
    /// Mira answers "find" questions with pages, not paragraphs (v2.1):
    /// every user message also runs the library search; hits render as
    /// tappable covers under it.
    var findPages: (String) -> [PageHit] = { _ in [] }
    var onOpenPage: (PageHit) -> Void = { _ in }
    /// Mira drafted a page from the conversation; open it in the editor.
    var onOpenDraft: (ChatPageDraft) -> Void = { _ in }

    @State private var viewModel: ChatViewModel
    @State private var hits: [ChatMessage.ID: [PageHit]] = [:]
    private let imageStore = Self.photoStore

    /// Sent chat photos live only as long as the transcript (which is not
    /// saved): in tmp, out of Documents and backups, for iOS to purge.
    private static let photoStore = ImageFileStore(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("ChatPhotos", isDirectory: true)
    )

    init(
        service: ChatService,
        transcription: VoiceTranscriptionService,
        studio: ImageStudioService,
        recorderFactory: @escaping @MainActor () -> AudioRecording,
        seed: String? = nil,
        onExit: @escaping () -> Void = {},
        onOpenCanvas: @escaping () -> Void = {},
        findPages: @escaping (String) -> [PageHit] = { _ in [] },
        onOpenPage: @escaping (PageHit) -> Void = { _ in },
        onOpenDraft: @escaping (ChatPageDraft) -> Void = { _ in }
    ) {
        // Each outgoing message carries the pages that match it, so the
        // companion answers from the user's own notes (journal mode).
        _viewModel = State(initialValue: ChatViewModel(
            service: service,
            studio: studio,
            transcription: transcription,
            makeRecorder: recorderFactory,
            imageStore: Self.photoStore,
            notesForMessage: { message in
                findPages(message).map { ChatNote(page: $0.memory) }
            }
        ))
        self.seed = seed
        self.onExit = onExit
        self.onOpenCanvas = onOpenCanvas
        self.findPages = findPages
        self.onOpenPage = onOpenPage
        self.onOpenDraft = onOpenDraft
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            MiraChatComposer(viewModel: viewModel)
        }
        .screenBackground()
        .task { await viewModel.seedIfNeeded(seed) }
        // The transcript is not kept, so neither are its photos.
        .onDisappear { viewModel.discardSentPhotos() }
    }

    /// Handoff screen 02: Home on frosted white, Canvas on forest, no title.
    /// The design's center undo glyph is left out -- a conversation has
    /// nothing to undo.
    private var header: some View {
        HStack {
            Button("Home", action: onExit)
                .buttonStyle(NavPill(prominent: false, surface: .chat, width: NavPill.leadingWidth))
                .accessibilityIdentifier("chat.home")
            Spacer()
            Button("Canvas", action: onOpenCanvas)
                // 70 wide like the way back (screen 02).
                .buttonStyle(NavPill(prominent: true, fill: Palette.forest, width: NavPill.leadingWidth))
                .accessibilityIdentifier("chat.canvas")
        }
        .padding(.horizontal, Metrics.chromeInset)
        // Pills at the design's y50 below the status bar.
        .padding(.top, 4)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Rhythm from the handoff: 22 between turns, 28 after the
                // quick-starts card.
                VStack(alignment: .leading, spacing: 22) {
                    MiraBubbleRow(
                        text: "Hi, I'm Mira. Tell me what you want to remember, change, or create.",
                        secondary: "You can start with a mood, a photo, a voice note, or a messy idea."
                    )
                    quickStarts
                        .padding(.bottom, 6)
                    ForEach(viewModel.messages) { message in
                        VStack(alignment: .leading, spacing: 12) {
                            if message.role == .user {
                                UserBubbleRow(message: message, imageStore: imageStore)
                            } else {
                                MiraBubbleRow(text: message.text, markdown: true)
                            }
                            if let draft = message.pageDraft {
                                draftCard(draft)
                                    .padding(.leading, ChatMetrics.bubbleIndent)
                            }
                            if let pageHits = hits[message.id], !pageHits.isEmpty {
                                hitsRow(pageHits)
                            }
                        }
                        .id(message.id)
                    }
                    if viewModel.isResponding {
                        TypingBubble().id("typing")
                    }
                }
                .padding(.horizontal, Metrics.chromeInset)
                .padding(.top, 14)
                .padding(.bottom, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                collectHits()
                scrollToEnd(proxy)
            }
            .onChange(of: viewModel.isResponding) { scrollToEnd(proxy) }
            // The latest turn stays in view when the keyboard or the staged
            // photos take space from the bottom.
            .onChange(of: viewModel.stagedImages.count) { scrollToEnd(proxy) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                scrollToEnd(proxy)
            }
        }
    }

    /// Handoff screen 02's empty-state starters; each chip sends its label.
    private var quickStarts: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Quick starts")
                .font(Sans.font(size: 16, weight: 700))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    quickChip("Make a healing page", width: 132)
                    quickChip("Use my photos", width: 104)
                }
                HStack(spacing: 10) {
                    quickChip("Rewrite softer", width: 104)
                    quickChip("Build a layout", width: 108)
                }
            }
        }
        .padding(.leading, 21)
        .padding(.top, 15)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.white.opacity(0.73))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(Color.white.opacity(0.72), lineWidth: 1))
        )
    }

    private func quickChip(_ label: String, width: CGFloat) -> some View {
        Button {
            Task { await viewModel.send(label) }
        } label: {
            Text(label)
                .font(Sans.font(size: 10, weight: 700))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(width: width, height: 24)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.78))
                        .overlay(Capsule().strokeBorder(Color(hex: 0x929292).opacity(0.72), lineWidth: 1))
                )
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .padding(.vertical, -10)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isResponding)
        .accessibilityIdentifier("chat.quick.\(label)")
    }

    /// Search runs for each new user message exactly once.
    private func collectHits() {
        for message in viewModel.messages where message.role == .user && hits[message.id] == nil {
            hits[message.id] = message.text.isEmpty ? [] : findPages(message.text)
        }
    }

    private func hitsRow(_ pageHits: [PageHit]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From your pages")
                .font(Sans.font(size: 11, weight: 500))
                .kerning(1.4)
                .foregroundStyle(Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pageHits) { hit in
                        Button {
                            onOpenPage(hit)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                PageCoverView(memory: hit.memory, coverWidth: 104, coverHeight: 128)
                                // Cover says the title; the caption says when.
                                Text(CaptionDate.string(for: hit.memory.memoryDate))
                                    .font(.miraCaption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(1)
                                    .frame(width: 104, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.hit.\(hit.memory.title)")
                    }
                }
            }
        }
    }

    /// The drafted page, one tap from the editor ("AI offers, the human
    /// shapes" -- nothing files until the user says Done there).
    private func draftCard(_ draft: ChatPageDraft) -> some View {
        Button {
            onOpenDraft(draft)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.forest)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title.isEmpty ? "New page" : draft.title)
                        .font(.miraCardTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("Draft ready -- open to shape it")
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Palette.onInk)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.draft.open")
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
}

/// Handoff screen 02 measures.
enum ChatMetrics {
    /// Avatar 36 + gap 10: where Mira's bubble starts.
    static let bubbleIndent: CGFloat = 46
    static let miraBubbleMaxWidth: CGFloat = 296
    static let userBubbleMaxWidth: CGFloat = 254
    /// The design's #81796F muted copy, kept at the palette's legible value.
    static let muted = Palette.textSecondary
}

/// Mira speaks from a translucent white bubble (r28) beside her "M" mark.
private struct MiraBubbleRow: View {
    var text: String
    var secondary: String?
    /// Replies carry light markdown (cited titles arrive bolded).
    var markdown = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MiraMark()
                .padding(.top, 12)
            // 15 between the lines lands the secondary line at the design's
            // y61 (Josefin's iOS line box is shorter than the mock's).
            VStack(alignment: .leading, spacing: 15) {
                Text(markdown ? ChatMarkdown.attributed(text) : AttributedString(text))
                    .font(Sans.font(size: 14, weight: 400))
                    .foregroundStyle(Palette.ink)
                if let secondary {
                    Text(secondary)
                        .font(Sans.font(size: 11, weight: 400))
                        .lineSpacing(2)
                        .foregroundStyle(ChatMetrics.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 19)
            .padding(.top, 17)
            .padding(.bottom, secondary == nil ? 16 : 19)
            .background(ChatBubbleShape.mira)
            .frame(maxWidth: ChatMetrics.miraBubbleMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

/// The user's words in ink on the right (r24, 13 pt); photos sit above.
private struct UserBubbleRow: View {
    let message: ChatMessage
    let imageStore: ImageFileStore

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.imageFileNames.isEmpty {
                    ChatPhotoStack(fileNames: message.imageFileNames, imageStore: imageStore)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(Sans.font(size: 13, weight: 400))
                        .foregroundStyle(Palette.onInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Palette.ink))
                }
            }
            .frame(maxWidth: ChatMetrics.userBubbleMaxWidth, alignment: .trailing)
        }
    }
}

/// Sent photos: one at up to 180 pt, several as a two-column grid inside
/// the same 180 pt column. Corners r24 like the bubble they belong to.
private struct ChatPhotoStack: View {
    let fileNames: [String]
    let imageStore: ImageFileStore

    var body: some View {
        if fileNames.count == 1 {
            ChatPhoto(fileName: fileNames[0], imageStore: imageStore, side: 180, corner: 24)
        } else {
            LazyVGrid(columns: [GridItem(.fixed(86), spacing: 8), GridItem(.fixed(86), spacing: 8)], spacing: 8) {
                ForEach(Array(fileNames.enumerated()), id: \.offset) { _, name in
                    ChatPhoto(fileName: name, imageStore: imageStore, side: 86, corner: 18)
                }
            }
            .frame(width: 180)
        }
    }
}

private struct ChatPhoto: View {
    let fileName: String
    let imageStore: ImageFileStore
    let side: CGFloat
    let corner: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Palette.cardFill
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("Photo you sent")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("chat.message.photo")
        .task(id: fileName) {
            image = imageStore.data(forFileName: fileName).flatMap(UIImage.init(data:))
        }
    }
}

/// Mira's bubble surface: white at 48% with a white rim.
private enum ChatBubbleShape {
    static var mira: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color.white.opacity(0.48))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.72), lineWidth: 1))
    }
}

/// Three pulsing dots shown while the assistant is composing a reply.
private struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            MiraMark()
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Palette.textSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(animating ? 1 : 0.35)
                        .animation(pulse(index), value: animating)
                }
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 14.5)
            .background(ChatBubbleShape.mira)
            Spacer(minLength: 24)
        }
        .accessibilityHidden(true)
        .onAppear { animating = true }
    }

    private func pulse(_ index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2)
    }
}

/// Mira's mark beside everything she says (handoff screens 02 and 06):
/// a 36 pt ink circle, "M" in Josefin Bold 13.
struct MiraMark: View {
    var body: some View {
        Text("M")
            .font(Sans.font(size: 13, weight: 700))
            .foregroundStyle(Palette.onInk)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Palette.ink))
            .accessibilityHidden(true)
    }
}

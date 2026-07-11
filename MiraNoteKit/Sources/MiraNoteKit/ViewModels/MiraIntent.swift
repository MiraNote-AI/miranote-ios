import CoreGraphics
import Foundation

struct MiraTimeoutError: Error {}

private extension TextTransformMode {
    var receiptLine: String {
        switch self {
        case .polish: return "Polished the text."
        case .expand: return "Expanded the text."
        case .clean: return "Tightened the text."
        }
    }
}

/// A clarify-type failure raised during classification (e.g. "polish the
/// text" on a page with no text).
struct MiraClarifyError: Error {
    let question: String
    let chips: [String]
}

/// Where a picked image candidate lands.
public enum ImageChoicePlacement: Equatable, Sendable {
    case picture
    case sticker
    case background
}

/// What a successful turn produced. Mutations are described, not applied --
/// the coordinator applies them on the main actor after the await returns.
enum MiraOutcome: Sendable {
    case textChanged(CanvasItem.ID, String, MiraReceipt)
    case titleAdded(String, MiraReceipt)
    case textAdded(String, MiraReceipt)
    case organized(MiraReceipt)
    case reply(String, sessionID: String?)
    // Image and style families (applied in MiraCanvasCoordinator+Images).
    case imageChoices([Data], prompt: String, placement: ImageChoicePlacement)
    case imageReplaced(CanvasItem.ID, Data, MiraReceipt)
    case stickerReplaced(CanvasItem.ID, Data, prompt: String, MiraReceipt)
    /// Edit of an EXISTING sticker: label and symbol are read from the
    /// item at settle time, so only the pixels ride along.
    case stickerEdited(CanvasItem.ID, Data, MiraReceipt)
    case filterApplied(CanvasItem.ID, name: String, MiraReceipt)
    case frameApplied(CanvasItem.ID, name: String, MiraReceipt)
    case textResized(CanvasItem.ID, up: Bool, MiraReceipt)
    case textRecolored(CanvasItem.ID, colorName: String, MiraReceipt)
    case backgroundCleared(MiraReceipt)
}

/// V1 local intent rules. The structured page-draft backend (plan D3 gap)
/// will replace classification; the surrounding turn machinery stays.
enum MiraIntent {
    case transformText(CanvasItem.ID, original: String, TextTransformMode)
    /// AI-driven: the page rides along; the model reads it and titles it.
    case addTitle(pageNotes: [ChatNote])
    /// AI-driven: a few warm sentences about the page (its photo included).
    case addCaption(pageNotes: [ChatNote])
    case organize
    /// Free conversation, grounded in the page being edited (sent as a
    /// journal-mode note so Mira knows what it is standing on).
    case converse(String, pageNotes: [ChatNote])
    case clarifyNoText
    // Image and style families; their cues live in MiraIntent+Image.swift.
    case generateImage(prompt: String, sticker: Bool)
    case editPhoto(CanvasItem.ID, imageData: Data, instruction: String)
    case makeSticker(CanvasItem.ID, imageData: Data, prompt: String)
    case applyFilter(CanvasItem.ID, name: String)
    case applyFrame(CanvasItem.ID, name: String)
    case resizeText(CanvasItem.ID, up: Bool)
    case recolorText(CanvasItem.ID, colorName: String)
    case clarifyPhoto(question: String)
    case editSticker(CanvasItem.ID, imageData: Data, instruction: String, prompt: String)
    case clarifySticker(question: String)
    case setBackground(prompt: String)
    case clearBackground
    case illustrateText(prompt: String)

    /// Where classify reads photo bytes from; the coordinator points this
    /// at its own store, tests at a temp directory.
    @MainActor static var classifyImageStore = ImageFileStore()

    /// Selected text block first; else the longest non-empty block (the
    /// prose body -- titles and date captions are short).
    @MainActor
    static func targetTextBlock(editor: CanvasViewModel) -> (CanvasItem.ID, String)? {
        let candidates = editor.orderedItems.compactMap { item -> (CanvasItem.ID, String)? in
            guard case .text(let block) = item.content,
                  !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (item.id, block.text)
        }
        if let selected = editor.selectedItemID,
           let match = candidates.first(where: { $0.0 == selected }) {
            return match
        }
        return candidates.max { $0.1.count < $1.1.count }
    }

    @MainActor
    static func classify(_ prompt: String, editor: CanvasViewModel) -> MiraIntent {
        let lowered = prompt.lowercased()

        func targetText() -> (CanvasItem.ID, String)? {
            Self.targetTextBlock(editor: editor)
        }

        // Image and style cues run first: photo-flavored wording ("make
        // the photo warmer") must win the filter, never fall into polish.
        if let imageIntent = Self.classifyImageOrStyle(
            lowered, prompt: prompt, editor: editor, imageStore: Self.classifyImageStore
        ) {
            return imageIntent
        }

        if lowered.contains("polish") || lowered.contains("warmer") || lowered.contains("softer") {
            if let (id, original) = targetText() {
                return .transformText(id, original: original, .polish)
            }
            return .clarifyNoText
        }
        if lowered.contains("expand") || lowered.contains("longer") {
            if let (id, original) = targetText() {
                return .transformText(id, original: original, .expand)
            }
            return .clarifyNoText
        }
        if lowered.contains("shorten") || lowered.contains("clean") || lowered.contains("tighten") {
            if let (id, original) = targetText() {
                return .transformText(id, original: original, .clean)
            }
            return .clarifyNoText
        }
        if lowered.contains("title") {
            return .addTitle(pageNotes: [ChatNote(page: editor.composedMemory())])
        }
        // Escaped strings are Chinese for caption / add-a-passage / write-
        // a-passage (source stays ASCII per repo rule 3).
        let captionCues = [
            "caption", "add a few words", "add words", "add text", "add a text",
            "write something", "write a few", "describe",
            "\u{914D}\u{6587}", "\u{52A0}\u{4E00}\u{6BB5}", "\u{5199}\u{4E00}\u{6BB5}",
            "\u{52A0}\u{6BB5}\u{6587}\u{5B57}", "\u{5199}\u{6BB5}",
            "\u{63CF}\u{8FF0}", "\u{5199}\u{51E0}\u{53E5}"
        ]
        if captionCues.contains(where: lowered.contains) {
            return .addCaption(pageNotes: [ChatNote(page: editor.composedMemory())])
        }
        if lowered.contains("tidy") || lowered.contains("layout")
            || lowered.contains("organize") || lowered.contains("arrange") {
            return .organize
        }
        return .converse(prompt, pageNotes: [ChatNote(page: editor.composedMemory())])
    }

    var verb: String {
        switch self {
        case .transformText(_, _, .polish): return "Polishing the text..."
        case .transformText(_, _, .expand): return "Expanding the text..."
        case .transformText(_, _, .clean): return "Tightening the text..."
        case .addTitle: return "Adding a title..."
        case .addCaption: return "Writing a few words..."
        case .organize: return "Tidying the layout..."
        case .converse: return "Thinking..."
        case .clarifyNoText: return "Thinking..."
        case .generateImage: return "Painting..."
        case .editPhoto: return "Restyling the photo..."
        case .makeSticker: return "Cutting the sticker..."
        case .editSticker: return "Redrawing the sticker..."
        case .setBackground: return "Painting the backdrop..."
        case .illustrateText: return "Painting..."
        // Instant local work settles before the 400 ms delay ever shows it.
        case .applyFilter, .applyFrame, .resizeText, .recolorText, .clearBackground:
            return "Working..."
        case .clarifyPhoto, .clarifySticker: return "Thinking..."
        }
    }

    var affectedItems: Set<CanvasItem.ID> {
        switch self {
        case .transformText(let id, _, _),
             .editPhoto(let id, _, _),
             .makeSticker(let id, _, _),
             .applyFilter(let id, _),
             .applyFrame(let id, _),
             .resizeText(let id, _),
             .recolorText(let id, _),
             .editSticker(let id, _, _, _):
            return [id]
        default:
            return []
        }
    }

    func perform(
        text: TextTransformService,
        chat: ChatService,
        sessionID: String?,
        imageStudio: ImageStudioService
    ) async throws -> MiraOutcome {
        switch self {
        case .transformText(let id, let original, let mode):
            let transformed = try await text.transform(original, mode: mode)
            return .textChanged(id, transformed, MiraReceipt(
                changed: mode.receiptLine,
                kept: "Layout, photos, and everything else stayed put."
            ))
        case .addTitle(let pageNotes):
            return try await Self.performAddTitle(chat: chat, pageNotes: pageNotes)
        case .addCaption(let pageNotes):
            return try await Self.performAddCaption(chat: chat, pageNotes: pageNotes)
        case .organize:
            return .organized(MiraReceipt(
                changed: "Tidied the layout.",
                kept: "Your words and photos are unchanged."
            ))
        case .converse(let prompt, let pageNotes):
            let reply = try await chat.reply(to: prompt, sessionID: sessionID, notes: pageNotes)
            if let landed = MiraIntent.landedDraft(from: reply) {
                return landed
            }
            return .reply(reply.text, sessionID: reply.sessionID)
        case .clarifyNoText:
            throw MiraClarifyError(
                question: "There are no words on the page yet -- which text should I change?",
                chips: ["Add a soft title"]
            )
        case .generateImage, .editPhoto, .makeSticker, .applyFilter,
             .applyFrame, .resizeText, .recolorText, .clarifyPhoto,
             .editSticker, .clarifySticker, .setBackground, .clearBackground,
             .illustrateText:
            return try await performImageOrStyle(imageStudio: imageStudio)
        }
    }

    private static func performAddTitle(chat: ChatService, pageNotes: [ChatNote]) async throws -> MiraOutcome {
        let reply = try await chat.reply(
            to: "Give this page a short, soft title: five words or fewer, "
                + "warm and concrete. Answer with the title only.",
            sessionID: nil,
            notes: pageNotes
        )
        let title = MiraIntent.cleanTitle(reply.text)
        return .titleAdded(title.isEmpty ? "A quiet moment" : title, MiraReceipt(
            changed: "Added a soft title.",
            kept: "Your words and photos are unchanged."
        ))
    }

    private static func performAddCaption(chat: ChatService, pageNotes: [ChatNote]) async throws -> MiraOutcome {
        let reply = try await chat.reply(
            to: "Write one or two warm sentences for this page -- about "
                + "its photo if it has one. Answer with the sentences only, "
                + "in the language the page is written in. No commentary, "
                + "no markdown, no emoji.",
            sessionID: nil,
            notes: pageNotes
        )
        let words = MiraIntent.cleanPlacedText(reply.text)
        guard !words.isEmpty else {
            throw MiraClarifyError(
                question: "I could not find words for this page -- try again?",
                chips: ["Try again"]
            )
        }
        return .textAdded(words, MiraReceipt(
            changed: "Added a few words.",
            kept: "Everything else stayed put."
        ))
    }

}

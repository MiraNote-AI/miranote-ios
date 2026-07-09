import CoreGraphics
import Foundation

struct MiraTimeoutError: Error {}

/// A clarify-type failure raised during classification (e.g. "polish the
/// text" on a page with no text).
struct MiraClarifyError: Error {
    let question: String
    let chips: [String]
}

/// What a successful turn produced. Mutations are described, not applied --
/// the coordinator applies them on the main actor after the await returns.
enum MiraOutcome: Sendable {
    case textChanged(CanvasItem.ID, String, MiraReceipt)
    case titleAdded(String, MiraReceipt)
    case organized(MiraReceipt)
    case reply(String, sessionID: String?)
}

/// V1 local intent rules. The structured page-draft backend (plan D3 gap)
/// will replace classification; the surrounding turn machinery stays.
enum MiraIntent {
    case transformText(CanvasItem.ID, original: String, TextTransformMode)
    case addTitle
    case organize
    /// Free conversation, grounded in the page being edited (sent as a
    /// journal-mode note so Mira knows what it is standing on).
    case converse(String, pageNotes: [ChatNote])
    case clarifyNoText

    @MainActor
    static func classify(_ prompt: String, editor: CanvasViewModel) -> MiraIntent {
        let lowered = prompt.lowercased()

        func targetText() -> (CanvasItem.ID, String)? {
            let candidates = editor.orderedItems.compactMap { item -> (CanvasItem.ID, String)? in
                guard case .text(let block) = item.content,
                      !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return (item.id, block.text)
            }
            if let selected = editor.selectedItemID,
               let match = candidates.first(where: { $0.0 == selected }) {
                return match
            }
            // No selection: the longest text is almost always the prose body
            // (titles and date captions are short).
            return candidates.max { $0.1.count < $1.1.count }
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
            return .addTitle
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
        case .organize: return "Tidying the layout..."
        case .converse: return "Thinking..."
        case .clarifyNoText: return "Thinking..."
        }
    }

    var affectedItems: Set<CanvasItem.ID> {
        if case .transformText(let id, _, _) = self { return [id] }
        return []
    }

    func perform(
        text: TextTransformService,
        chat: ChatService,
        sessionID: String?
    ) async throws -> MiraOutcome {
        switch self {
        case .transformText(let id, let original, let mode):
            let transformed = try await text.transform(original, mode: mode)
            let what: String
            switch mode {
            case .polish: what = "Polished the text."
            case .expand: what = "Expanded the text."
            case .clean: what = "Tightened the text."
            }
            return .textChanged(id, transformed, MiraReceipt(
                changed: what,
                kept: "Layout, photos, and everything else stayed put."
            ))
        case .addTitle:
            return .titleAdded("A quiet moment", MiraReceipt(
                changed: "Added a soft title.",
                kept: "Your words and photos are unchanged."
            ))
        case .organize:
            return .organized(MiraReceipt(
                changed: "Tidied the layout.",
                kept: "Your words and photos are unchanged."
            ))
        case .converse(let prompt, let pageNotes):
            let reply = try await chat.reply(to: prompt, sessionID: sessionID, notes: pageNotes)
            return .reply(reply.text, sessionID: reply.sessionID)
        case .clarifyNoText:
            throw MiraClarifyError(
                question: "There are no words on the page yet -- which text should I change?",
                chips: ["Add a soft title"]
            )
        }
    }
}

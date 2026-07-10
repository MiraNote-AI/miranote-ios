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
    case textAdded(String, MiraReceipt)
    case organized(MiraReceipt)
    case reply(String, sessionID: String?)
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
            return .addTitle(pageNotes: [ChatNote(page: editor.composedMemory())])
        }
        // Escaped strings are Chinese for caption / add-a-passage / write-
        // a-passage (source stays ASCII per repo rule 3).
        let captionCues = [
            "caption", "add a few words", "add words", "add text",
            "write something", "write a few",
            "\u{914D}\u{6587}", "\u{52A0}\u{4E00}\u{6BB5}", "\u{5199}\u{4E00}\u{6BB5}",
            "\u{52A0}\u{6BB5}\u{6587}\u{5B57}", "\u{5199}\u{6BB5}"
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

    /// The model structured a draft (create_note) mid-conversation? On
    /// the canvas that MEANS "these words, on this page" -- land the clean
    /// body; the chatter never touches the paper.
    private static func landedDraft(from reply: ChatReply) -> MiraOutcome? {
        guard let draft = reply.pageDraft else { return nil }
        let words = cleanPlacedText(draft.body.isEmpty ? draft.title : draft.body)
        guard !words.isEmpty else { return nil }
        return .textAdded(words, MiraReceipt(
            changed: "Added a few words.",
            kept: "Everything else stayed put."
        ))
    }

    /// Words landing on the CANVAS must be plain prose: markdown line
    /// decorations go, emphasis marks go, and when the reply frames a
    /// quoted suggestion ("how about: '...'"), the quote IS the payload.
    static func cleanPlacedText(_ raw: String) -> String {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                while trimmed.hasPrefix(">") || trimmed.hasPrefix("#") {
                    trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
        var kept = lines
        // A lead-in that just announces the payload ("Here's a caption:")
        // is chatter; so is a trailing "feel free to tweak" paragraph.
        while let first = kept.first(where: { !$0.isEmpty }), first.hasSuffix(":"),
              let index = kept.firstIndex(of: first) {
            kept.remove(at: index)
        }
        let metaCues = ["it's ready", "feel free", "let me know", "just say", "hope you",
                        "if you'd like", "want me to", "would you like"]
        while let last = kept.last(where: { !$0.isEmpty }),
              metaCues.contains(where: { last.lowercased().hasPrefix($0) || last.lowercased().contains($0) }),
              let index = kept.lastIndex(of: last) {
            kept.remove(at: index)
        }
        var text = kept.joined(separator: "\n")
        for mark in ["**", "__", "*", "_", "`"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var longestQuote = ""
        for (open, close) in [("\"", "\""), ("\u{201C}", "\u{201D}")] {
            var rest = Substring(text)
            while let start = rest.firstIndex(of: Character(open)) {
                let after = rest.index(after: start)
                guard let end = rest[after...].firstIndex(of: Character(close)) else { break }
                let span = String(rest[after..<end])
                if span.count > longestQuote.count { longestQuote = span }
                rest = rest[rest.index(after: end)...]
            }
        }
        if longestQuote.count >= 20 {
            return longestQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// LLM replies arrive with quotes, trailing periods, or a chatty
    /// second line; a title is one clean line.
    static func cleanTitle(_ raw: String) -> String {
        let firstLine = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let noise = CharacterSet(charactersIn: "\"'`.\u{201C}\u{201D}\u{2018}\u{2019}")
            .union(.whitespacesAndNewlines)
        var title = firstLine.trimmingCharacters(in: noise)
        if title.count > 60 {
            title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces)
        }
        return title
    }
}

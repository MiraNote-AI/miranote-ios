import Foundation

/// One turn in a MiraNote AI conversation.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public var role: Role
    public var text: String
    /// A page the companion drafted during this turn, if any -- rendered
    /// as an openable card under the bubble.
    public var pageDraft: ChatPageDraft?

    public init(id: UUID = UUID(), role: Role, text: String, pageDraft: ChatPageDraft? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.pageDraft = pageDraft
    }
}

/// A page the companion drafted from the conversation. The app opens it
/// in the editor for the user to shape -- nothing files automatically.
public struct ChatPageDraft: Codable, Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// The page the user is editing right now, sent with a canvas turn.
/// `image` is a JPEG of the page as they see it -- it rides along on
/// every canvas turn but is only spent if Mira calls look_at_page.
public struct PageContext: Sendable {
    public let map: PageMap
    public let image: Data?

    public init(map: PageMap, image: Data?) {
        self.map = map
        self.image = image
    }
}

/// Slow image work Mira asked the app to run. The server does none of
/// it; it only records the request, the same way it handles create_note.
public enum BackgroundRequest: Equatable, Sendable {
    case set(prompt: String)
    case clear
}

/// A photo restyle Mira asked for, having seen the page. The server
/// records the call; the app runs the slow stylize on its own budget.
public struct PhotoRestyleRequest: Equatable, Sendable {
    public let handle: String
    public let instruction: String

    public init(handle: String, instruction: String) {
        self.handle = handle
        self.instruction = instruction
    }
}

/// An assistant reply plus the server-issued session id to carry into the next
/// turn (the backend keeps the transcript keyed on this id, so the client only
/// tracks the id, not the history).
public struct ChatReply: Sendable {
    public let text: String
    public let sessionID: String?
    public let pageDraft: ChatPageDraft?
    /// Canvas edits Mira asked for, already merged into one change.
    public let pageEdits: [ElementChange]
    public let backgroundRequest: BackgroundRequest?
    public let photoRestyle: PhotoRestyleRequest?

    public init(
        text: String, sessionID: String?, pageDraft: ChatPageDraft? = nil,
        pageEdits: [ElementChange] = [], backgroundRequest: BackgroundRequest? = nil,
        photoRestyle: PhotoRestyleRequest? = nil
    ) {
        self.text = text
        self.sessionID = sessionID
        self.pageDraft = pageDraft
        self.pageEdits = pageEdits
        self.backgroundRequest = backgroundRequest
        self.photoRestyle = photoRestyle
    }
}

/// A page from the user's library, flattened for the companion. Sending
/// notes with a message selects the backend's journal mode: replies come
/// from these pages, never from the demo docs corpus.
public struct ChatNote: Codable, Equatable, Sendable {
    public let title: String
    public let body: String
    public let date: String

    public init(title: String, body: String, date: String) {
        self.title = title
        self.body = body
        self.date = date
    }
}

public extension ChatNote {
    /// What the page "says": body text, canvas words, sound notes, and
    /// sticker prompts, in reading order.
    init(page: Memory) {
        var parts: [String] = []
        if !page.body.isEmpty { parts.append(page.body) }
        for item in page.items {
            switch item.content {
            case .text(let block):
                parts.append(block.text)
            case .sound(let clip):
                if !clip.note.isEmpty { parts.append("(sound) " + clip.note) }
            case .sticker(let sticker):
                if !sticker.prompt.isEmpty { parts.append("(sticker) " + sticker.prompt) }
            case .image(let ref):
                // Vision described it at import. If it has not looked yet,
                // say THAT -- a file name like "Library photo" sends the
                // model chasing bookshelves.
                parts.append(ref.summary.isEmpty
                    ? "(photo) a photo Mira has not looked at yet"
                    : "(photo) " + ref.summary)
            }
        }
        self.init(
            title: page.title,
            body: parts.joined(separator: "\n"),
            date: Self.dayFormatter.string(from: page.memoryDate)
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// The MiraNote AI companion. Backend mapping: chatbot POC (:8003) `/chat`.
public protocol ChatService: Sendable {
    /// `notes` are the user's own pages relevant to this message (journal
    /// mode). The app always sends them -- an empty list means "nothing
    /// matched", not "not a journal conversation".
    ///
    /// `page` is the canvas the user is editing right now. Present = a
    /// canvas turn: the backend releases its page-edit tools and Mira
    /// answers about what is actually on the page. The chat screen sends
    /// nil -- those are pages the user is not editing.
    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply
}

public extension ChatService {
    func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        try await reply(to: message, sessionID: sessionID, notes: notes, page: nil)
    }

    func reply(to message: String, sessionID: String?) async throws -> ChatReply {
        try await reply(to: message, sessionID: sessionID, notes: [], page: nil)
    }
}

/// Warm, journaling-oriented canned replies for previews, tests, and offline
/// use. Deterministic: keyed on the message, not randomness.
public struct MockChatService: ChatService {
    public init() {}

    public func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        try await Task.sleep(for: .milliseconds(500))
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // Canvas asks get a canned edit so previews, snapshot QA and
        // tests exercise the apply path with no network.
        if let page, let first = page.map.elements.first, Self.isCanvasAsk(trimmed) {
            return ChatReply(
                text: "Moved it up for you.",
                sessionID: sessionID ?? "mock-session",
                pageEdits: [ElementChange(handle: first.handle, x: 28, y: 24)]
            )
        }
        if trimmed.lowercased().contains("note") || trimmed.lowercased().contains("draft") {
            return ChatReply(
                text: "I sketched a little page from that -- open it to shape it.",
                sessionID: sessionID ?? "mock-session",
                pageDraft: ChatPageDraft(title: "A small draft", body: trimmed)
            )
        }
        let text: String
        if isAffirmative(trimmed) {
            text = "Lovely. I can set the scene, warm the photo with a film filter, "
                + "and add a small sticker. Tap New memory when you're ready."
        } else {
            text = "\"\(trimmed)\" sounds like a moment worth keeping. Tell me a "
                + "little more, or say the word and I'll shape it into a page."
        }
        return ChatReply(text: text, sessionID: sessionID ?? "mock-session")
    }

    private static func isCanvasAsk(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["move", "tidy", "arrange", "bigger", "smaller"].contains { lowered.contains($0) }
    }

    private func isAffirmative(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let cues = ["yes", "yeah", "ok", "okay", "sure", "start", "go", "please", "let's"]
        return cues.contains { lowered.contains($0) }
    }
}

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

/// An assistant reply plus the server-issued session id to carry into the next
/// turn (the backend keeps the transcript keyed on this id, so the client only
/// tracks the id, not the history).
public struct ChatReply: Sendable {
    public let text: String
    public let sessionID: String?
    public let pageDraft: ChatPageDraft?

    public init(text: String, sessionID: String?, pageDraft: ChatPageDraft? = nil) {
        self.text = text
        self.sessionID = sessionID
        self.pageDraft = pageDraft
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
                // Vision described it at import; fall back to the name.
                let seen = ref.summary.isEmpty
                    ? (ref.displayName.isEmpty ? "a photo" : ref.displayName)
                    : ref.summary
                parts.append("(photo) " + seen)
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
    func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply
}

public extension ChatService {
    func reply(to message: String, sessionID: String?) async throws -> ChatReply {
        try await reply(to: message, sessionID: sessionID, notes: [])
    }
}

/// Warm, journaling-oriented canned replies for previews, tests, and offline
/// use. Deterministic: keyed on the message, not randomness.
public struct MockChatService: ChatService {
    public init() {}

    public func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        try await Task.sleep(for: .milliseconds(500))
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func isAffirmative(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let cues = ["yes", "yeah", "ok", "okay", "sure", "start", "go", "please", "let's"]
        return cues.contains { lowered.contains($0) }
    }
}

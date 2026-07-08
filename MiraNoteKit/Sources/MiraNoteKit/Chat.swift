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

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// An assistant reply plus the server-issued session id to carry into the next
/// turn (the backend keeps the transcript keyed on this id, so the client only
/// tracks the id, not the history).
public struct ChatReply: Sendable {
    public let text: String
    public let sessionID: String?

    public init(text: String, sessionID: String?) {
        self.text = text
        self.sessionID = sessionID
    }
}

/// The MiraNote AI companion. Backend mapping: chatbot POC (:8003) `/chat`.
public protocol ChatService: Sendable {
    func reply(to message: String, sessionID: String?) async throws -> ChatReply
}

/// Warm, journaling-oriented canned replies for previews, tests, and offline
/// use. Deterministic: keyed on the message, not randomness.
public struct MockChatService: ChatService {
    public init() {}

    public func reply(to message: String, sessionID: String?) async throws -> ChatReply {
        try await Task.sleep(for: .milliseconds(500))
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
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

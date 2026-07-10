import Foundation
import Observation

/// Drives the MiraNote AI conversation: holds the transcript, sends the user's
/// message, and appends the assistant's reply. Seeded once with the text the
/// user typed on Home.
@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var messages: [ChatMessage] = []
    public var draft = ""
    public private(set) var isResponding = false

    private let service: ChatService
    /// Selects the user's own pages to ground each message in (journal
    /// mode). Injected by the screen that owns the library.
    private let notesForMessage: (String) -> [ChatNote]
    private var sessionID: String?
    private var didSeed = false

    public init(
        service: ChatService,
        notesForMessage: @escaping (String) -> [ChatNote] = { _ in [] }
    ) {
        self.service = service
        self.notesForMessage = notesForMessage
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    /// Send the first message exactly once (the Home hand-off text).
    public func seedIfNeeded(_ text: String?) async {
        guard !didSeed else { return }
        didSeed = true
        if let text { await send(text) }
    }

    public func sendDraft() async {
        let text = draft
        draft = ""
        await send(text)
    }

    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }
        do {
            let reply = try await service.reply(
                to: trimmed,
                sessionID: sessionID,
                notes: notesForMessage(trimmed)
            )
            sessionID = reply.sessionID
            messages.append(ChatMessage(
                role: .assistant,
                text: reply.text,
                pageDraft: reply.pageDraft
            ))
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription
                ?? "Something went wrong. Try again in a moment."
            messages.append(ChatMessage(role: .assistant, text: detail))
        }
    }
}

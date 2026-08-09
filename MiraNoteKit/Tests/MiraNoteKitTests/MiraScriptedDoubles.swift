import Foundation
@testable import MiraNoteKit

// MARK: - Scripted services

struct ScriptedText: TextTransformService {
    var delay: Duration = .zero
    var error: Error?

    func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return "[\(mode.rawValue)] " + text
    }
}

struct ScriptedChat: ChatService {
    var reply = "Scripted reply."
    var sessionID: String? = "scripted-session"
    var delay: Duration = .zero
    var error: Error?
    var pageDraft: ChatPageDraft?
    var pageEdits: [ElementChange] = []
    var backgroundRequest: BackgroundRequest?
    let recorder = SessionRecorder()

    func reply(
        to message: String, sessionID incoming: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        await recorder.record(incoming, notes: notes, page: page)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return ChatReply(
            text: reply, sessionID: sessionID, pageDraft: pageDraft,
            pageEdits: pageEdits, backgroundRequest: backgroundRequest
        )
    }
}

actor SessionRecorder {
    private(set) var sessionIDs: [String?] = []
    private(set) var notes: [[ChatNote]] = []
    private(set) var pages: [PageContext?] = []

    func record(_ id: String?, notes incoming: [ChatNote], page: PageContext? = nil) {
        sessionIDs.append(id)
        notes.append(incoming)
        pages.append(page)
    }
}

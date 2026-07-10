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
    let recorder = SessionRecorder()

    func reply(to message: String, sessionID incoming: String?, notes: [ChatNote]) async throws -> ChatReply {
        await recorder.record(incoming, notes: notes)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return ChatReply(text: reply, sessionID: sessionID, pageDraft: pageDraft)
    }
}

actor SessionRecorder {
    private(set) var sessionIDs: [String?] = []
    private(set) var notes: [[ChatNote]] = []

    func record(_ id: String?, notes incoming: [ChatNote]) {
        sessionIDs.append(id)
        notes.append(incoming)
    }
}

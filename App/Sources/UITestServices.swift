#if DEBUG
import Foundation
import MiraNoteKit

extension ServiceContainer {
    /// Deterministic services for -UITEST runs: text transforms use the
    /// instant mock; chat is keyword-scripted so the working bar, Stop, and
    /// the failure card can each be driven on purpose.
    static let uiTestScripted = ServiceContainer(
        textTransform: MockTextTransformService(),
        voiceTranscription: MockVoiceTranscriptionService(),
        stickerGeneration: MockStickerGenerationService(),
        styleTransfer: MockStyleTransferService(),
        chat: UITestScriptedChat()
    )
}

/// "slowly" holds the turn long enough to show the working bar; "fail"
/// throws; anything else replies instantly.
struct UITestScriptedChat: ChatService {
    func reply(to message: String, sessionID: String?, notes: [ChatNote]) async throws -> ChatReply {
        let lowered = message.lowercased()
        if lowered.contains("fail") {
            throw URLError(.notConnectedToInternet)
        }
        if lowered.contains("slowly") {
            try await Task.sleep(for: .seconds(8))
        }
        if lowered.contains("draft") {
            return ChatReply(
                text: "Your draft is ready.",
                sessionID: "ui-test",
                pageDraft: ChatPageDraft(title: "Drafted by Mira", body: "warm broth, golden light")
            )
        }
        return ChatReply(text: "A scripted reply for UI tests.", sessionID: "ui-test")
    }
}
#endif

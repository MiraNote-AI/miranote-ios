#if DEBUG
import Foundation
import MiraNoteKit
import UIKit

extension ServiceContainer {
    /// Deterministic services for -UITEST runs: text transforms use the
    /// instant mock; chat and sticker making are keyword-scripted so the
    /// working states, Stop, and the failure card can each be driven on
    /// purpose.
    static let uiTestScripted = ServiceContainer(
        textTransform: MockTextTransformService(),
        voiceTranscription: MockVoiceTranscriptionService(),
        stickerGeneration: MockStickerGenerationService(),
        styleTransfer: MockStyleTransferService(),
        chat: UITestScriptedChat(),
        imageStudio: UITestScriptedStudio()
    )
}

/// The mock studio, except that a sticker prompt with "slowly" holds long
/// enough to show the generating state, and made stickers are a visible
/// round sticker rather than the mock's 8 pt square.
struct UITestScriptedStudio: ImageStudioService {
    private let mock = MockImageStudioService()

    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        try await mock.generate(kind: kind, prompt: prompt)
    }

    func generateStickers(prompt: String) async throws -> StickerGeneration {
        if prompt.lowercased().contains("slowly") {
            try await Task.sleep(for: .seconds(8))
        }
        // Two, like the mock (and the backend on most days).
        let count = try await mock.generate(kind: .sticker, prompt: prompt).count
        return StickerGeneration(images: Array(repeating: Self.roundSticker, count: count))
    }

    func cutout(image: Data, target: String?) async throws -> Data {
        try await mock.cutout(image: image, target: target)
    }

    func stylize(image: Data, instruction: String) async throws -> Data {
        try await mock.stylize(image: image, instruction: instruction)
    }

    func outline(image: Data) async throws -> Data {
        try await mock.outline(image: image)
    }

    func describe(image: Data) async throws -> String {
        try await mock.describe(image: image)
    }

    /// A pink disc with a white rim on a clear ground.
    private static let roundSticker: Data = {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240), format: format).pngData { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 8, y: 8, width: 224, height: 224))
            UIColor(red: 0.91, green: 0.55, blue: 0.66, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 22, y: 22, width: 196, height: 196))
        }
    }()
}

/// "slowly" holds the turn long enough to show the working bar; "fail"
/// throws; anything else replies instantly.
struct UITestScriptedChat: ChatService {
    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
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
        // Carries markdown on purpose (the bubble must render the bold,
        // never print the asterisks) and a quoted suggestion (the reply
        // card's place chip appears only for quoted payloads).
        return ChatReply(
            text: "A **scripted** reply for UI tests. How about: \"a quiet line for the page\"?",
            sessionID: "ui-test"
        )
    }
}
#endif

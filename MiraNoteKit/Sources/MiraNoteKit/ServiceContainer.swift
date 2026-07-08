import Foundation

/// Composition root: the single place that decides which service
/// implementations the running app uses. The app installs `.live`; tests and
/// previews use `.mock` (integration spec D6 -- no global runtime flag, the
/// choice is just which container gets injected).
public struct ServiceContainer: Sendable {
    public let textTransform: TextTransformService
    public let voiceTranscription: VoiceTranscriptionService
    public let stickerGeneration: StickerGenerationService
    public let styleTransfer: StyleTransferService
    public let chat: ChatService

    public init(
        textTransform: TextTransformService,
        voiceTranscription: VoiceTranscriptionService,
        stickerGeneration: StickerGenerationService,
        styleTransfer: StyleTransferService,
        chat: ChatService = MockChatService()
    ) {
        self.textTransform = textTransform
        self.voiceTranscription = voiceTranscription
        self.stickerGeneration = stickerGeneration
        self.styleTransfer = styleTransfer
        self.chat = chat
    }

    /// Live wiring. Text, voice, and chat hit their POCs. Sticker and style
    /// transfer stay mocked -- no backend POC exists for them yet (spec scope).
    public static let live = ServiceContainer(
        textTransform: LiveTextTransformService(),
        voiceTranscription: LiveVoiceTranscriptionService(),
        stickerGeneration: MockStickerGenerationService(),
        styleTransfer: MockStyleTransferService(),
        chat: LiveChatService()
    )

    /// All-mock wiring for previews, tests, and offline use.
    public static let mock = ServiceContainer(
        textTransform: MockTextTransformService(),
        voiceTranscription: MockVoiceTranscriptionService(),
        stickerGeneration: MockStickerGenerationService(),
        styleTransfer: MockStyleTransferService(),
        chat: MockChatService()
    )
}

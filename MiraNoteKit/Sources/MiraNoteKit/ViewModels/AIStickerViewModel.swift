import Foundation
import Observation

/// AI Sticker sheet (sketch 2.2, split out per D2).
@MainActor
@Observable
public final class AIStickerViewModel {
    public var prompt: String
    public private(set) var generated: GeneratedSticker?
    public private(set) var isGenerating = false
    public private(set) var lastError: String?

    private let service: StickerGenerationService
    private let voiceService: VoiceTranscriptionService

    public init(
        prompt: String = "",
        service: StickerGenerationService = MockStickerGenerationService(),
        voiceService: VoiceTranscriptionService = MockVoiceTranscriptionService()
    ) {
        self.prompt = prompt
        self.service = service
        self.voiceService = voiceService
    }

    public var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    public func generate() async {
        guard canGenerate else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            generated = try await service.generateSticker(prompt: prompt)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A3: the mic glyph dictates into the prompt field. Reuses the
    /// isGenerating flag so a double-tap cannot append twice.
    public func dictate() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let transcript = try await voiceService.transcribe()
            prompt = prompt.isEmpty ? transcript : prompt + " " + transcript
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

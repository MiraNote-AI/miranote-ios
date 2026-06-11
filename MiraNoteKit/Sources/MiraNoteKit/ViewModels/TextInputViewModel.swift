import Foundation
import Observation

/// Text input sheet (sketch 2.1): editor + voice/clean/expand/polish row.
@MainActor
@Observable
public final class TextInputViewModel {
    public var text: String
    public private(set) var isProcessing = false
    public private(set) var lastError: String?

    private let textService: TextTransformService
    private let voiceService: VoiceTranscriptionService

    public init(
        text: String = "",
        textService: TextTransformService = MockTextTransformService(),
        voiceService: VoiceTranscriptionService = MockVoiceTranscriptionService()
    ) {
        self.text = text
        self.textService = textService
        self.voiceService = voiceService
    }

    public var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func apply(_ mode: TextTransformMode) async {
        guard canSubmit, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            text = try await textService.transform(text, mode: mode)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func dictate() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let transcript = try await voiceService.transcribe()
            text = text.isEmpty ? transcript : text + "\n" + transcript
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

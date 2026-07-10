import Foundation
import Observation

/// AI Sticker sheet (sketch 2.2, split out per D2).
@MainActor
@Observable
public final class AIStickerViewModel {
    public var prompt: String
    public private(set) var generated: GeneratedSticker?
    public private(set) var isGenerating = false
    public private(set) var isRecording = false
    public private(set) var lastError: String?

    private let service: StickerGenerationService
    private let voiceService: VoiceTranscriptionService
    private let recorder: AudioRecording

    public init(
        prompt: String = "",
        service: StickerGenerationService = MockStickerGenerationService(),
        voiceService: VoiceTranscriptionService = MockVoiceTranscriptionService(),
        recorder: AudioRecording? = nil
    ) {
        self.prompt = prompt
        self.service = service
        self.voiceService = voiceService
        self.recorder = recorder ?? AudioRecorder()
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

    /// A3: the mic glyph dictates into the prompt field. Tap to start, tap
    /// again to stop and transcribe (D7).
    public func toggleDictation() async {
        if isRecording {
            await finishDictation()
        } else {
            await startDictation()
        }
    }

    private func startDictation() async {
        guard !isGenerating else { return }
        do {
            try await recorder.start()
            isRecording = true
            lastError = nil
        } catch {
            isRecording = false
            lastError = error.localizedDescription
        }
    }

    private func finishDictation() async {
        guard isRecording else { return }
        isRecording = false
        isGenerating = true
        defer { isGenerating = false }
        do {
            let audio = try await recorder.stop()
            let transcript = try await voiceService.transcribe(audio: audio, filename: "recording.m4a")
            prompt = prompt.isEmpty ? transcript : prompt + " " + transcript
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

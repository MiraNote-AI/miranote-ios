import Foundation
import Observation

/// Text input sheet (sketch 2.1): editor + voice/clean/expand/polish row.
@MainActor
@Observable
public final class TextInputViewModel {
    public var text: String
    public private(set) var isProcessing = false
    public private(set) var isRecording = false
    public private(set) var lastError: String?

    private let textService: TextTransformService
    private let voiceService: VoiceTranscriptionService
    private let recorder: AudioRecording

    public init(
        text: String = "",
        textService: TextTransformService = MockTextTransformService(),
        voiceService: VoiceTranscriptionService = MockVoiceTranscriptionService(),
        recorder: AudioRecording? = nil
    ) {
        self.text = text
        self.textService = textService
        self.voiceService = voiceService
        self.recorder = recorder ?? AudioRecorder()
    }

    public var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func apply(_ mode: TextTransformMode) async {
        guard canSubmit, !isProcessing, !isRecording else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            text = try await textService.transform(text, mode: mode)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Tap to start recording, tap again to stop and transcribe (D7). The
    /// transcript is appended to the editor text.
    public func toggleDictation() async {
        if isRecording {
            await finishDictation()
        } else {
            await startDictation()
        }
    }

    private func startDictation() async {
        guard !isProcessing else { return }
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
        isProcessing = true
        defer { isProcessing = false }
        do {
            let audio = try await recorder.stop()
            let transcript = try await voiceService.transcribe(audio: audio, filename: "recording.m4a")
            text = text.isEmpty ? transcript : text + "\n" + transcript
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

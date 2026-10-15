import Foundation
import Observation

/// Hold-to-talk progress in the chat composer.
public enum ChatVoiceState: Equatable, Sendable {
    case idle
    case recording(since: Date)
    case transcribing
}

/// A one-line note above the composer: why a voice clip or a photo did not
/// land the way the user expected.
public struct ChatHint: Equatable, Sendable {
    public let text: String
    /// The fix is in iOS Settings (microphone access was turned off).
    public let opensSettings: Bool

    public init(text: String, opensSettings: Bool = false) {
        self.text = text
        self.opensSettings = opensSettings
    }

    public static let noWords = ChatHint(text: "I couldn't catch any words -- try again?")
    public static let transcriberUnreachable = ChatHint(text: "Couldn't reach the transcriber -- try again?")
    public static let photoUnseen = ChatHint(text: "Mira couldn't look at that photo -- she answered from your words.")
}

/// Drives the MiraNote AI conversation: holds the transcript, sends the user's
/// message, and appends the assistant's reply. Seeded once with the text the
/// user typed on Home.
///
/// The composer can also dictate into the draft (hold to talk: the transcript
/// fills the field for editing, it is never sent on release) and stage photos.
/// The chat backend is text-only, so a staged photo is described by the image
/// service and the description rides with the message as "(photo) ..." --
/// the same convention `ChatNote(page:)` uses for photos on a page.
@MainActor
@Observable
public final class ChatViewModel {
    public static let maxStagedImages = 4

    public private(set) var messages: [ChatMessage] = []
    public var draft = ""
    public private(set) var isResponding = false
    public private(set) var stagedImages: [Data] = []
    public private(set) var voice: ChatVoiceState = .idle
    public var hint: ChatHint?

    private let service: ChatService
    private let studio: ImageStudioService
    private let transcription: VoiceTranscriptionService
    private let makeRecorder: @MainActor () -> AudioRecording
    private let imageStore: ImageFileStore
    /// Selects the user's own pages to ground each message in (journal
    /// mode). Injected by the screen that owns the library.
    private let notesForMessage: (String) -> [ChatNote]
    private var sessionID: String?
    private var didSeed = false
    private var recorder: AudioRecording?
    /// Resolves to whether the mic actually started; a release can come
    /// before it has.
    private var recorderStart: Task<Bool, Never>?

    public init(
        service: ChatService,
        studio: ImageStudioService,
        transcription: VoiceTranscriptionService,
        makeRecorder: @escaping @MainActor () -> AudioRecording,
        imageStore: ImageFileStore,
        notesForMessage: @escaping (String) -> [ChatNote] = { _ in [] }
    ) {
        self.service = service
        self.studio = studio
        self.transcription = transcription
        self.makeRecorder = makeRecorder
        self.imageStore = imageStore
        self.notesForMessage = notesForMessage
    }

    public var canSend: Bool {
        let hasWords = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasWords || !stagedImages.isEmpty) && !isResponding
    }

    public var canStageMoreImages: Bool { stagedImages.count < Self.maxStagedImages }

    /// Send the first message exactly once (the Home hand-off text).
    public func seedIfNeeded(_ text: String?) async {
        guard !didSeed else { return }
        didSeed = true
        if let text { await send(text) }
    }

    public func sendDraft() async {
        // Return reaches here even while the Send pill is disabled: a second
        // message mid-answer would go out without the session and start a
        // new one. The draft stays for when Mira has answered.
        guard canSend else { return }
        let text = draft
        let images = stagedImages
        draft = ""
        stagedImages = []
        await send(text, images: images)
    }

    public func send(_ text: String, images: [Data] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        let fileNames = images.compactMap { try? imageStore.save($0, id: UUID()) }
        messages.append(ChatMessage(role: .user, text: trimmed, imageFileNames: fileNames))
        isResponding = true
        defer { isResponding = false }
        let outgoing = await withPhotoDescriptions(trimmed, images: images)
        do {
            let reply = try await service.reply(
                to: outgoing,
                sessionID: sessionID,
                notes: notesForMessage(trimmed.isEmpty ? outgoing : trimmed)
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

    /// One "(photo) <description>" line per photo, then the user's words.
    /// A photo the service could not describe still says it is there, and
    /// the user is told Mira did not see it.
    private func withPhotoDescriptions(_ text: String, images: [Data]) async -> String {
        guard !images.isEmpty else { return text }
        var lines: [String] = []
        for image in images {
            let summary = (try? await studio.describe(image: image))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if summary.isEmpty {
                lines.append("(photo) a photo Mira could not look at")
                hint = .photoUnseen
            } else {
                lines.append("(photo) " + summary)
            }
        }
        if !text.isEmpty { lines.append(text) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Photos

    public func stageImage(_ data: Data) {
        guard canStageMoreImages else { return }
        stagedImages.append(data)
    }

    public func removeStagedImage(at index: Int) {
        guard stagedImages.indices.contains(index) else { return }
        stagedImages.remove(at: index)
    }

    // MARK: - Voice

    /// Adds dictated words to the draft for the user to edit before
    /// sending. Returns false when there were no words.
    @discardableResult
    public func insertTranscript(_ transcript: String) -> Bool {
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return false }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = words
        } else {
            draft += (draft.hasSuffix(" ") || draft.hasSuffix("\n") ? "" : " ") + words
        }
        return true
    }

    /// Press: the mic opens.
    public func startVoice() {
        guard voice == .idle else { return }
        hint = nil
        let recorder = makeRecorder()
        self.recorder = recorder
        voice = .recording(since: Date())
        recorderStart = Task {
            do {
                try await recorder.start()
                return true
            } catch {
                hint = ChatHint(
                    text: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    opensSettings: (error as? RecordingError) == .microphonePermissionDenied
                )
                if case .recording = voice {
                    voice = .idle
                    self.recorder = nil
                }
                return false
            }
        }
    }

    /// Release: transcribe and add the words to the draft.
    public func finishVoice() async {
        guard case .recording = voice, let recorder else { return }
        self.recorder = nil
        voice = .transcribing
        defer { voice = .idle }
        let started = await recorderStart?.value ?? false
        recorderStart = nil
        // A failed start already said why.
        guard started else { return }
        guard let audio = try? await recorder.stop(), !audio.isEmpty else {
            hint = .noWords
            return
        }
        guard let transcript = try? await transcription.transcribe(
            audio: audio, filename: "chat-dictation.m4a"
        ) else {
            hint = .transcriberUnreachable
            return
        }
        if !insertTranscript(transcript) { hint = .noWords }
    }

    /// Slid away before releasing: stop the mic quietly, keep nothing.
    public func cancelVoice() {
        guard case .recording = voice, let recorder else { return }
        self.recorder = nil
        voice = .idle
        let start = recorderStart
        recorderStart = nil
        Task {
            guard await start?.value == true else { return }
            _ = try? await recorder.stop()
        }
    }
}

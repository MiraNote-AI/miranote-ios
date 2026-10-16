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
    public static let photoNotLoaded = ChatHint(text: "That photo couldn't be loaded. Try another?")
}

/// A photo staged in the composer; the id lets the view decode its
/// thumbnail once.
public struct StagedPhoto: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let data: Data
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
    // internal(set): ChatViewModel+Photos.swift stages and loads them.
    public internal(set) var staged: [StagedPhoto] = []
    public var stagedImages: [Data] { staged.map(\.data) }
    /// Picks still loading (iCloud originals): Send waits for them, each
    /// shows a placeholder that can remove it.
    public internal(set) var loadingPicks: [UUID] = []
    public var loadingImages: Int { loadingPicks.count }
    /// Picks that arrived while one picked before them still loads.
    @ObservationIgnored var arrivedPicks: [UUID: Data?] = [:]
    /// The batch (one picker pick) each loading pick came in.
    @ObservationIgnored var pickBatches: [UUID: UUID] = [:]
    public private(set) var voice: ChatVoiceState = .idle
    public var hint: ChatHint?

    private let service: ChatService
    private let studio: ImageStudioService
    private let transcription: VoiceTranscriptionService
    private let makeRecorder: @MainActor () -> AudioRecording
    let imageStore: ImageFileStore
    /// How long the photos' descriptions may hold a message (all of them
    /// together, as the canvas caps its look at the page).
    private let describeTimeout: Duration
    /// How long one pick may load before it counts as failed: an iCloud
    /// original that never arrives must not hold Send for good.
    let pickTimeout: Duration
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
        describeTimeout: Duration = .seconds(8),
        pickTimeout: Duration = .seconds(20),
        notesForMessage: @escaping (String) -> [ChatNote] = { _ in [] }
    ) {
        self.service = service
        self.studio = studio
        self.transcription = transcription
        self.makeRecorder = makeRecorder
        self.imageStore = imageStore
        self.describeTimeout = describeTimeout
        self.pickTimeout = pickTimeout
        self.notesForMessage = notesForMessage
    }

    public var canSend: Bool {
        let hasWords = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasWords || !staged.isEmpty) && !isResponding && loadingImages == 0
    }

    public var canStageMoreImages: Bool { staged.count + loadingImages < Self.maxStagedImages }

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
        staged = []
        await send(text, images: images)
    }

    public func send(_ text: String, images: [Data] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // One message at a time (the quick chips come here directly): a
        // second one mid-answer would go out without the session.
        guard !trimmed.isEmpty || !images.isEmpty, !isResponding else { return }
        let fileNames = images.compactMap { try? imageStore.save($0, id: UUID()) }
        messages.append(ChatMessage(role: .user, text: trimmed, imageFileNames: fileNames))
        isResponding = true
        defer { isResponding = false }
        let summaries = await describe(images)
        let outgoing = withPhotoDescriptions(trimmed, summaries: summaries)
        // Pages are searched with words the user said or a photo showed --
        // never with the app's own "could not look at" line.
        let query = trimmed.isEmpty ? summaries.filter { !$0.isEmpty }.joined(separator: "\n") : trimmed
        do {
            let reply = try await service.reply(
                to: outgoing,
                sessionID: sessionID,
                notes: query.isEmpty ? [] : notesForMessage(query)
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
    /// A photo the service could not describe (or not within the cap) still
    /// says it is there, and the user is told Mira did not see it.
    private func withPhotoDescriptions(_ text: String, summaries: [String]) -> String {
        guard !summaries.isEmpty else { return text }
        var lines: [String] = []
        for summary in summaries {
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

    /// The photos' descriptions in pick order, looked at side by side; any
    /// not back within `describeTimeout` (or failed) is "".
    private func describe(_ images: [Data]) async -> [String] {
        guard !images.isEmpty else { return [] }
        let studio = self.studio
        let cap = describeTimeout
        var summaries = Array(repeating: "", count: images.count)
        await withTaskGroup(of: (Int, String)?.self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let summary = (try? await studio.describe(image: image)) ?? ""
                    return (index, summary.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            // Vision takes seconds; never hold a message hostage longer.
            group.addTask {
                try? await Task.sleep(for: cap)
                return nil
            }
            var pending = images.count
            while pending > 0, let next = await group.next() {
                // nil: the cap ran out first.
                guard let described = next else { break }
                summaries[described.0] = described.1
                pending -= 1
            }
            group.cancelAll()
        }
        return summaries
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

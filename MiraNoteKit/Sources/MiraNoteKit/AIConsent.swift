import Foundation
import Observation

/// Whether the writer agreed to send page content to the AI providers
/// (#151, App Store Review Guideline 5.1.2(i)), and whether their pages'
/// moods are read. Kept in the settings' defaults (`AppSettings.storeDefaults`).
///
/// Nothing is sent before `isGranted`: the services `ServiceContainer.asking`
/// wraps ask first. `permit()` shows the "How Mira uses AI" sheet through
/// `present` and waits for the answer; the sheet calls `answer(_:)`. "Not
/// now" is not remembered: the next AI action asks again.
@MainActor
@Observable
public final class AIConsent {
    /// The app's one instance. A UI test starts consented, so suites that
    /// are not about this sheet are never stopped by it -- unless it
    /// launches with `-AI-CONSENT-ASK`, or withdrew before its own relaunch.
    public static let shared: AIConsent = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITEST") {
            return AIConsent(defaults: AppSettings.storeDefaults,
                             grantedByDefault: !arguments.contains("-AI-CONSENT-ASK"))
        }
        #endif
        return AIConsent(defaults: AppSettings.storeDefaults)
    }()

    enum Key {
        static let granted = "miranote.ai.consent"
        static let moodFromWords = "miranote.ai.moodFromWords"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public private(set) var isGranted: Bool {
        didSet { defaults.set(isGranted, forKey: Key.granted) }
    }

    /// Settings > AI & privacy > "Mood from my words". On by default; it
    /// reads moods only while `isGranted` too (`allowsMood`).
    public var moodFromWords: Bool {
        didSet { defaults.set(moodFromWords, forKey: Key.moodFromWords) }
    }

    /// Whether saved pages' words go to the text service for their mood.
    public var allowsMood: Bool { isGranted && moodFromWords }

    /// The sheet is up, waiting for `answer(_:)`.
    public private(set) var isAsking = false

    /// Requests let through to a service since launch: the UI tests'
    /// ground truth for "Not now sends nothing".
    public private(set) var sentRequests = 0

    /// Shows the sheet. Unset, nobody can answer, so nothing is sent.
    @ObservationIgnored public var present: (@MainActor () -> Void)?

    @ObservationIgnored private var waiting: [CheckedContinuation<Bool, Never>] = []

    public init(defaults: UserDefaults, grantedByDefault: Bool = false) {
        self.defaults = defaults
        isGranted = (defaults.object(forKey: Key.granted) as? Bool) ?? grantedByDefault
        moodFromWords = (defaults.object(forKey: Key.moodFromWords) as? Bool) ?? true
    }

    /// True at once when granted. Otherwise shows the sheet (once for any
    /// number of requests waiting together) and returns its answer.
    public func permit() async -> Bool {
        if isGranted { return true }
        guard let present else { return false }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if !isAsking {
                isAsking = true
                present()
            }
        }
    }

    /// The sheet's answer: Continue (`true`) is kept, Not now only ends
    /// this ask.
    public func answer(_ granted: Bool) {
        if granted { isGranted = true }
        isAsking = false
        let answered = waiting
        waiting = []
        for continuation in answered { continuation.resume(returning: granted) }
    }

    /// Settings' "Stop sending to AI": the sheet shows again before the
    /// next AI action.
    public func withdraw() {
        isGranted = false
    }

    /// Asks if needed; throws `AIConsentError.notNow` unless granted.
    func clearToSend() async throws {
        guard await permit() else { throw AIConsentError.notNow }
        sentRequests += 1
    }

    /// For work the writer did not just ask for -- a page's mood
    /// (`allowsMood`), a photo's description (`isGranted`): never shows the
    /// sheet.
    func clearToSendQuietly(forMood: Bool) throws {
        guard forMood ? allowsMood : isGranted else { throw AIConsentError.notNow }
        sentRequests += 1
    }
}

/// An AI action that did not run because the writer has not agreed yet.
public enum AIConsentError: Error, LocalizedError, Equatable {
    case notNow

    public var errorDescription: String? {
        String(appCopy: "Mira needs your OK to use AI. You can turn it on in Settings.")
    }
}

// MARK: - Services that ask first

public extension ServiceContainer {
    /// These services, each asking `consent` before anything leaves the
    /// phone. A plain cutout and the outline run on the phone in the live
    /// studio (`LiveImageStudioService.cutsLocally`, `.outlinesLocally`) and
    /// pass without asking; mocks are treated the same. Sticker generation
    /// and style transfer are mocks with no backend and stay as they are.
    func asking(_ consent: AIConsent) -> ServiceContainer {
        let live = imageStudio as? LiveImageStudioService
        return ServiceContainer(
            textTransform: AskingTextTransform(base: textTransform, consent: consent),
            voiceTranscription: AskingTranscription(base: voiceTranscription, consent: consent),
            stickerGeneration: stickerGeneration,
            styleTransfer: styleTransfer,
            chat: AskingChat(base: chat, consent: consent),
            imageStudio: AskingImageStudio(
                base: imageStudio, consent: consent,
                localCutout: live?.cutsLocally ?? true,
                localOutline: live?.outlinesLocally ?? true
            ),
            mood: AskingMood(base: mood, consent: consent)
        )
    }
}

struct AskingTextTransform: TextTransformService {
    let base: TextTransformService
    let consent: AIConsent

    func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        try await consent.clearToSend()
        return try await base.transform(text, mode: mode)
    }
}

struct AskingTranscription: VoiceTranscriptionService {
    let base: VoiceTranscriptionService
    let consent: AIConsent

    func transcribe(audio: Data, filename: String) async throws -> String {
        try await consent.clearToSend()
        return try await base.transcribe(audio: audio, filename: filename)
    }

    func askToSend() async -> Bool { await consent.permit() }
}

struct AskingChat: ChatService {
    let base: ChatService
    let consent: AIConsent

    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        try await consent.clearToSend()
        return try await base.reply(to: message, sessionID: sessionID, notes: notes, page: page)
    }

    func askToSend() async -> Bool { await consent.permit() }
}

/// A page's mood is read after Save, never on request: it does not show
/// the sheet (HomeFlow asks once after a Save instead).
struct AskingMood: MoodService {
    let base: MoodService
    let consent: AIConsent

    func mood(for text: String) async throws -> Mood {
        try await consent.clearToSendQuietly(forMood: true)
        return try await base.mood(for: text)
    }
}

struct AskingImageStudio: ImageStudioService {
    let base: ImageStudioService
    let consent: AIConsent
    let localCutout: Bool
    let localOutline: Bool

    func prepare() { base.prepare() }

    func askToSend() async -> Bool { await consent.permit() }

    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        try await consent.clearToSend()
        return try await base.generate(kind: kind, prompt: prompt)
    }

    func generateStickers(prompt: String) async throws -> StickerGeneration {
        try await consent.clearToSend()
        return try await base.generateStickers(prompt: prompt)
    }

    func cutout(image: Data, target: String?) async throws -> Data {
        let named = !(target ?? "").isEmpty
        if named || !localCutout { try await consent.clearToSend() }
        return try await base.cutout(image: image, target: target)
    }

    func stylize(image: Data, instruction: String) async throws -> Data {
        try await consent.clearToSend()
        return try await base.stylize(image: image, instruction: instruction)
    }

    func outline(image: Data) async throws -> Data {
        if !localOutline { try await consent.clearToSend() }
        return try await base.outline(image: image)
    }

    /// A placed photo is described in the background for Mira's context:
    /// only once granted, never with the sheet.
    func describe(image: Data) async throws -> String {
        try await consent.clearToSendQuietly(forMood: false)
        return try await base.describe(image: image)
    }
}

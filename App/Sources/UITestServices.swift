#if DEBUG
import Foundation
import MiraNoteKit
import SwiftUI
import UIKit

extension ServiceContainer {
    /// Deterministic services for -UITEST runs: text transforms use the
    /// instant mock; chat and sticker making are keyword-scripted so the
    /// working states, Stop, and the failure card can each be driven on
    /// purpose.
    static let uiTestScripted = ServiceContainer(
        textTransform: MockTextTransformService(),
        voiceTranscription: UITestScriptedTranscription(),
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

    /// Slower by `-GENERATE_DELAY <ms>`: a picture or backdrop being painted.
    /// A prompt with "fail" throws, as an unreachable backend does.
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        let delay = UserDefaults.standard.integer(forKey: "GENERATE_DELAY")
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        if prompt.lowercased().contains("fail") { throw URLError(.notConnectedToInternet) }
        return try await mock.generate(kind: kind, prompt: prompt)
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

    /// Slower by `-AI_EDIT_DELAY <ms>`: an AI photo edit still running.
    func stylize(image: Data, instruction: String) async throws -> Data {
        let delay = UserDefaults.standard.integer(forKey: "AI_EDIT_DELAY")
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        return try await mock.stylize(image: image, instruction: instruction)
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

/// The mock transcriber, slower by `-TRANSCRIBE_DELAY <ms>` so a test can
/// act while the words are on their way ("Writing it down..."), or with
/// only the process's first take held (`-TRANSCRIBE_FIRST_DELAY <ms>`).
/// `-NUMBER_TAKES` ends each take's words with its number, in the order
/// the takes were let go; `-FAIL_FIRST_TAKE` fails the first take.
struct UITestScriptedTranscription: VoiceTranscriptionService {
    private let mock = MockVoiceTranscriptionService()
    @MainActor private static var takes = 0

    func transcribe(audio: Data, filename: String) async throws -> String {
        let take = await Self.countTake()
        let delay = UserDefaults.standard.integer(forKey: "TRANSCRIBE_DELAY")
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        let first = UserDefaults.standard.integer(forKey: "TRANSCRIBE_FIRST_DELAY")
        if first > 0, take == 1 { try await Task.sleep(for: .milliseconds(first)) }
        let arguments = ProcessInfo.processInfo.arguments
        if take == 1, arguments.contains("-FAIL_FIRST_TAKE") { throw URLError(.notConnectedToInternet) }
        let words = try await mock.transcribe(audio: audio, filename: filename)
        return arguments.contains("-NUMBER_TAKES") ? "\(words) #\(take)" : words
    }

    @MainActor private static func countTake() -> Int {
        takes += 1
        return takes
    }
}

/// "slowly" holds the turn long enough to show the working bar; "fail"
/// throws; anything else replies instantly -- or after `-CHAT_DELAY <ms>`,
/// so a test can act while a canvas ask (a title) is on its way.
struct UITestScriptedChat: ChatService {
    func reply(
        to message: String, sessionID: String?,
        notes: [ChatNote], page: PageContext?
    ) async throws -> ChatReply {
        let delay = UserDefaults.standard.integer(forKey: "CHAT_DELAY")
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
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

/// The chat's camera cover under `-UITEST -CAMERA_COVER`: the system camera
/// cannot be driven, so "Use Photo" stages a canned photo and closes it.
struct UITestCameraStub: View {
    let onUse: () -> Void

    var body: some View {
        Button("Use Photo", action: onUse)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .accessibilityIdentifier("camera.stub.use")
    }
}

/// -UITEST probe counters for render cost: how often the canvas scene's
/// body ran, and how often an on-screen image was decoded. A drag must not
/// move either per frame.
enum RenderCounters {
    // Bumped and read on the main thread (view bodies, the image cache's
    // main-thread callers); a test counter, not state.
    nonisolated(unsafe) static var canvasSceneBodies = 0
    nonisolated(unsafe) static var displayImageDecodes = 0
}

/// -UITEST only: a scene's state as JSON on an invisible element, for the
/// monkey (MonkeyUITests) to check its invariants after every event.
struct DebugStateProbe: View {
    let state: () -> [String: Any]

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let json = Self.json(state())
                Text(json)
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .accessibilityLabel(json)
                    // Not a static text: the JSON holds every element's
                    // words, and a test's staticTexts query by label must
                    // find the element, never the probe.
                    .accessibilityRemoveTraits(.isStaticText)
                    .accessibilityIdentifier("debug.state")
            }
        }
    }

    static func json(_ state: [String: Any]) -> String {
        var state = state
        // Ground truth for "no microphone left on": every mock recorder on.
        state["micLive"] = MockAudioRecorder.liveCount
        state["sceneBodies"] = RenderCounters.canvasSceneBodies
        state["imageDecodes"] = RenderCounters.displayImageDecodes
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// -UITEST only: how many sent chat photos are on disk (the folder is the
/// process's own), for a test to read from the chat or from Home.
struct ChatPhotoFilesProbe: View {
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let files = try? FileManager.default.contentsOfDirectory(atPath: MiraChatView.photoDirectory.path)
                Text("\(files?.count ?? 0)")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("debug.chatPhotoFiles")
            }
        }
    }
}
#endif

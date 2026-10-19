import Foundation
@testable import MiraNoteKit

/// The chat composer's hold to talk with a gated microphone and
/// transcriber: presses, releases and slide-away cancels in any order with
/// the mic coming up (or failing) and the words coming back (or not) at any
/// point.
///
/// Invariants, after every step:
/// - never two microphones on; none on once the composer is idle and no
///   mic is still coming up;
/// - "Transcribing..." never sticks once nothing is held;
/// - each take's words land in the draft at most once, and only a released
///   take is transcribed.
@MainActor
final class ChatVoiceModel: SequenceModel {
    enum Action {
        case press, release, cancel
        case micUp, micFails
        case words, wordsFail
    }

    private let mics = MicLedger()
    private let transcriber = GatedTranscription()
    private let viewModel: ChatViewModel
    private let imageDirectory: URL
    private var finishing: [Task<Void, Never>] = []
    private var released = 0
    private var transcripts = 0
    private var problems: [String] = []

    init(seed: UInt64) async {
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatVoiceModel-\(seed)-\(UUID().uuidString)", isDirectory: true)
        let mics = self.mics
        viewModel = ChatViewModel(
            service: MessageCapturingChat(), studio: MockImageStudioService(), transcription: transcriber,
            makeRecorder: { mics.makeRecorder() }, imageStore: ImageFileStore(directory: imageDirectory)
        )
    }

    func nextAction(_ rng: inout SeededRandom) -> Action {
        rng.pick([
            (.press, 5), (.release, 4), (.cancel, 2),
            (.micUp, mics.starts.pending > 0 ? 5 : 0), (.micFails, mics.starts.pending > 0 ? 1 : 0),
            (.words, transcriber.calls.pending > 0 ? 5 : 0), (.wordsFail, transcriber.calls.pending > 0 ? 1 : 0)
        ])
    }

    func apply(_ action: Action) async {
        switch action {
        case .press:
            viewModel.startVoice()
        case .release:
            if case .recording = viewModel.voice { released += 1 }
            finishing.append(Task { await viewModel.finishVoice() })
        case .cancel:
            viewModel.cancelVoice()
        case .micUp:
            mics.starts.releaseNext(.success(()))
        case .micFails:
            mics.starts.releaseNext(.failure(GateError()))
        case .words:
            transcripts += 1
            transcriber.calls.releaseNext(.success("w\(transcripts)"))
        case .wordsFail:
            transcriber.calls.releaseNext(.failure(GateError()))
        }
        // Let whatever the step set going run up to its next held gate.
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .microseconds(300))
    }

    func violations() async -> [String] {
        var found = problems
        problems = []
        if mics.live > 1 { found.append("\(mics.live) microphones on") }
        let held = mics.starts.pending > 0 || transcriber.calls.pending > 0
        if viewModel.voice == .idle, mics.starts.pending == 0 {
            if !(await eventually(timeout: .milliseconds(500)) { mics.live == 0 }) {
                found.append("a microphone left on with the composer idle")
            }
        }
        if viewModel.voice == .transcribing, !held {
            if !(await eventually(timeout: .milliseconds(500)) { viewModel.voice == .idle }) {
                found.append("Transcribing... stuck with nothing held")
            }
        }
        if transcriber.calls.count > released {
            found.append("\(transcriber.calls.count) takes transcribed, only \(released) released")
        }
        let words = viewModel.draft.split(separator: " ").map(String.init)
        if Set(words).count != words.count { found.append("words landed twice: \(viewModel.draft)") }
        return found
    }

    func finish() async -> [String] {
        mics.starts.releaseAll(.success(()))
        transcriber.calls.releaseAll(.success("end"))
        for task in finishing { await task.value }
        viewModel.cancelVoice()
        var found = await violations()
        if !(await eventually(timeout: .milliseconds(500)) { mics.live == 0 }) {
            found.append("a microphone left on at the end")
        }
        return found
    }

    func tearDown() async {
        mics.starts.releaseAll(.failure(GateError()))
        transcriber.calls.releaseAll(.failure(GateError()))
        for task in finishing { await task.value }
        try? FileManager.default.removeItem(at: imageDirectory)
    }

    func trace() -> String {
        "  voice \(viewModel.voice) live \(mics.live) made \(mics.made) starts held \(mics.starts.pending) "
            + "words held \(transcriber.calls.pending) draft \"\(viewModel.draft)\""
    }
}

import Foundation
@testable import MiraNoteKit

/// The chat composer's photo staging: picker batches whose picks load
/// through gates, arriving, failing or stalling in any order, removed from
/// their placeholder, their batch cancelled, staged photos removed, words
/// typed, Send.
///
/// Invariants, after every step (each released pick given time to land):
/// - Send is never held forever: with no pick still loading, nothing waits;
/// - no photo is lost or duplicated: a pick that loaded is staged or sent
///   exactly once (unless removed, or its batch was cancelled), and a pick
///   that failed or was removed never shows up;
/// - order is kept within a batch;
/// - never more than four photos staged and loading together;
/// - `canSend` says what Send does.
@MainActor
final class ChatStagingModel: SequenceModel {
    enum Action {
        case pick(count: Int)
        case arrive(Int)
        case fail(Int)
        case remove(Int)
        case cancelBatch(Int)
        case removeStaged(Int)
        case type
        case clear
        case send
    }

    private enum State: Equatable {
        case held, arrived, failed, removed, notAccepted
    }

    private struct Pick {
        let number: Int
        let batch: Int
        let gate = GateQueue<Data?>()
        var id: UUID?
        var state: State = .held
    }

    private struct Batch {
        let task: Task<Void, Never>
        var cancelled = false
    }

    private let chat = MessageCapturingChat()
    private let viewModel: ChatViewModel
    private let imageDirectory: URL
    private var picks: [Pick] = []
    private var batches: [Batch] = []
    /// Pick numbers in the order they reached the staged strip.
    private var stagedLog: [Int] = []
    private var sent: [Int] = []
    private var removedStaged: [Int] = []
    private var problems: [String] = []

    init(seed: UInt64) async {
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatStagingModel-\(seed)-\(UUID().uuidString)", isDirectory: true)
        viewModel = ChatViewModel(
            service: chat, studio: NumberDescribingStudio(), transcription: MockVoiceTranscriptionService(),
            makeRecorder: { MockAudioRecorder() }, imageStore: ImageFileStore(directory: imageDirectory),
            describeTimeout: .seconds(30), pickTimeout: .seconds(60)
        )
    }

    // MARK: Generation

    func nextAction(_ rng: inout SeededRandom) -> Action {
        let held = picks.filter { $0.state == .held && $0.id != nil }.count
        let options: [(Int, Int)] = [
            (0, 5), (1, held > 0 ? 8 : 0), (2, held > 0 ? 3 : 0), (3, viewModel.loadingImages > 0 ? 3 : 0),
            (4, batches.contains { !$0.cancelled } ? 1 : 0), (5, viewModel.staged.isEmpty ? 0 : 2),
            (6, 2), (7, 1), (8, 4)
        ]
        switch rng.pick(options) {
        case 0: return .pick(count: rng.int(1...4))
        case 1: return .arrive(rng.int(0...7))
        case 2: return .fail(rng.int(0...7))
        case 3: return .remove(rng.int(0...7))
        case 4: return .cancelBatch(rng.int(0...7))
        case 5: return .removeStaged(rng.int(0...3))
        case 6: return .type
        case 7: return .clear
        default: return .send
        }
    }

    // MARK: Applying

    func apply(_ action: Action) async {
        let stagedBefore = numbers(viewModel.staged)
        switch action {
        case .pick(let count):
            await pick(count)
        case .arrive(let index):
            await release(index, loaded: true)
        case .fail(let index):
            await release(index, loaded: false)
        case .remove(let index):
            let loading = viewModel.loadingPicks
            guard !loading.isEmpty else { break }
            let id = loading[index % loading.count]
            viewModel.removeLoadingPick(id)
            if let at = picks.firstIndex(where: { $0.id == id }) { picks[at].state = .removed }
        case .cancelBatch(let index):
            let running = batches.indices.filter { !batches[$0].cancelled }
            guard !running.isEmpty else { break }
            let batch = running[index % running.count]
            batches[batch].cancelled = true
            batches[batch].task.cancel()
            if !(await finished(batches[batch].task)) {
                problems.append("a cancelled pick batch did not finish")
            }
        case .removeStaged(let index):
            guard !viewModel.staged.isEmpty else { break }
            let at = index % viewModel.staged.count
            removedStaged += numbers([viewModel.staged[at]])
            viewModel.removeStagedImage(at: at)
        case .type:
            viewModel.draft = "what is this?"
        case .clear:
            viewModel.draft = ""
        case .send:
            await send()
        }
        let stagedNow = numbers(viewModel.staged)
        stagedLog += stagedNow.filter { !stagedBefore.contains($0) }
    }

    private func pick(_ count: Int) async {
        let room = max(0, ChatViewModel.maxStagedImages - viewModel.staged.count - viewModel.loadingImages)
        let batch = batches.count
        let first = picks.count
        for offset in 0..<count {
            picks.append(Pick(number: first + offset + 1, batch: batch))
        }
        let loaders: [@Sendable () async -> Data?] = picks[first...].map { pick in
            let gate = pick.gate
            return { await gate.wait() }
        }
        let before = viewModel.loadingPicks
        // Its first part (room, placeholders) runs at once once it starts.
        let started = Flag()
        let task = Task {
            started.value = true
            await viewModel.stagePhotos(loaders)
        }
        batches.append(Batch(task: task))
        let accepted = min(count, room)
        if !(await eventually { started.value }) || viewModel.loadingPicks.count < before.count + accepted {
            problems.append("a batch's picks never showed as loading")
        }
        let ids = viewModel.loadingPicks.filter { !before.contains($0) }
        for offset in 0..<count {
            if offset < ids.count {
                picks[first + offset].id = ids[offset]
            } else {
                picks[first + offset].state = .notAccepted
            }
        }
    }

    /// Lets the k-th held pick load (or fail), and waits until the staging
    /// has taken it: staged, failed, or arrived and waiting its turn.
    private func release(_ index: Int, loaded: Bool) async {
        let held = picks.indices.filter { picks[$0].state == .held && picks[$0].id != nil }
        guard !held.isEmpty else { return }
        let at = held[index % held.count]
        let number = picks[at].number
        picks[at].gate.releaseNext(loaded ? Self.data(number) : nil)
        picks[at].state = loaded ? .arrived : .failed
        guard let id = picks[at].id, viewModel.loadingPicks.contains(id) else { return }
        let landed = await eventually {
            !viewModel.loadingPicks.contains(id) || viewModel.arrivedPicks[id] != nil
        }
        if !landed { problems.append("pick \(number) was let go but never reached the staging") }
    }

    private func send() async {
        let couldSend = viewModel.canSend
        let staged = numbers(viewModel.staged)
        let count = await chat.messages.all.count
        await viewModel.sendDraft()
        let messages = await chat.messages.all
        guard couldSend else {
            if messages.count != count { problems.append("Send went out while canSend was false") }
            return
        }
        guard messages.count == count + 1, let message = messages.last else {
            problems.append("Send with canSend true sent nothing")
            return
        }
        let photos = message.split(separator: "\n").compactMap { line -> Int? in
            guard line.hasPrefix("(photo) p") else { return nil }
            return Int(line.dropFirst("(photo) p".count))
        }
        if photos != staged {
            problems.append("Send carried photos \(photos), the strip showed \(staged)")
        }
        sent += photos
    }

    // MARK: Invariants

    func violations() async -> [String] {
        var found = problems
        problems = []
        let staged = numbers(viewModel.staged)
        if staged.count + viewModel.loadingImages > ChatViewModel.maxStagedImages {
            found.append("\(staged.count) staged and \(viewModel.loadingImages) loading: more than four")
        }
        let shown = staged + sent
        if Set(shown).count != shown.count { found.append("a photo staged or sent twice: \(shown)") }
        for number in staged {
            guard let pick = picks.first(where: { $0.number == number }) else { continue }
            if pick.state != .arrived {
                found.append("pick \(number) is staged though it \(pick.state)")
            }
        }
        for batch in Set(picks.map(\.batch)) {
            let order = stagedLog.filter { number in picks.first { $0.number == number }?.batch == batch }
            if order != order.sorted() { found.append("batch \(batch) staged out of pick order: \(order)") }
        }
        let anyHeld = picks.contains { $0.state == .held && $0.id.map(viewModel.loadingPicks.contains) == true }
        if !anyHeld, viewModel.loadingImages > 0 {
            found.append("Send held by \(viewModel.loadingImages) loading picks though none is still loading")
        }
        for id in viewModel.loadingPicks where !picks.contains(where: { $0.id == id }) {
            found.append("a loading placeholder for no pick")
        }
        let words = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let expected = (words || !staged.isEmpty) && !viewModel.isResponding && viewModel.loadingImages == 0
        if viewModel.canSend != expected { found.append("canSend is \(viewModel.canSend), expected \(expected)") }
        return found
    }

    func finish() async -> [String] {
        // Every pick still loading arrives; then each one that loaded is on
        // the strip or in a message, once.
        while picks.contains(where: { $0.state == .held && $0.id != nil }) {
            await release(0, loaded: true)
        }
        var found = await violations()
        let cancelled = Set(batches.indices.filter { batches[$0].cancelled })
        let shown = numbers(viewModel.staged) + sent + removedStaged
        for pick in picks where pick.state == .arrived && !cancelled.contains(pick.batch) {
            let times = shown.filter { $0 == pick.number }.count
            if times != 1 { found.append("pick \(pick.number) loaded and shows \(times) times") }
        }
        if viewModel.loadingImages > 0 { found.append("Send still held at the end") }
        return found
    }

    func tearDown() async {
        for pick in picks { pick.gate.releaseAll(nil) }
        for batch in batches { _ = await finished(batch.task) }
        try? FileManager.default.removeItem(at: imageDirectory)
    }

    func trace() -> String {
        "  staged \(numbers(viewModel.staged)) loading \(viewModel.loadingImages) sent \(sent) "
            + "picks \(picks.map { "\($0.number):\($0.state)" })"
    }

    // MARK: Helpers

    /// Whether `task` ends within two seconds.
    private func finished(_ task: Task<Void, Never>) async -> Bool {
        let done = Flag()
        Task { @MainActor in
            await task.value
            done.value = true
        }
        return await eventually { done.value }
    }

    nonisolated static func data(_ number: Int) -> Data { Data([UInt8(number >> 8), UInt8(number & 0xFF)]) }

    private func numbers(_ photos: [StagedPhoto]) -> [Int] {
        photos.map { Int($0.data[0]) << 8 | Int($0.data[1]) }
    }
}

@MainActor
final class Flag {
    var value = false
}

/// Describes a pick's bytes as "p<number>".
private struct NumberDescribingStudio: ImageStudioService {
    func describe(image: Data) async throws -> String { "p\(Int(image[0]) << 8 | Int(image[1]))" }
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] { [] }
    func cutout(image: Data, target: String?) async throws -> Data { image }
    func stylize(image: Data, instruction: String) async throws -> Data { image }
    func outline(image: Data) async throws -> Data { image }
}

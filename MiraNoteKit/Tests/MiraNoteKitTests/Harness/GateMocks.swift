import Foundation
import MiraNoteKit

// Gate mocks: services whose every call waits until the test releases it,
// so a result can land before, during or after any user action -- no fixed
// sleeps. Public Kit API only: the app's unit tests compile this file too
// (project.yml). A call ignores cancellation, like a network call already
// on the wire; the code under test must drop a result it no longer wants.

/// The calls to one service method, each held until released. A call can
/// be released before it is made (the service has not got there yet): it
/// then returns at once.
final class GateQueue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    /// In call order; past `made`, releases waiting for calls to come.
    private var calls: [Call] = []
    private var made = 0
    /// What every call returns after `releaseAll` (tear-down).
    private var fallback: Value?

    private final class Call {
        var value: Value?
        var continuation: CheckedContinuation<Value, Never>?
    }

    init() {}

    /// Called by the service: waits for this call's release.
    func wait() async -> Value {
        let call = claim()
        return await withCheckedContinuation { park(call, $0) }
    }

    private func claim() -> Call {
        lock.lock()
        defer { lock.unlock() }
        if made == calls.count { calls.append(Call()) }
        let call = calls[made]
        made += 1
        if call.value == nil, let fallback { call.value = fallback }
        return call
    }

    private func park(_ call: Call, _ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if let value = call.value {
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            call.continuation = continuation
            lock.unlock()
        }
    }

    /// Calls made so far, released or not.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    /// Calls made and still held.
    var pending: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls.prefix(made).filter { $0.value == nil }.count
    }

    /// Releases call `index` (in call order, made or still to come) with
    /// `value`; false when it was already released.
    @discardableResult
    func release(_ index: Int, _ value: Value) -> Bool {
        lock.lock()
        while calls.count <= index { calls.append(Call()) }
        guard calls[index].value == nil else {
            lock.unlock()
            return false
        }
        calls[index].value = value
        let continuation = calls[index].continuation
        calls[index].continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
        return true
    }

    /// Releases the oldest call not released yet, made or to come.
    @discardableResult
    func releaseNext(_ value: Value) -> Bool {
        lock.lock()
        let index = calls.firstIndex { $0.value == nil } ?? calls.count
        lock.unlock()
        return release(index, value)
    }

    /// Releases every call made, and every call to come (tear-down).
    func releaseAll(_ value: Value) {
        lock.lock()
        fallback = value
        let held = calls.indices.filter { calls[$0].value == nil }
        lock.unlock()
        for index in held { release(index, value) }
    }
}

struct GateError: Error, Equatable {}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .microseconds(200))
    }
    return true
}

/// The image studio, every call held: `stylize`, `cutout`, `outline`,
/// `describe` and `generate` each have their own queue.
final class GatedStudio: ImageStudioService, @unchecked Sendable {
    let stylizeCalls = GateQueue<Result<Data, GateError>>()
    let cutoutCalls = GateQueue<Result<Data, GateError>>()
    let outlineCalls = GateQueue<Result<Data, GateError>>()
    let describeCalls = GateQueue<Result<String, GateError>>()
    let generateCalls = GateQueue<Result<[Data], GateError>>()

    init() {}

    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        try await generateCalls.wait().get()
    }
    func cutout(image: Data, target: String?) async throws -> Data { try await cutoutCalls.wait().get() }
    func stylize(image: Data, instruction: String) async throws -> Data { try await stylizeCalls.wait().get() }
    func outline(image: Data) async throws -> Data { try await outlineCalls.wait().get() }
    func describe(image: Data) async throws -> String { try await describeCalls.wait().get() }

    func releaseAll() {
        stylizeCalls.releaseAll(.failure(GateError()))
        cutoutCalls.releaseAll(.failure(GateError()))
        outlineCalls.releaseAll(.failure(GateError()))
        describeCalls.releaseAll(.failure(GateError()))
        generateCalls.releaseAll(.failure(GateError()))
    }
}

/// The transcriber, every take held.
final class GatedTranscription: VoiceTranscriptionService, @unchecked Sendable {
    let calls = GateQueue<Result<String, GateError>>()

    init() {}

    func transcribe(audio: Data, filename: String) async throws -> String { try await calls.wait().get() }
}

/// The chat backend, every turn held; records what was asked.
final class GatedChat: ChatService, @unchecked Sendable {
    let calls = GateQueue<Result<ChatReply, GateError>>()
    private let lock = NSLock()
    private var asked: [String] = []

    init() {}

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func reply(to message: String, sessionID: String?, notes: [ChatNote], page: PageContext?) async throws -> ChatReply {
        record(message)
        return try await calls.wait().get()
    }

    private func record(_ message: String) {
        lock.lock()
        asked.append(message)
        lock.unlock()
    }
}

/// The microphones of one test: each recorder's start is held (the mic
/// coming up, the permission alert), and `live` counts the recorders on,
/// so a test can assert that no microphone is left on.
@MainActor
final class MicLedger {
    let starts = GateQueue<Result<Void, GateError>>()
    fileprivate(set) var live = 0
    private(set) var made = 0

    init() {}

    func makeRecorder() -> AudioRecording {
        made += 1
        return GatedRecorder(ledger: self)
    }
}

@MainActor
final class GatedRecorder: AudioRecording {
    private let ledger: MicLedger
    private(set) var isRecording = false {
        didSet {
            if isRecording != oldValue { ledger.live += isRecording ? 1 : -1 }
        }
    }

    init(ledger: MicLedger) {
        self.ledger = ledger
    }

    var level: Float { isRecording ? 0.5 : 0 }

    func start() async throws {
        try await ledger.starts.wait().get()
        isRecording = true
    }

    func stop() async throws -> Data {
        isRecording = false
        return Data("take".utf8)
    }
}

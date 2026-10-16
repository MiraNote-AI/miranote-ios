import Foundation
import XCTest

// Stateful random-sequence testing: a seeded generator of user actions,
// many sequences per model, invariants checked after EVERY step. A failure
// prints the seed and a shortened failing sequence that replays on its own.
//
// Environment (all optional):
//   HARNESS_SEED=<n>        base seed (default: fixed, so CI is repeatable)
//   HARNESS_SEQUENCES=<n>   sequences per model (default 500)
//   HARNESS_LENGTH=<n>      actions per sequence (default 40)
//   HARNESS_LONG=1          local soak: 20,000 sequences x 80 actions, and a
//                           time-based seed unless HARNESS_SEED is set
//   HARNESS_TRACE=1         print the state after each step of the
//                           shortened failing sequence

/// SplitMix64: tiny, fast, and the same numbers on every machine.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }

    mutating func chance(_ probability: Double) -> Bool { Double.random(in: 0..<1, using: &self) < probability }

    /// One of `weighted`, each chosen in proportion to its weight.
    mutating func pick<T>(_ weighted: [(T, Int)]) -> T {
        let total = weighted.reduce(0) { $0 + max(0, $1.1) }
        var roll = int(0...max(0, total - 1))
        for (value, weight) in weighted where weight > 0 {
            if roll < weight { return value }
            roll -= weight
        }
        return weighted[0].0
    }
}

/// A stateful system under test plus its invariants. Actions must be
/// self-contained (elements by index modulo the count, never by id), so a
/// shortened sequence still replays.
@MainActor
protocol SequenceModel: AnyObject {
    /// Printed as Swift prints an enum case: `move(2, dx: 30, dy: -12)`.
    associatedtype Action

    /// The same initial state for the same seed.
    init(seed: UInt64) async
    /// The next action, chosen from the current state.
    func nextAction(_ rng: inout SeededRandom) -> Action
    func apply(_ action: Action) async
    /// What is wrong right after the last action; empty when nothing is.
    func violations() async -> [String]
    /// Checks only the end of a sequence can make (undo back to the start).
    func finish() async -> [String]
    /// Lets go of anything still running (gates, tasks).
    func tearDown() async
    /// The state in a few lines, for HARNESS_TRACE=1.
    func trace() -> String
}

extension SequenceModel {
    func finish() async -> [String] { [] }
    func tearDown() async {}
    func trace() -> String { "" }
}

@MainActor
enum SequenceHarness {
    struct Settings {
        var seed: UInt64
        var sequences: Int
        var length: Int

        static func fromEnvironment(sequences: Int = 500, length: Int = 40) -> Settings {
            let env = ProcessInfo.processInfo.environment
            let long = env["HARNESS_LONG"] == "1"
            let seed = env["HARNESS_SEED"].flatMap(UInt64.init)
                ?? (long ? UInt64(Date().timeIntervalSince1970 * 1000) : 0x5EED_2026_1016)
            return Settings(
                seed: seed,
                sequences: env["HARNESS_SEQUENCES"].flatMap(Int.init) ?? (long ? 20_000 : sequences),
                length: env["HARNESS_LENGTH"].flatMap(Int.init) ?? (long ? 80 : length)
            )
        }
    }

    struct Failure {
        let step: Int
        let messages: [String]
    }

    /// Runs the sequences; on the first failing one, shortens it and fails
    /// the test with the seed and the steps that still fail.
    static func run<Model: SequenceModel>(
        _ model: Model.Type,
        _ settings: Settings = .fromEnvironment(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let started = Date()
        var steps = 0
        for index in 0..<settings.sequences {
            let seed = settings.seed &+ UInt64(index) &* 0x9E37_79B9
            var rng = SeededRandom(seed: seed)
            let system = await Model(seed: seed)
            var actions: [Model.Action] = []
            var failure: Failure?
            for step in 0..<settings.length {
                let action = system.nextAction(&rng)
                actions.append(action)
                await system.apply(action)
                steps += 1
                let problems = await system.violations()
                if !problems.isEmpty {
                    failure = Failure(step: step, messages: problems)
                    break
                }
            }
            if failure == nil {
                let problems = await system.finish()
                if !problems.isEmpty { failure = Failure(step: actions.count, messages: problems) }
            }
            await system.tearDown()
            guard let failure else { continue }
            let short = await shorten(Model.self, seed: seed, actions: actions)
            let tracing = ProcessInfo.processInfo.environment["HARNESS_TRACE"] == "1"
            let shortFailure = await replay(Model.self, seed: seed, actions: short, tracing: tracing)
            XCTFail(report(Model.self, seed: seed, index: index, failure: failure, actions: actions,
                           short: short, shortFailure: shortFailure),
                    file: file, line: line)
            return
        }
        let seconds = Date().timeIntervalSince(started)
        print("[harness] \(Model.self): \(settings.sequences) sequences, \(steps) steps, "
              + "base seed \(settings.seed), \(String(format: "%.1f", seconds)) s, ok")
    }

    /// Replays `actions` on a fresh model: the first failure, or nil.
    static func replay<Model: SequenceModel>(
        _ model: Model.Type, seed: UInt64, actions: [Model.Action], tracing: Bool = false
    ) async -> Failure? {
        let system = await Model(seed: seed)
        var failure: Failure?
        if tracing { print("[trace] start\n\(system.trace())") }
        for (step, action) in actions.enumerated() {
            await system.apply(action)
            if tracing { print("[trace] \(step): \(action)\n\(system.trace())") }
            let problems = await system.violations()
            if !problems.isEmpty {
                failure = Failure(step: step, messages: problems)
                break
            }
        }
        if failure == nil {
            let problems = await system.finish()
            if !problems.isEmpty { failure = Failure(step: actions.count, messages: problems) }
        }
        await system.tearDown()
        return failure
    }

    /// Drops chunks, then single actions, while the sequence still fails the
    /// same invariant: a minimal-ish sequence to turn into a named test.
    private static func shorten<Model: SequenceModel>(
        _ model: Model.Type, seed: UInt64, actions: [Model.Action]
    ) async -> [Model.Action] {
        var current = actions
        guard let failure = await replay(Model.self, seed: seed, actions: current) else { return current }
        current = Array(current.prefix(failure.step + 1))
        let kind = signature(failure)
        func stillFails(_ candidate: [Model.Action]) async -> Bool {
            guard let again = await replay(Model.self, seed: seed, actions: candidate) else { return false }
            return signature(again) == kind
        }
        var chunk = max(1, current.count / 2)
        while chunk >= 1 {
            var start = 0
            while start < current.count {
                var candidate = current
                candidate.removeSubrange(start..<min(current.count, start + chunk))
                if !candidate.isEmpty, await stillFails(candidate) {
                    current = candidate
                } else {
                    start += chunk
                }
            }
            chunk /= 2
        }
        return current
    }

    /// Which invariant failed: the first message up to its first number,
    /// quote or bracket.
    private static func signature(_ failure: Failure) -> String {
        let first = failure.messages.first ?? ""
        return String(first.prefix { !$0.isNumber && $0 != "\"" && $0 != "(" }.prefix(32))
    }

    private static func report<Model: SequenceModel>(
        _ model: Model.Type, seed: UInt64, index: Int, failure: Failure,
        actions: [Model.Action], short: [Model.Action], shortFailure: Failure?
    ) -> String {
        var lines = ["\(Model.self) failed: sequence \(index), seed \(seed), step \(failure.step)"]
        lines += failure.messages.map { "  invariant: " + $0 }
        lines.append("  shortened to \(short.count) of \(actions.count) steps (replays from the same seed):")
        lines += short.enumerated().map { "    \($0.offset): \($0.element)" }
        if let shortFailure {
            let at = shortFailure.step < short.count ? "step \(shortFailure.step)" : "the end-of-sequence check"
            lines.append("  which fails at \(at):")
            lines += shortFailure.messages.map { "    invariant: " + $0 }
        }
        lines.append("  replay all: HARNESS_SEED=\(seed) HARNESS_SEQUENCES=1 HARNESS_LENGTH=\(actions.count)")
        return lines.joined(separator: "\n")
    }
}

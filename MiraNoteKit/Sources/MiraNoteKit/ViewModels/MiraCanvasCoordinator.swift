import CoreGraphics
import Foundation
import Observation

/// What the Mira strip under the canvas is showing right now.
public enum MiraTurnPhase: Equatable {
    case idle
    /// Shown only after `workingDelay` (400 ms): verb-specific copy + Stop.
    case working(verb: String)
    /// A canvas edit landed: the Keep-pattern receipt (auto-keeps).
    case receipt(MiraReceipt)
    /// The turn failed; canvas untouched, prompt refilled.
    case failure(MiraFailure)
    /// A conversational answer (no canvas change) with follow-up chips.
    case reply(String, chips: [String])
}

/// The v2.1 receipt: say what changed AND what was kept.
public struct MiraReceipt: Equatable, Sendable {
    public let changed: String
    public let kept: String

    public init(changed: String, kept: String) {
        self.changed = changed
        self.kept = kept
    }
}

/// The v2.1 failure taxonomy: clarify (did not understand), retry (it did
/// not work), redirect (cannot do that here). Never red, never partial.
public struct MiraFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case clarify, retry, redirect
    }

    public let kind: Kind
    public let message: String
    public let chips: [String]

    public init(kind: Kind, message: String, chips: [String]) {
        self.kind = kind
        self.message = message
        self.chips = chips
    }
}

/// Runs one Mira turn against the canvas: classify -> (maybe) call a
/// backend -> apply atomically -> receipt; or fail with the taxonomy above.
/// V1 classification is a local rule set (the structured page-edit backend
/// is the recorded D3 gap); text transforms hit the :8001 POC and
/// conversation hits the :8003 POC for real.
@MainActor
@Observable
public final class MiraCanvasCoordinator {
    public private(set) var phase: MiraTurnPhase = .idle
    /// Elements currently being changed -- the board breathes and locks these.
    public private(set) var workingItemIDs: Set<CanvasItem.ID> = []
    /// Set when a turn stops or fails so the input bar can restore the words.
    public var refillPrompt: String?

    private let text: TextTransformService
    private let chat: ChatService
    /// How long a receipt (and its Revert) stays before keeping by
    /// itself. One line plus an inline Revert reads in a few seconds,
    /// and the header undo still covers regrets after auto-keep -- so
    /// short wins (Meng tuned this twice: 20s and 10s both felt long).
    public static let defaultReceiptDismiss: Duration = .seconds(6)

    private let workingDelay: Duration
    private let timeout: Duration
    private let receiptDismiss: Duration

    private var turnTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var sessionID: String?
    private var lastPrompt = ""
    /// Generation token: every ask/cancel bumps it, and every phase write
    /// from a turn is guarded on it, so a replaced turn can never clobber
    /// its successor's state (Stop, isWorking, receipts all stay coherent).
    private var turnGeneration = 0
    /// The editor's changeCount when the current receipt was shown; Revert
    /// only undoes if nothing else mutated the canvas since.
    private var receiptChangeCount: Int?

    public init(
        text: TextTransformService,
        chat: ChatService,
        workingDelay: Duration = .milliseconds(400),
        timeout: Duration = .seconds(30),
        receiptDismiss: Duration = MiraCanvasCoordinator.defaultReceiptDismiss
    ) {
        self.text = text
        self.chat = chat
        self.workingDelay = workingDelay
        self.timeout = timeout
        self.receiptDismiss = receiptDismiss
    }

    public var isWorking: Bool {
        if case .working = phase { return true }
        return turnTask != nil
    }

    /// Context-aware idle suggestions -- PAGE-level only (Meng,
    /// 2026-07-09): polishing belongs to the text editor's keyboard row,
    /// where the target block is unambiguous. Every chip must be ABOUT
    /// something already on the page, and a title is a suggestion about
    /// words, so it waits for words.
    public func suggestions(for editor: CanvasViewModel) -> [String] {
        var chips: [String] = []
        let hasText = editor.items.contains {
            if case .text = $0.content { return true } else { return false }
        }
        if editor.items.count > 1 {
            chips.append("Tidy the layout")
        }
        let hasTitle = editor.items.contains {
            if case .text(let block) = $0.content { return block.pointSize >= 24 }
            return false
        }
        if hasText, !hasTitle {
            chips.append("Add a soft title")
        }
        return chips
    }

    // MARK: Turn lifecycle

    public func ask(_ prompt: String, editor: CanvasViewModel) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelTurn()
        phase = .idle
        lastPrompt = trimmed
        refillPrompt = nil
        let intent = MiraIntent.classify(trimmed, editor: editor)
        let generation = turnGeneration
        turnTask = Task { await run(intent, prompt: trimmed, editor: editor, generation: generation) }
    }

    /// The Stop control: cancel with no residue, give the words back.
    public func stop() {
        guard turnTask != nil else { return }
        cancelTurn()
        phase = .idle
        refillPrompt = lastPrompt
    }

    /// Failure chip: run the same words again.
    public func retry(editor: CanvasViewModel) {
        guard !lastPrompt.isEmpty else { return }
        ask(lastPrompt, editor: editor)
    }

    /// One-tap revert of the last applied change (the receipt's escape
    /// hatch). If anything else touched the canvas since the receipt was
    /// shown, revert declines to undo (it would eat the user's edit, not
    /// Mira's) and just dismisses.
    public func revert(editor: CanvasViewModel) {
        if let expected = receiptChangeCount, editor.changeCount == expected {
            editor.undo()
        }
        receiptChangeCount = nil
        dismissTask?.cancel()
        phase = .idle
    }

    /// The view calls this when the canvas mutates. A showing receipt
    /// keeps itself (its Revert would no longer be honest), and a lingering
    /// reply steps aside -- the user has gone back to making things.
    public func canvasDidChange(_ editor: CanvasViewModel) {
        switch phase {
        case .receipt:
            guard let expected = receiptChangeCount, editor.changeCount != expected else { return }
            dismiss()
        case .reply:
            dismiss()
        default:
            break
        }
    }

    /// Auto-keep is the default: dismissing keeps the change.
    public func dismiss() {
        receiptChangeCount = nil
        dismissTask?.cancel()
        phase = .idle
    }

    private func cancelTurn() {
        turnGeneration += 1
        turnTask?.cancel()
        turnTask = nil
        dismissTask?.cancel()
        workingItemIDs = []
    }

    private func run(
        _ intent: MiraIntent,
        prompt: String,
        editor: CanvasViewModel,
        generation: Int
    ) async {
        // The working state earns its place only past the delay threshold.
        let indicator = Task { [workingDelay] in
            try? await Task.sleep(for: workingDelay)
            guard !Task.isCancelled, self.turnGeneration == generation else { return }
            phase = .working(verb: intent.verb)
            workingItemIDs = intent.affectedItems
        }
        defer {
            indicator.cancel()
            if turnGeneration == generation {
                workingItemIDs = []
                turnTask = nil
            }
        }

        do {
            let outcome = try await withTimeout(timeout) { [text, chat, sessionID] in
                try await intent.perform(text: text, chat: chat, sessionID: sessionID)
            }
            indicator.cancel()
            guard !Task.isCancelled, turnGeneration == generation else { return }
            settle(outcome, editor: editor)
        } catch is CancellationError {
            // stop() already reset the phase.
        } catch {
            indicator.cancel()
            guard !Task.isCancelled, turnGeneration == generation else { return }
            refillPrompt = prompt
            phase = .failure(Self.failure(for: error))
        }
    }

    /// Apply the outcome atomically: the canvas mutates only here, only on
    /// success, with one undo snapshot behind the receipt's Revert.
    private func settle(_ outcome: MiraOutcome, editor: CanvasViewModel) {
        switch outcome {
        case .textChanged(let itemID, let newText, let receipt):
            guard editor.item(itemID) != nil else {
                refillPrompt = lastPrompt
                phase = .failure(MiraFailure(
                    kind: .retry,
                    message: "The text I was working on is gone, so I left everything as is.",
                    chips: ["Try again"]
                ))
                return
            }
            editor.beginChange()
            editor.setText(itemID: itemID, to: newText)
            showReceipt(receipt, editor: editor)
        case .titleAdded(let title, let receipt):
            // Land above the current topmost element, never on top of it.
            let currentTop = editor.items
                .map { $0.position.y - $0.size.height / 2 }
                .min() ?? 100
            let titleY = max(36, currentTop - 44)
            editor.addText(
                title,
                at: CGPoint(x: 150, y: titleY),
                pointSize: 30,
                size: CGSize(width: 270, height: 60)
            )
            showReceipt(receipt, editor: editor)
        case .organized(let receipt):
            editor.quickOrganize(canvasWidth: editor.canvasWidth ?? 360)
            showReceipt(receipt, editor: editor)
        case .reply(let message, let newSessionID):
            sessionID = newSessionID ?? sessionID
            phase = .reply(message, chips: suggestions(for: editor))
        }
    }

    private func showReceipt(_ receipt: MiraReceipt, editor: CanvasViewModel) {
        receiptChangeCount = editor.changeCount
        phase = .receipt(receipt)
        dismissTask?.cancel()
        dismissTask = Task { [receiptDismiss] in
            try? await Task.sleep(for: receiptDismiss)
            guard !Task.isCancelled else { return }
            if case .receipt = phase { phase = .idle }
        }
    }

    private static func failure(for error: Error) -> MiraFailure {
        if error is MiraTimeoutError {
            return MiraFailure(
                kind: .retry,
                message: "This was taking too long, so I stopped. Try again?",
                chips: ["Try again", "Rephrase"]
            )
        }
        if let clarify = error as? MiraClarifyError {
            return MiraFailure(kind: .clarify, message: clarify.question, chips: clarify.chips)
        }
        return MiraFailure(
            kind: .retry,
            message: "That one did not go through. Try again, or say it differently?",
            chips: ["Try again", "Rephrase"]
        )
    }

    private func withTimeout<T: Sendable>(
        _ limit: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw MiraTimeoutError()
            }
            guard let first = try await group.next() else { throw MiraTimeoutError() }
            group.cancelAll()
            return first
        }
    }
}

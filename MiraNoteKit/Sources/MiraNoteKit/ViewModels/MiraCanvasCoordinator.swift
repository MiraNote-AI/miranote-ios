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
public struct MiraReceipt: Equatable {
    public let changed: String
    public let kept: String

    public init(changed: String, kept: String) {
        self.changed = changed
        self.kept = kept
    }
}

/// The v2.1 failure taxonomy: clarify (did not understand), retry (it did
/// not work), redirect (cannot do that here). Never red, never partial.
public struct MiraFailure: Equatable {
    public enum Kind: Equatable {
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
    private let workingDelay: Duration
    private let timeout: Duration
    private let receiptDismiss: Duration

    private var turnTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var sessionID: String?
    private var lastPrompt = ""

    public init(
        text: TextTransformService,
        chat: ChatService,
        workingDelay: Duration = .milliseconds(400),
        timeout: Duration = .seconds(30),
        receiptDismiss: Duration = .seconds(5)
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

    /// Context-aware idle suggestions (only offer what the page can take).
    public func suggestions(for editor: CanvasViewModel) -> [String] {
        var chips: [String] = []
        if editor.items.contains(where: { if case .text = $0.content { return true } else { return false } }) {
            chips.append("Polish the text")
        }
        if editor.items.count > 1 {
            chips.append("Tidy the layout")
        }
        chips.append("Add a soft title")
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
        turnTask = Task { await run(intent, prompt: trimmed, editor: editor) }
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

    /// One-tap revert of the last applied change (the receipt's escape hatch).
    public func revert(editor: CanvasViewModel) {
        editor.undo()
        dismissTask?.cancel()
        phase = .idle
    }

    /// Auto-keep is the default: dismissing keeps the change.
    public func dismiss() {
        dismissTask?.cancel()
        phase = .idle
    }

    private func cancelTurn() {
        turnTask?.cancel()
        turnTask = nil
        dismissTask?.cancel()
        workingItemIDs = []
    }

    private func run(_ intent: MiraIntent, prompt: String, editor: CanvasViewModel) async {
        // The working state earns its place only past the delay threshold.
        let indicator = Task { [workingDelay] in
            try? await Task.sleep(for: workingDelay)
            guard !Task.isCancelled else { return }
            phase = .working(verb: intent.verb)
            workingItemIDs = intent.affectedItems
        }
        defer {
            indicator.cancel()
            workingItemIDs = []
            turnTask = nil
        }

        do {
            let outcome = try await withTimeout(timeout) { [text, chat, sessionID] in
                try await intent.perform(text: text, chat: chat, sessionID: sessionID)
            }
            indicator.cancel()
            guard !Task.isCancelled else { return }
            settle(outcome, editor: editor)
        } catch is CancellationError {
            // stop() already reset the phase.
        } catch {
            indicator.cancel()
            guard !Task.isCancelled else { return }
            refillPrompt = prompt
            phase = .failure(Self.failure(for: error))
        }
    }

    /// Apply the outcome atomically: the canvas mutates only here, only on
    /// success, with one undo snapshot behind the receipt's Revert.
    private func settle(_ outcome: MiraOutcome, editor: CanvasViewModel) {
        switch outcome {
        case .textChanged(let itemID, let newText, let receipt):
            editor.beginChange()
            editor.setText(itemID: itemID, to: newText)
            showReceipt(receipt)
        case .titleAdded(let title, let receipt):
            editor.addText(
                title,
                at: CGPoint(x: 150, y: 40),
                pointSize: 30,
                size: CGSize(width: 270, height: 60)
            )
            showReceipt(receipt)
        case .organized(let receipt):
            editor.quickOrganize(canvasWidth: editor.canvasWidth ?? 360)
            showReceipt(receipt)
        case .reply(let message, let newSessionID):
            sessionID = newSessionID ?? sessionID
            phase = .reply(message, chips: suggestions(for: editor))
        }
    }

    private func showReceipt(_ receipt: MiraReceipt) {
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

struct MiraTimeoutError: Error {}

/// A clarify-type failure raised during classification (e.g. "polish the
/// text" on a page with no text).
struct MiraClarifyError: Error {
    let question: String
    let chips: [String]
}

/// What a successful turn produced. Mutations are described, not applied --
/// the coordinator applies them on the main actor after the await returns.
enum MiraOutcome: Sendable {
    case textChanged(CanvasItem.ID, String, MiraReceipt)
    case titleAdded(String, MiraReceipt)
    case organized(MiraReceipt)
    case reply(String, sessionID: String?)
}

/// V1 local intent rules. The structured page-draft backend (plan D3 gap)
/// will replace classification; the surrounding turn machinery stays.
enum MiraIntent {
    case transformText(CanvasItem.ID, original: String, TextTransformMode)
    case addTitle
    case organize
    case converse(String)

    @MainActor
    static func classify(_ prompt: String, editor: CanvasViewModel) -> MiraIntent {
        let lowered = prompt.lowercased()

        func targetText() -> (CanvasItem.ID, String)? {
            let candidates = editor.orderedItems.compactMap { item -> (CanvasItem.ID, String)? in
                guard case .text(let block) = item.content,
                      !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return (item.id, block.text)
            }
            if let selected = editor.selectedItemID,
               let match = candidates.first(where: { $0.0 == selected }) {
                return match
            }
            // No selection: the longest text is almost always the prose body
            // (titles and date captions are short).
            return candidates.max { $0.1.count < $1.1.count }
        }

        if lowered.contains("polish") || lowered.contains("warmer") || lowered.contains("softer") {
            if let (id, original) = targetText() {
                return .transformText(id, original: original, .polish)
            }
            return .converse(prompt)
        }
        if lowered.contains("expand") || lowered.contains("longer") {
            if let (id, original) = targetText() {
                return .transformText(id, original: original, .expand)
            }
            return .converse(prompt)
        }
        if lowered.contains("shorten") || lowered.contains("clean") || lowered.contains("tighten") {
            if let (id, original) = targetText() {
                return .transformText(id, original: original, .clean)
            }
            return .converse(prompt)
        }
        if lowered.contains("title") {
            return .addTitle
        }
        if lowered.contains("tidy") || lowered.contains("layout")
            || lowered.contains("organize") || lowered.contains("arrange") {
            return .organize
        }
        return .converse(prompt)
    }

    var verb: String {
        switch self {
        case .transformText(_, _, .polish): return "Polishing the text..."
        case .transformText(_, _, .expand): return "Expanding the text..."
        case .transformText(_, _, .clean): return "Tightening the text..."
        case .addTitle: return "Adding a title..."
        case .organize: return "Tidying the layout..."
        case .converse: return "Thinking..."
        }
    }

    var affectedItems: Set<CanvasItem.ID> {
        if case .transformText(let id, _, _) = self { return [id] }
        return []
    }

    func perform(
        text: TextTransformService,
        chat: ChatService,
        sessionID: String?
    ) async throws -> MiraOutcome {
        switch self {
        case .transformText(let id, let original, let mode):
            let transformed = try await text.transform(original, mode: mode)
            let what: String
            switch mode {
            case .polish: what = "Polished the text."
            case .expand: what = "Expanded the text."
            case .clean: what = "Tightened the text."
            }
            return .textChanged(id, transformed, MiraReceipt(
                changed: what,
                kept: "Layout, photos, and everything else stayed put."
            ))
        case .addTitle:
            return .titleAdded("A quiet moment", MiraReceipt(
                changed: "Added a soft title.",
                kept: "Your words and photos are unchanged."
            ))
        case .organize:
            return .organized(MiraReceipt(
                changed: "Tidied the layout.",
                kept: "Your words and photos are unchanged."
            ))
        case .converse(let prompt):
            let reply = try await chat.reply(to: prompt, sessionID: sessionID)
            return .reply(reply.text, sessionID: reply.sessionID)
        }
    }
}

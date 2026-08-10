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
    /// Two generated candidates awaiting the user's pick (or the xmark).
    case imageChoices([Data], prompt: String, placement: ImageChoicePlacement)
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
    // Setter is internal (not private) so the +Images extension file can
    // drive the choice flow; outside the module it stays read-only.
    public internal(set) var phase: MiraTurnPhase = .idle
    /// The canvas conversation so far (capped) -- the reply card shows a
    /// short transcript so turns read as one thread, not islands.
    public private(set) var conversation: [ChatMessage] = []
    /// The chip that lands the current reply on the page.
    public nonisolated static let placeReplyChip = "Put this on the page"
    /// Elements currently being changed -- the board breathes and locks these.
    public private(set) var workingItemIDs: Set<CanvasItem.ID> = []
    /// Set when a turn stops or fails so the input bar can restore the words.
    public var refillPrompt: String?
    /// Runs before a turn classifies -- the view wires page preparation
    /// here (e.g. wait for vision to finish looking at new photos) so the
    /// turn sees a fully-described page.
    public var prepareTurn: (() async -> Void)?
    /// Renders the page as the user sees it, for Mira's look_at_page.
    /// Wired by the view because the renderer lives in the App layer.
    /// Nil in tests and previews -- Mira then answers from the map
    /// alone, which is not a failure.
    public var renderPage: (() -> Data?)?

    private let text: TextTransformService
    private let chat: ChatService
    let imageStudio: ImageStudioService
    /// Generation and photo edits legitimately run past the chat timeout.
    let imageTimeout: Duration
    let imageStore: ImageFileStore
    let stickerFavorites: StickerFavoritesStore
    /// How long a receipt (and its Revert) stays before keeping by
    /// itself. One line plus an inline Revert reads in a few seconds,
    /// and the header undo still covers regrets after auto-keep -- so
    /// short wins (Meng tuned this twice: 20s and 10s both felt long).
    public nonisolated static let defaultReceiptDismiss: Duration = .seconds(6)

    /// The middle rung of the timeout ladder. Inside it, a look_at_page
    /// hop gets 25s and failing costs only the look. Outside it,
    /// `LiveChatService.requestTimeout` sits higher on purpose, so
    /// exactly one clock can fire and the same stall always reads the
    /// same way to the user.
    public nonisolated static let defaultTurnTimeout: Duration = .seconds(60)

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
        timeout: Duration = MiraCanvasCoordinator.defaultTurnTimeout,
        receiptDismiss: Duration = MiraCanvasCoordinator.defaultReceiptDismiss,
        imageStudio: ImageStudioService = MockImageStudioService(),
        imageTimeout: Duration = .seconds(150),
        imageStore: ImageFileStore = ImageFileStore(),
        stickerFavorites: StickerFavoritesStore = StickerFavoritesStore()
    ) {
        self.text = text
        self.chat = chat
        self.workingDelay = workingDelay
        self.timeout = timeout
        self.receiptDismiss = receiptDismiss
        self.imageStudio = imageStudio
        self.imageTimeout = imageTimeout
        self.imageStore = imageStore
        self.stickerFavorites = stickerFavorites
        // classify reads photo bytes through the same store this
        // coordinator lands images with.
        MiraIntent.classifyImageStore = imageStore
    }

    public var isWorking: Bool {
        if case .working = phase { return true }
        return turnTask != nil
    }

    // MARK: Turn lifecycle

    public func ask(_ prompt: String, editor: CanvasViewModel) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelTurn()
        phase = .idle
        lastPrompt = trimmed
        refillPrompt = nil
        let generation = turnGeneration
        turnTask = Task {
            if let prepareTurn {
                // Cover the preparation with the working bar past the
                // usual threshold, so waiting on vision reads as work.
                let indicator = Task { [workingDelay] in
                    try? await Task.sleep(for: workingDelay)
                    guard !Task.isCancelled, self.turnGeneration == generation else { return }
                    if case .idle = self.phase {
                        self.phase = .working(verb: "Looking at the page...")
                    }
                }
                await prepareTurn()
                indicator.cancel()
                guard self.turnGeneration == generation else { return }
            }
            let intent = MiraIntent.classify(trimmed, editor: editor, render: self.renderPage)
            await run(intent, prompt: trimmed, editor: editor, generation: generation)
        }
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

    /// The reply's suggested words land on the page as a text block (under
    /// the content), with the standard receipt. Only the quoted/emphasized
    /// suggestion lands -- never the conversational wrapping.
    public func placeReply(editor: CanvasViewModel) {
        guard case .reply(let message, _) = phase,
              let payload = MiraIntent.placeablePayload(message) else { return }
        editor.addText(
            payload,
            at: CGPoint(x: MiraNoteConfig.pageWidth / 2, y: editor.contentBottom + 60),
            pointSize: 15,
            size: CGSize(width: 320, height: 60)
        )
        showReceipt(MiraReceipt(
            changed: "Added a few words.",
            kept: "Everything else stayed put."
        ), editor: editor)
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
            let limit = intent.isSlowImageWork ? imageTimeout : timeout
            let outcome = try await withTimeout(limit) { [text, chat, sessionID, imageStudio] in
                try await intent.perform(
                    text: text, chat: chat, sessionID: sessionID, imageStudio: imageStudio
                )
            }
            indicator.cancel()
            guard !Task.isCancelled, turnGeneration == generation else { return }
            settle(outcome, editor: editor)
        } catch is CancellationError {
            // stop() already reset the phase.
        } catch {
            indicator.cancel()
            guard !Task.isCancelled, turnGeneration == generation else { return }
            // Layout is the one ask with a good local answer, so an
            // unreachable backend gets a deterministic rearrange rather
            // than a failure card. Everything else honestly fails.
            if case .canvasTurn(let words, _, _) = intent,
               MiraIntent.isLayoutAsk(words), editor.items.count >= 2 {
                editor.beginChange()
                editor.quickOrganize(canvasWidth: MiraNoteConfig.pageWidth)
                showReceipt(MiraReceipt(
                    changed: "Tidied the layout.",
                    kept: "Your words and photos are unchanged."
                ), editor: editor)
                return
            }
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
            landTitle(title, receipt: receipt, editor: editor)
        case .textAdded(let words, let receipt):
            // A caption reads under the page's content, not on top of it.
            editor.addText(
                words,
                at: CGPoint(x: MiraNoteConfig.pageWidth / 2, y: editor.contentBottom + 60),
                pointSize: 15,
                size: CGSize(width: 320, height: 60)
            )
            showReceipt(receipt, editor: editor)
        case .pageEdited(let changes, let handles):
            settlePageEdits(changes, handles: handles, editor: editor)
        case .backgroundRequested(let request, _):
            startBackgroundTurn(request, editor: editor)
        case .reply(let message, let newSessionID):
            sessionID = newSessionID ?? sessionID
            conversation.append(ChatMessage(role: .user, text: lastPrompt))
            conversation.append(ChatMessage(role: .assistant, text: message))
            if conversation.count > 24 {
                conversation.removeFirst(conversation.count - 24)
            }
            // The place chip appears only when the reply carries words meant
            // for the page (a quoted/emphasized suggestion) -- plain banter
            // has nothing to place.
            let placeChips = MiraIntent.placeablePayload(message) != nil ? [Self.placeReplyChip] : []
            phase = .reply(message, chips: placeChips + suggestions(for: editor))
        case .imageChoices, .imageReplaced, .stickerReplaced, .stickerEdited,
             .filterApplied, .frameApplied, .textResized, .textRecolored,
             .backgroundCleared:
            settleImageOutcome(outcome, editor: editor)
        }
    }

    /// Guards run HERE, on the main actor, against the page as it stands
    /// now -- `perform` ran off it and the page may have moved underneath.
    private func settlePageEdits(
        _ changes: [ElementChange],
        handles: [String: CanvasItem.ID],
        editor: CanvasViewModel
    ) {
        let resolved = PageEditGuard.resolve(
            changes, handles: handles, canvasWidth: MiraNoteConfig.pageWidth
        )
        guard editor.applyPageEdits(resolved) else {
            // A receipt for a change that never landed would be a lie.
            refillPrompt = lastPrompt
            phase = .failure(MiraFailure(
                kind: .clarify,
                message: "I could not tell which piece you meant -- which one should I move?",
                chips: ["Try again"]
            ))
            return
        }
        showReceipt(Self.receipt(for: resolved, editor: editor), editor: editor)
    }

    /// Slow image work Mira asked for. It is a NEW turn, not the tail of
    /// the chat turn: that one has already settled, so without its own
    /// generation Stop would have nothing to cancel and a late receipt
    /// could land on top of whatever the user did next.
    private func startBackgroundTurn(_ request: BackgroundRequest, editor: CanvasViewModel) {
        switch request {
        case .clear:
            // The same call the existing .backgroundCleared branch makes.
            editor.beginChange()
            editor.setBackground(fileName: "")
            showReceipt(MiraReceipt(
                changed: "Cleared the backdrop.",
                kept: "Your words and photos are unchanged."
            ), editor: editor)
        case .set(let prompt):
            cancelTurn()
            let generation = turnGeneration
            phase = .working(verb: "Painting the backdrop...")
            turnTask = Task { [lastPrompt] in
                await run(
                    .setBackground(prompt: prompt), prompt: lastPrompt,
                    editor: editor, generation: generation
                )
            }
        }
    }

    func showReceipt(_ receipt: MiraReceipt, editor: CanvasViewModel) {
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

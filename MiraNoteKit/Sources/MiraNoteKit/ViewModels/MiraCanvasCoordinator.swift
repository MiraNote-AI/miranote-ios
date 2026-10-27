import CoreGraphics
import Foundation
import Observation

/// What the Mira strip under the canvas is showing right now.
public enum MiraTurnPhase: Equatable {
    case idle
    /// Shown only after `workingDelay` (400 ms): verb-specific copy + Stop.
    case working(verb: String)
    /// A canvas edit landed: the result sheet, waiting for Keep or Revert
    /// (or for the user to move on with an edit or a new ask).
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

    /// The middle rung of the timeout ladder. Inside it, a look_at_page
    /// hop gets 25s and failing costs only the look. Outside it,
    /// `LiveChatService.requestTimeout` sits higher on purpose, so
    /// exactly one clock can fire and the same stall always reads the
    /// same way to the user.
    public nonisolated static let defaultTurnTimeout: Duration = .seconds(60)

    private let workingDelay: Duration
    private let timeout: Duration

    private var turnTask: Task<Void, Never>?
    /// The running turn is the Background tool's Apply: its painting lands
    /// at once instead of waiting as two candidates.
    var appliesFirstBackground = false
    private var sessionID: String?
    private var lastPrompt = ""
    /// The last ask's words are the app's own (a chip), not typed.
    private var lastPromptIsAppCopy = false
    /// The intent the last ask was given rather than read from its words.
    private var lastIntent: MiraIntent?
    /// The last ask was the Background tool's Apply (Retry applies too).
    private var lastAppliesFirstBackground = false
    /// Generation token: every ask/cancel bumps it, and every phase write
    /// from a turn is guarded on it, so a replaced turn can never clobber
    /// its successor's state (Stop, isWorking, receipts all stay coherent).
    private var turnGeneration = 0
    /// The editor's changeCount when the current receipt was shown; Revert
    /// only undoes if nothing else mutated the canvas since.
    private var receiptChangeCount: Int?
    /// The page's words as the receipt found them, and its editor: typing
    /// records no undo step (and so no count), and a change made where the
    /// canvas view is not mounted never reaches `canvasDidChange`, so Revert
    /// compares both the count and the words.
    private var receiptWords: [CanvasItem.ID: String]?
    private weak var receiptEditor: CanvasViewModel?

    public init(
        text: TextTransformService,
        chat: ChatService,
        workingDelay: Duration = .milliseconds(400),
        timeout: Duration = MiraCanvasCoordinator.defaultTurnTimeout,
        imageStudio: ImageStudioService = MockImageStudioService(),
        imageTimeout: Duration = .seconds(120),
        imageStore: ImageFileStore = ImageFileStore(),
        stickerFavorites: StickerFavoritesStore = StickerFavoritesStore()
    ) {
        self.text = text
        self.chat = chat
        self.workingDelay = workingDelay
        self.timeout = timeout
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

    /// The text accessory's in-place rewrite (handoff screen 15): words in,
    /// words out, no Mira turn -- the block previews the result while the
    /// keyboard stays up, and the editor commits it.
    public func rewriteText(_ text: String, mode: TextTransformMode) async throws -> String {
        try await self.text.transform(text, mode: mode)
    }

    // MARK: Turn lifecycle

    public func ask(_ prompt: String, editor: CanvasViewModel) {
        ask(prompt, editor: editor, as: nil)
    }

    /// Runs a turn. `intent` skips reading the words: a chip that already
    /// knows what it means (and quotes the user's own text, which may hold
    /// router keywords) passes it, and Retry reuses it. `appCopy`: the words
    /// are a chip's, shown in the app's language in the conversation.
    func ask(
        _ prompt: String, editor: CanvasViewModel, as intent: MiraIntent?,
        appliesFirstBackground applies: Bool = false, appCopy: Bool = false
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelTurn()
        phase = .idle
        lastPrompt = trimmed
        lastPromptIsAppCopy = appCopy
        lastIntent = intent
        lastAppliesFirstBackground = applies
        appliesFirstBackground = applies
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
                        self.phase = .working(verb: String(appCopy: "Looking at the page..."))
                    }
                }
                await prepareTurn()
                indicator.cancel()
                guard self.turnGeneration == generation else { return }
            }
            let resolved = intent ?? MiraIntent.classify(trimmed, editor: editor, render: self.renderPage)
            await run(resolved, prompt: trimmed, editor: editor, generation: generation)
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
        ask(lastPrompt, editor: editor, as: lastIntent, appliesFirstBackground: lastAppliesFirstBackground,
            appCopy: lastPromptIsAppCopy)
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
            changed: String(appCopy: "Added a few words."),
            kept: String(appCopy: "Everything else stayed put.")
        ), editor: editor)
    }

    /// Whether the showing receipt's Revert would undo anything; a receipt
    /// for a turn that changed nothing offers no Revert.
    public var receiptCanRevert: Bool {
        guard case .receipt = phase, let editor = receiptEditor else { return false }
        return receiptStillLatest(on: editor)
    }

    /// Mira's change is still the page's last one: no step recorded since,
    /// and nothing typed.
    private func receiptStillLatest(on editor: CanvasViewModel) -> Bool {
        guard let expected = receiptChangeCount, let words = receiptWords else { return false }
        return editor.changeCount == expected && Self.words(on: editor) == words
    }

    /// Every text block's words. Typing is the one user edit that records
    /// no step; re-measured heights and photo descriptions are not edits.
    private static func words(on editor: CanvasViewModel) -> [CanvasItem.ID: String] {
        var words: [CanvasItem.ID: String] = [:]
        for item in editor.items {
            if case .text(let block) = item.content { words[item.id] = block.text }
        }
        return words
    }

    /// One-tap revert of the last applied change (the receipt's escape
    /// hatch). If anything else touched the canvas since the receipt was
    /// shown -- an edit, or words typed -- revert declines to undo (it would
    /// eat the user's edit, not Mira's) and just dismisses.
    public func revert(editor: CanvasViewModel) {
        if receiptStillLatest(on: editor) {
            editor.undo()
        }
        dismiss()
    }

    /// The view calls this when the canvas mutates. A showing receipt is
    /// accepted and dismissed (its Revert would no longer be honest, or it
    /// had none), and a lingering reply steps aside -- the user has gone back
    /// to making things.
    public func canvasDidChange(_ editor: CanvasViewModel) {
        switch phase {
        case .receipt:
            // A non-revertible receipt has no count to compare; any edit
            // means the user has moved on.
            if receiptStillLatest(on: editor) { return }
            dismiss()
        case .reply:
            dismiss()
        default:
            break
        }
    }

    /// Keep: dismissing keeps the change. A receipt never keeps by itself
    /// (screen 07 waits for the choice); an edit or a new ask moves on.
    public func dismiss() {
        receiptChangeCount = nil
        receiptWords = nil
        receiptEditor = nil
        phase = .idle
    }

    private func cancelTurn() {
        turnGeneration += 1
        turnTask?.cancel()
        turnTask = nil
        appliesFirstBackground = false
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
                // quickOrganize records its own step: the receipt's Revert
                // is exactly this one.
                editor.quickOrganize(canvasWidth: MiraNoteConfig.pageWidth)
                showReceipt(MiraReceipt(
                    changed: String(appCopy: "Tidied the layout."),
                    kept: String(appCopy: "Your words and photos are unchanged.")
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
                    message: String(appCopy: "The text I was working on is gone, so I left everything as is."),
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
        case .photoRestyleRequested(let request, let handles):
            startPhotoRestyleTurn(request, handles: handles, editor: editor)
        case .reply(let message, let newSessionID):
            sessionID = newSessionID ?? sessionID
            conversation.append(ChatMessage(role: .user, text: lastPrompt, isAppCopy: lastPromptIsAppCopy))
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
            if resolved.contains(where: { editor.item($0.id) != nil }) {
                // The right piece, but nothing asked for changes it (already
                // so, or a value the page cannot use): say so, with no Revert
                // -- an undo would take back an older step (#100).
                showReceipt(Self.unchangedReceipt(for: resolved, editor: editor),
                            editor: editor, revertible: false)
                return
            }
            // A receipt for a change that never landed would be a lie.
            failClarify("I could not tell which piece you meant -- which one should I move?")
            return
        }
        showReceipt(Self.receipt(for: resolved, editor: editor), editor: editor)
    }

    /// `revertible: false` is for a turn that changed nothing: its Revert
    /// only dismisses, since an undo would take back an older step.
    func showReceipt(_ receipt: MiraReceipt, editor: CanvasViewModel, revertible: Bool = true) {
        receiptChangeCount = revertible ? editor.changeCount : nil
        receiptWords = revertible ? Self.words(on: editor) : nil
        receiptEditor = editor
        phase = .receipt(receipt)
    }

    /// Start a NEW turn for slow image work Mira asked for.
    ///
    /// The chat turn that produced the request has already settled, so
    /// this cannot be its tail: without its own generation Stop would
    /// have nothing to cancel, and a late receipt could land on top of
    /// whatever the user did next. Every slow request goes through here,
    /// which is why +SlowWork can decide WHAT to run without reaching
    /// into the turn machinery.
    func startSlowTurn(_ intent: MiraIntent, verb: String, editor: CanvasViewModel) {
        cancelTurn()
        let generation = turnGeneration
        phase = .working(verb: verb)
        turnTask = Task { [lastPrompt] in
            await run(intent, prompt: lastPrompt, editor: editor, generation: generation)
        }
    }

    /// Ask instead of guessing, and give the words back. Used wherever a
    /// request names something that is no longer on the page.
    func failClarify(_ message: String, chips: [String] = ["Try again"]) {
        refillPrompt = lastPrompt
        phase = .failure(MiraFailure(kind: .clarify, message: message, chips: chips))
    }

    private static func failure(for error: Error) -> MiraFailure {
        if error is MiraTimeoutError {
            return MiraFailure(
                kind: .retry,
                message: String(appCopy: "This was taking too long, so I stopped. Try again?"),
                chips: ["Try again", "Rephrase"]
            )
        }
        if let clarify = error as? MiraClarifyError {
            return MiraFailure(kind: .clarify, message: clarify.question, chips: clarify.chips)
        }
        return MiraFailure(
            kind: .retry,
            message: String(appCopy: "That one did not go through. Try again, or say it differently?"),
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

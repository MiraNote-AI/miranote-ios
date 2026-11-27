import Foundation

/// Why "test-push this theme" stopped without a push. `text` is English,
/// for the debug page.
public enum ThemePushStop: Equatable, Sendable {
    /// This build finds no repeat themes (no `themeEngine`).
    case notSetUp
    /// No theme has that id (any more).
    case unknownTheme
    case sensitive
    case blocked
    /// The theme has no name to send.
    case unnamed
    /// Too few days of photos, and no big theme to fall back to.
    case notEnoughDays(String)
    /// Round 2 found it the same as, or much like, these listed themes.
    case similar([RoundTwoAnswer.Similar])
    /// Every round-2 try failed, for these reasons.
    case triesUsedUp([String])
    /// The repeat compose turned it down, with the backend's message.
    case composeRejected(String)

    public var text: String {
        switch self {
        case .notSetUp: return "Repeat themes are not set up in this build"
        case .unknownTheme: return "The theme is no longer in the library"
        case .sensitive: return "The theme is sensitive"
        case .blocked: return "The theme is blocked"
        case .unnamed: return "The theme has no name"
        case .notEnoughDays(let reason): return reason
        case .similar(let names):
            return "Too like " + names.map { "\($0.name) (\($0.level))" }.joined(separator: ", ")
        case .triesUsedUp(let reasons):
            return "\(reasons.count) round 2 tries did not pass: " + reasons.joined(separator: "; ")
        case .composeRejected(let message): return "Not written: \(message)"
        }
    }
}

/// What a repeat theme's debug push adds to its record and ledger row.
struct RepeatPushInfo: Sendable {
    let themeId: String
    let themeName: String
    let roundUsages: [RoundUsage]
    let roundTwoTries: [String]
}

/// "Test-push this theme" (spec 6.10, F2, 6.13): round 2 on the theme's
/// candidates, the photos picked, the repeat compose, pushed in 10 s as a
/// debug push. It never counts as pushed and never touches the plan.
extension PushScheduler {
    /// Round-2 tries one test push makes at most (F2).
    static let maxThemeTries = 3

    /// One press, as progress. A sensitive or blocked theme is refused
    /// with the reason and nothing is sent. A second press while one runs
    /// is ignored (its stream ends at once), as is any press turned off.
    public func tryTheme(_ themeId: String) -> AsyncStream<TriggerProgress> {
        let (stream, continuation) = AsyncStream<TriggerProgress>.makeStream()
        guard !themePressing, !isOff else {
            continuation.finish()
            return stream
        }
        themePressing = true
        let mine = generation
        themePress = Task { await self.pressTheme(themeId, generation: mine, out: continuation) }
        return stream
    }

    private func pressTheme(_ themeId: String, generation mine: Int,
                            out: AsyncStream<TriggerProgress>.Continuation) async {
        defer {
            themePressing = false
            themePress = nil
            out.finish()
        }
        out.yield(.preparing)
        guard await deps.notifications.requestPermission() else { return out.step(.failed(.notificationsOff)) }
        let access = await deps.library.requestAccess()
        guard access != .denied else { return out.step(.failed(.photosDenied)) }
        if access == .limited { out.yield(.partialLibrary) }
        guard let engine = deps.themeEngine else { return out.step(.themeStopped(.notSetUp)) }
        let rows = await engine.snapshot().themes
        guard let row = rows.first(where: { $0.id == themeId }) else {
            return out.step(.themeStopped(.unknownTheme))
        }
        if let refusal = Self.refusal(row) { return out.step(.themeStopped(refusal)) }
        let context = await themeContext(row, rows: rows, engine: engine)
        switch await checkRoundTwo(row, context: context, engine: engine, generation: mine, out: out) {
        case .stopped(let stop): out.yield(.themeStopped(stop))
        case .cancelled: return
        case .passed(let passed): await composeTheme(passed, context: context, generation: mine, out: out)
        }
    }

    /// Why `row` is not pushed whatever its photos, or nil.
    static func refusal(_ row: ThemeRow) -> ThemePushStop? {
        switch row.status {
        case .sensitive: return .sensitive
        case .blocked: return .blocked
        default: break
        }
        return row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unnamed : nil
    }

    // MARK: What the press reads

    /// The phone's view for one press: the library rows, the theme records
    /// and library assets of the theme and its big theme, the ledger.
    struct ThemeContext {
        let rows: [ThemeRow]
        let records: [String: ThemePhoto]
        let library: [String: LibraryAsset]
        let ledger: [LedgerEntry]
        let now: Date
        let calendar: Calendar
        /// Photo id -> local `yyyy-MM-dd`.
        let days: [String: String]
        /// Photos of repeat pushes that stand (not debug, not taken back):
        /// never shown again (S10 step 1).
        let repeatPushed: Set<String>
        /// Photos of life-fragment pushes that stand: their days go last.
        let lifeFragment: Set<String>

        func parent(of row: ThemeRow) -> ThemeRow? {
            row.parentId.flatMap { id in rows.first { $0.id == id } }
        }

        /// The theme's center; a small theme's is its big theme's.
        func center(of row: ThemeRow) -> [Float] {
            row.center ?? parent(of: row)?.center ?? []
        }

        var aesthetics: [String: Double] { records.compactMapValues(\.aesthetics) }
    }

    private func themeContext(_ row: ThemeRow, rows: [ThemeRow], engine: ThemeEngine) async -> ThemeContext {
        let now = deps.now()
        let calendar = deps.calendar()
        let parent = row.parentId.flatMap { id in rows.first { $0.id == id } }
        let wanted = Set(row.members + (parent?.members ?? []))
        let records = engine.deps.photos.loadAll().filter { wanted.contains($0.key) }
        let since = records.values.map(\.takenAt).min() ?? now
        let known = deps.analyses.loadAll().compactMapValues(\.originalFilename)
        let assets = await deps.library.assets(since: since, knownFilenames: known).filter { wanted.contains($0.id) }
        let ledger = deps.ledger.load()
        let standing = ledger.filter { !$0.isDebug && $0.removedAt == nil && $0.removedReason == nil }
        return ThemeContext(
            rows: rows, records: records,
            library: Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            ledger: ledger, now: now, calendar: calendar,
            days: records.mapValues { PushPhotoPicker.day($0.takenAt, calendar: calendar) },
            repeatPushed: Set(standing.filter { $0.mode == RepeatComposeMeta.mode }.flatMap(\.photoIds)),
            lifeFragment: Set(standing.filter { $0.mode != RepeatComposeMeta.mode }.flatMap(\.photoIds)))
    }

    /// Decision 12 on the theme's photos still in the library, minus those
    /// a repeat push showed.
    private func candidates(_ row: ThemeRow, context: ThemeContext) -> [String] {
        let ids = row.members.filter {
            context.records[$0] != nil && context.library[$0] != nil && !context.repeatPushed.contains($0)
        }
        var evidence: [String: Float] = [:]
        if case .content(let wanted) = row.rule {
            for id in ids {
                let scores = (context.records[id]?.labels ?? []).filter { wanted.contains($0.id) }.map(\.confidence)
                if let top = scores.max() { evidence[id] = top }
            }
        }
        return PushPhotoPicker.candidates(ids, takenAt: context.records.mapValues(\.takenAt), days: context.days,
                                          aesthetics: context.aesthetics,
                                          vectors: context.records.mapValues(\.vector),
                                          center: context.center(of: row), lifeFragmentPhotos: context.lifeFragment,
                                          evidence: evidence)
    }

    // MARK: Round 2

    struct PassedTheme {
        /// The theme pushed: the one pressed, or its big theme.
        let row: ThemeRow
        let photos: [String]
        let usages: [RoundUsage]
        /// Why the tries before failed.
        let tries: [String]
    }

    enum ThemeCheck {
        case passed(PassedTheme)
        case stopped(ThemePushStop)
        /// Turned off or cleared meanwhile: nothing more is said.
        case cancelled
    }

    /// What one round-2 try gave.
    private enum ThemeTry {
        case passed(photos: [String])
        case similar([RoundTwoAnswer.Similar])
        /// `short`: too few days (of candidates, or left after the answer).
        case failed(reason: String, short: Bool)
    }

    /// Up to three round-2 tries (F2). Under 5 days of candidates, or of
    /// photos left after the answer, a small theme falls back to its big
    /// theme (a try either way) and a big theme stops; a failed call or an
    /// answer that is not JSON is tried again; a listed name it is like
    /// stops at once.
    private func checkRoundTwo(_ pressed: ThemeRow, context: ThemeContext, engine: ThemeEngine, generation mine: Int,
                               out: AsyncStream<TriggerProgress>.Continuation) async -> ThemeCheck {
        var row = pressed
        var tries: [String] = []
        var usages: [RoundUsage] = []
        for attempt in 1...Self.maxThemeTries {
            guard mine == generation, !isOff, !Task.isCancelled else { return .cancelled }
            let (reason, short): (String, Bool)
            let (outcome, usage) = await themeTry(row, attempt: attempt, context: context, engine: engine, out: out)
            if let usage { usages.append(usage) }
            switch outcome {
            case .passed(let photos):
                return .passed(PassedTheme(row: row, photos: photos, usages: usages, tries: tries))
            case .similar(let names): return .stopped(.similar(names))
            case .failed(let why, let isShort): (reason, short) = (why, isShort)
            }
            tries.append(reason)
            guard attempt < Self.maxThemeTries else { break }
            if short {
                guard row.kind == .small, let parent = context.parent(of: row) else {
                    return .stopped(.notEnoughDays(reason))
                }
                if let refusal = Self.refusal(parent) { return .stopped(refusal) }
                row = parent
            }
            out.yield(.themeTryFailed(attempt: attempt, reason: reason))
        }
        return .stopped(.triesUsedUp(tries))
    }

    /// One try: the candidates (no call under 5 days of them), round 2,
    /// what is left of them; and what the call cost.
    private func themeTry(_ row: ThemeRow, attempt: Int, context: ThemeContext, engine: ThemeEngine,
                          out: AsyncStream<TriggerProgress>.Continuation) async -> (ThemeTry, RoundUsage?) {
        let candidates = candidates(row, context: context)
        guard candidates.count >= RoundTwo.minDays else {
            return (.failed(reason: "\(row.name): \(candidates.count) days of photos", short: true), nil)
        }
        out.yield(.checkingTheme(attempt: attempt, theme: row.name, candidates: candidates.count))
        let lists = RoundTwo.comparisonLists(ledger: context.ledger, rows: context.rows, themeId: row.id,
                                             now: context.now, calendar: context.calendar)
        let call = await engine.roundTwo(
            theme: RoundTwoRequest.Theme(name: row.name, noun: row.noun, samePart: row.samePart),
            candidates: candidates, pushed: lists.pushed, blocked: lists.blocked, themeId: row.id)
        switch call.result {
        case .failure(let failure):
            return (.failed(reason: "\(row.name): \(failure.text)", short: false), call.usage)
        case .success(let answer):
            guard answer.similarTo.isEmpty else { return (.similar(answer.similarTo), call.usage) }
            let left = RoundTwo.survivors(answer, candidates: call.numbering, aesthetics: context.aesthetics,
                                          days: context.days)
            guard left.days >= RoundTwo.minDays else {
                let reason = "\(row.name): \(left.days) days left after round 2"
                return (.failed(reason: reason, short: true), call.usage)
            }
            return (.passed(photos: left.photos), call.usage)
        }
    }

    // MARK: Compose and push

    /// The photos picked (decision 13), the repeat compose (or, with the
    /// fake AI, the memory made on the phone), the debug push.
    private func composeTheme(_ passed: PassedTheme, context: ThemeContext, generation mine: Int,
                              out: AsyncStream<TriggerProgress>.Continuation) async {
        let row = passed.row
        let picked = PushPhotoPicker.pick(passed.photos, vectors: context.records.mapValues(\.vector),
                                          takenAt: context.records.mapValues(\.takenAt),
                                          center: context.center(of: row))
        let nearby = QuestionPicker.nearbyTypes(context.ledger, around: context.now, calendar: context.calendar)
        let built = RepeatComposeMeta.build(theme: row, photoIds: picked, photos: context.records,
                                            library: context.library, recentQuestionTypes: nearby,
                                            calendar: context.calendar)
        out.yield(.composingTheme(theme: row.name, photos: built.meta.photos.count))
        let memory: TriggerMemory
        let photoIds: [String: String]
        if deps.fakeAI() {
            let aesthetics = built.photoIds.compactMapValues { context.records[$0]?.aesthetics }
            memory = FakeRepeatMemory.build(meta: built.meta, aesthetics: aesthetics, calendar: context.calendar,
                                            zh: deps.zh)
            photoIds = built.photoIds
        } else {
            let session = ComposeSession(library: deps.library, client: deps.client, sleep: deps.sleep)
            switch await session.run(built.meta, photoIds: built.photoIds) {
            case .success(let composed):
                (memory, photoIds) = (composed.memory, composed.photoIds)
            case .failure(let box):
                switch box.attempt {
                case .rejected(let message): return out.step(.themeStopped(.composeRejected(message)))
                case .stop(let failure): return out.step(.failed(failure))
                case .pushed: return
                }
            }
        }
        guard mine == generation, !isOff else { return }
        // The photos sent, P1... (by date); the push belongs to the last one's day.
        let shown = (0..<photoIds.count).compactMap { photoIds["P\($0 + 1)"] }
        let theme = RepeatPushInfo(themeId: row.id, themeName: row.name, roundUsages: passed.usages,
                                   roundTwoTries: passed.tries)
        switch await pushDebug(memory: QuestionPicker.picking(memory, nearby: nearby).memory, photoIds: photoIds,
                               rank: 1, score: Self.themeScore, bucket: .other,
                               belongsTo: shown.last.flatMap { context.days[$0] } ?? "",
                               groupKey: built.meta.groupKey, groupPhotos: shown, place: nil, generation: mine,
                               theme: theme) {
        case .pushed: out.yield(.scheduled(rank: 1, score: 0))
        case .refused: out.yield(.failed(.notificationsOff))
        case .cleared: return
        }
    }

    /// A theme push has no life-fragment score: every part 0, bucket other.
    static let themeScore = FragmentScore(r: 0, s: 0, p: 0, n: 0, u: 0, a: 0, base: 0, multiplier: 1, bucket: .other,
                                          total: 0, days: 0, pushable: true)
}

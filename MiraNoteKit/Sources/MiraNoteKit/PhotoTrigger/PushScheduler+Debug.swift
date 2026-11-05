import Foundation

/// The debug page's buttons (handoff 6.8). Debug pushes are marked in the
/// record and the ledger, never count as pushed, never change the schedule;
/// the "..." menu still applies to them.
extension PushScheduler {
    // MARK: Replan and clear

    /// Takes back every scheduled push and runs at once; the ledger,
    /// preferences and AI cache stay.
    public func replan() async {
        await removeActive(.replan) { _ in true }
        await request(.replan)
    }

    /// Back to the first launch: this feature's pending and delivered
    /// notifications, the ledger, preferences, AI cache, log, state, push
    /// records and last report are gone. The per-photo analyses stay
    /// (re-analysing the library costs minutes). Nothing runs until the
    /// app next comes to the front.
    public func clearAll() async {
        generation += 1
        pendingRerun = nil
        let pending = await deps.notifications.pending()
        var ours = Set(pending.filter(PushIdentifier.isOurs))
        let entries = deps.ledger.load()
        ours.formUnion(entries.map(\.identifier).filter(PushIdentifier.isOurs))
        ours.formUnion(deps.records.all().map { PushIdentifier.make($0.pushId) })
        let identifiers = ours.sorted()
        if !identifiers.isEmpty {
            await deps.notifications.removePending(identifiers)
            await deps.notifications.removeDelivered(identifiers)
        }
        try? deps.ledger.clear()
        try? deps.preferences.clear()
        try? deps.cache.clear()
        try? deps.log.clear()
        try? deps.state.clear()
        try? deps.records.removeAll()
        try? deps.lastRun.clear()
        // `work` stays: a run in flight sees the new generation and stops.
        previewCount = 0
        outsideCursor = nil
        lastReport = nil
        lastRanking = nil
    }

    /// Clears one blocked day (debug page).
    public func unblockDay(_ day: String) {
        try? deps.preferences.update { $0.blockedDays[day] = nil }
    }

    /// Clears one "fewer like this" (debug page).
    public func clearFewer(_ bucket: PushBucket) {
        try? deps.preferences.update { $0.fewer[bucket] = nil }
    }

    // MARK: Preview

    /// The Nth press sends a copy of the Nth scheduled push in night order
    /// (wrapping) in 10 s: same memory, no AI, schedule untouched.
    public func previewNext() async -> PreviewResult {
        let active = deps.ledger.load().filter(\.isActive).sorted { $0.scheduledFor < $1.scheduledFor }
        let pairs = active.compactMap { entry in deps.records.load(entry.pushId).map { (entry, $0) } }
        guard !pairs.isEmpty else { return .nothingScheduled }
        let (entry, record) = pairs[previewCount % pairs.count]
        previewCount += 1
        switch await pushDebug(memory: record.memory, photoIds: record.photoIds, rank: record.rank,
                               score: entry.score, bucket: entry.bucket, belongsTo: entry.belongsTo,
                               groupKey: entry.groupKey, groupPhotos: entry.photoIds, place: entry.place,
                               generation: generation) {
        case .pushed: break
        case .refused: return .notificationsOff
        case .cleared: return .nothingScheduled
        }
        let calendar = deps.calendar()
        return .scheduled(slotDay: SchedulePlanner.day(entry.scheduledFor, calendar: calendar))
    }

    // swiftlint:disable function_parameter_count
    /// Saves a debug record, schedules it 10 s out, writes its ledger row --
    /// unless `clearAll` ran since the press began (`generation`).
    func pushDebug(memory: TriggerMemory, photoIds: [String: String], rank: Int, score: FragmentScore,
                   bucket: PushBucket, belongsTo: String, groupKey: String, groupPhotos: [String],
                   place: String?, generation mine: Int) async -> DebugPush {
        guard mine == generation else { return .cleared }
        let pushId = UUID().uuidString
        let now = deps.now()
        let record = PushRecord(pushId: pushId, memory: memory, photoIds: photoIds, createdAt: now, rank: rank,
                                score: score.total, bucket: memory.bucket.isEmpty ? deps.zh(bucket.catalogKey)
                                    : memory.bucket,
                                bucketId: bucket, belongsTo: belongsTo, isDebug: true)
        guard (try? deps.records.save(record)) != nil else { return .refused }
        let identifier = PushIdentifier.make(pushId)
        guard await deps.notifications.schedule(record, identifier: identifier, at: nil, relevance: score.total)
        else {
            try? deps.records.remove(pushId)
            return .refused
        }
        guard mine == generation else {
            // Cleared while it was being scheduled: take it back.
            await deps.notifications.removePending([identifier])
            try? deps.records.remove(pushId)
            return .cleared
        }
        try? deps.ledger.append(LedgerEntry(
            pushId: pushId, isDebug: true, belongsTo: belongsTo, groupKey: groupKey, photoIds: groupPhotos,
            bucket: bucket, place: place, score: score, body: memory.push.body, question: memory.ending.question,
            questionType: memory.ending.questionType, scheduledFor: now.addingTimeInterval(Self.debugDelay)))
        return .pushed
    }
    // swiftlint:enable function_parameter_count

    // MARK: Try a group outside the schedule

    /// One press of "try a group outside the schedule", as phase-1
    /// progress: the candidates ranked now that are not among the seven
    /// nights, from where the last press stopped, at most three groups,
    /// back to the first with a `wrapped` notice past the end. A pass is
    /// pushed in 10 s as a debug push. A second press while one runs is
    /// ignored (its stream ends at once).
    public func tryOutside() -> AsyncStream<TriggerProgress> {
        let (stream, continuation) = AsyncStream<TriggerProgress>.makeStream()
        guard !outsidePressing else {
            continuation.finish()
            return stream
        }
        outsidePressing = true
        outsideGeneration = generation
        Task { await self.pressOutside(continuation) }
        return stream
    }

    private func pressOutside(_ out: AsyncStream<TriggerProgress>.Continuation) async {
        defer {
            outsidePressing = false
            out.finish()
        }
        out.yield(.preparing)
        guard await deps.notifications.requestPermission() else { return out.step(.failed(.notificationsOff)) }
        let access = await deps.library.requestAccess()
        guard access != .denied else { return out.step(.failed(.photosDenied)) }
        if access == .limited { out.yield(.partialLibrary) }
        let now = deps.now()
        let calendar = deps.calendar()
        let ranking: TriggerRanking
        if let last = lastRanking {
            ranking = last
        } else {
            ranking = await rank(now: now, calendar: calendar) { out.yield($0) }
            if outsideGeneration == generation { lastRanking = ranking }
        }
        let outside = outsideCandidates(ranking, now: now, calendar: calendar)
        guard !outside.isEmpty else { return out.step(.failed(.noFragment)) }
        await tryOutside(outside, ranking: ranking, calendar: calendar, out: out)
    }

    /// Eligible now, best first, minus the groups scheduled for the nights.
    /// A cached refusal stays in the list: trying it shows the reason.
    private func outsideCandidates(_ ranking: TriggerRanking, now: Date, calendar: Calendar) -> [PushCandidate] {
        let entries = deps.ledger.load()
        let scheduled = Set(entries.filter(\.isActive).map(\.groupKey))
        return PushCandidates.ranked(
            ranking.fragments, aiPhotoIds: { ranking.preselect($0).map(\.id) }, at: now,
            analyses: ranking.analyses, library: ranking.library, calendar: calendar,
            pastLocations: ranking.pastLocations, pushedDays: LedgerReconciler.pushedDays(entries),
            preferences: deps.preferences.load(), cache: { _ in nil })
            .filter { !scheduled.contains($0.groupKey) }
    }

    private func tryOutside(_ outside: [PushCandidate], ranking: TriggerRanking, calendar: Calendar,
                            out: AsyncStream<TriggerProgress>.Continuation) async {
        let count = outside.count
        var rank = outsideCursor ?? 1
        if rank > count {
            rank = 1
            out.yield(.wrapped)
        }
        let tries = min(TriggerRun.maxTries, count)
        for attempt in 0..<tries {
            let candidate = outside[rank - 1]
            switch await attemptOutside(candidate, rank: rank, ranking: ranking, calendar: calendar, out: out) {
            case .pushed:
                outsideCursor = rank + 1
                return
            case .stop(let failure):
                return out.step(.failed(failure))
            case .rejected(let message):
                let following = rank < count ? rank + 1 : 1
                guard attempt < tries - 1 else {
                    outsideCursor = following
                    return out.step(.allFailed(tried: tries))
                }
                out.yield(.rejected(rank: rank, message: message, next: following))
                if following == 1 { out.yield(.wrapped) }
                rank = following
            }
        }
    }

    /// The cached verdict when the photo set has one, else the AI (5 s
    /// polls, as phase 1), cached; a pass is pushed in 10 s.
    private func attemptOutside(_ candidate: PushCandidate, rank: Int, ranking: TriggerRanking, calendar: Calendar,
                                out: AsyncStream<TriggerProgress>.Continuation) async -> TriggerAttempt {
        let fragment = candidate.fragment
        let place = await placeName(fragment)
        out.yield(.askingAI(rank: rank, date: TriggerWords.shortDate(fragment.belongsTo), place: place,
                            count: fragment.uniqueCount))
        let picks = ranking.preselect(fragment)
        // A debug push goes out tonight: its question keeps off the nights around today.
        let nearby = QuestionPicker.nearbyTypes(deps.ledger.load(), around: deps.now(), calendar: calendar)
        let built = ComposeMeta.build(fragment: fragment, picks: picks, analyses: ranking.analyses,
                                      library: ranking.library, place: place, bucket: candidate.bucket,
                                      recentQuestionTypes: nearby, calendar: calendar)
        let memory: TriggerMemory
        let photoIds: [String: String]
        switch deps.cache.verdict(candidate.cacheKey) {
        case .ok(let cached, let ids):
            (memory, photoIds) = (cached, ids)
        case .rejected(_, let message):
            return .rejected(message)
        case nil where deps.fakeAI():
            memory = FakeAIMemory.build(meta: built.meta, photoIds: built.photoIds, picks: picks, calendar: calendar,
                                        zh: deps.zh)
            photoIds = built.photoIds
            store(.ok(memory: memory, photoIds: photoIds), candidate)
        case nil:
            let session = ComposeSession(library: deps.library, client: deps.client, sleep: deps.sleep)
            switch await session.run(built.meta, photoIds: built.photoIds) {
            case .success(let composed):
                (memory, photoIds) = (composed.memory, composed.photoIds)
                store(.ok(memory: memory, photoIds: photoIds), candidate)
            case .failure(let box):
                if case .rejected(let message) = box.attempt, message != ComposeSession.unreadableMessage {
                    store(.rejected(reason: "rejected", message: message), candidate)
                }
                return box.attempt
            }
        }
        switch await pushDebug(memory: QuestionPicker.picking(memory, nearby: nearby).memory, photoIds: photoIds,
                               rank: rank, score: candidate.score,
                               bucket: candidate.bucket, belongsTo: candidate.belongsTo, groupKey: candidate.groupKey,
                               groupPhotos: fragment.photos.map(\.id), place: place, generation: outsideGeneration) {
        case .pushed: break
        case .refused: return .stop(.notificationsOff)
        // Cleared during the press: nothing of it is kept.
        case .cleared: return .stop(.noFragment)
        }
        out.yield(.scheduled(rank: rank, score: candidate.score.total))
        return .pushed
    }

    private func store(_ verdict: AIVerdict, _ candidate: PushCandidate) {
        guard outsideGeneration == generation else { return }
        try? deps.cache.store(verdict, key: candidate.cacheKey, belongsTo: candidate.belongsTo, at: deps.now())
    }

    // MARK: Snapshot

    /// The debug page's view: the next seven nights (after tonight's push
    /// when it is under 30 min away and so not one of them), the log, counters,
    /// preferences and the last run's fragments with what became of them.
    /// Built from stored results; never regroups.
    public func snapshot() -> SchedulerSnapshot {
        let calendar = deps.calendar()
        let now = deps.now()
        if lastReport == nil { lastReport = deps.lastRun.load() }
        let report = lastReport
        let active = deps.ledger.load().filter(\.isActive)
        var slots = PushSlots.make(now: now, calendar: calendar)
        // Tonight's push under 30 min away is not one of the nights, yet still to come.
        let tonight = active.filter { $0.scheduledFor >= now && calendar.isDate($0.scheduledFor, inSameDayAs: now) }
            .min { $0.scheduledFor < $1.scheduledFor }
        if let tonight, !slots.contains(where: { calendar.isDate($0, inSameDayAs: now) }) {
            slots.insert(tonight.scheduledFor, at: 0)
        }
        let days = slots.map { slot -> SchedulerSnapshot.Day in
            let day = SchedulePlanner.day(slot, calendar: calendar)
            let entry = active.filter { calendar.isDate($0.scheduledFor, inSameDayAs: slot) }
                .min { $0.scheduledFor < $1.scheduledFor }
            return SchedulerSnapshot.Day(slot: slot, slotDay: day, entry: entry,
                                         emptyReason: entry == nil ? report?.emptyDays[day] : nil)
        }
        let verdicts = deps.cache.verdicts()
        let scheduled = Dictionary(
            active.map { ($0.groupKey, SchedulePlanner.day($0.scheduledFor, calendar: calendar)) },
            uniquingKeysWith: { first, _ in first })
        let groups = (report?.fragments ?? []).map { fragment -> SchedulerSnapshot.Group in
            let status: AIStatus
            switch verdicts[fragment.cacheKey] {
            case .ok: status = .ok
            case .rejected(_, let message): status = .rejected(message)
            case nil: status = .notSent
            }
            return SchedulerSnapshot.Group(report: fragment, scheduledDay: scheduled[fragment.groupKey],
                                           aiStatus: status)
        }
        return SchedulerSnapshot(
            days: days, runs: deps.log.runs(), counters: deps.log.counters(), preferences: deps.preferences.load(),
            groups: groups, utilityPhotoIds: report?.utility ?? [], categories: report?.categories ?? .empty,
            threshold: report?.threshold, isRunning: isRunning)
    }
}

/// What became of a debug push.
enum DebugPush {
    case pushed
    /// No record saved, or the system did not take the notification.
    case refused
    /// `clearAll` ran during the press: nothing of it is left.
    case cleared
}

private extension AsyncStream<TriggerProgress>.Continuation {
    /// `yield` without its result, so a guard can `return` it.
    func step(_ progress: TriggerProgress) {
        yield(progress)
    }
}

import Foundation

extension PushScheduler {
    // MARK: Walking the nights

    /// Decides every night: kept, cached, or sent to the AI; then polls the
    /// jobs, scheduling each night as its answer comes back.
    func walk(_ context: RunContext) async {
        work.orphans = orphanClaims()
        await settle(context)
        while work.days.contains(where: \.isWaiting), context.generation == generation {
            await pollWave(context)
            guard context.generation == generation else { return }
            await settle(context)
        }
    }

    /// Active pushes outside the seven nights (tonight's, under 30 min away)
    /// still hold their group and day.
    private func orphanClaims() -> [(group: String, day: String)] {
        let planned = Set(work.days.compactMap(\.plan.existing?.pushId))
        return deps.ledger.load().filter { $0.isActive && !planned.contains($0.pushId) }
            .map { ($0.groupKey, $0.belongsTo) }
    }

    /// Walks the open nights until none moves; submits what needs the AI.
    private func settle(_ context: RunContext) async {
        while context.generation == generation {
            var moved = false
            var asks: [Int] = []
            for index in work.days.indices {
                guard case .open = work.days[index].state else { continue }
                let step = step(index)
                if case .deferred = step { continue }
                if await move(index, step, context: context) { asks.append(index) }
                moved = true
            }
            if !asks.isEmpty { await send(asks, context: context) }
            if moved { continue }
            // Nights waiting on each other's pushes with nothing out: the first keeps its own.
            guard !work.days.contains(where: \.isWaiting),
                  let stuck = work.days.firstIndex(where: { if case .open = $0.state { true } else { false } })
            else { return }
            work.days[stuck].state = work.days[stuck].plan.existing == nil ? .empty("noCandidate") : .kept
        }
    }

    /// Acts on a night's step; true when it needs the AI.
    private func move(_ index: Int, _ step: DayStep, context: RunContext) async -> Bool {
        let existing = work.days[index].plan.existing
        switch step {
        case .deferred: return false
        case .keep: work.days[index].state = .kept
        case .exhausted: work.days[index].state = existing == nil ? .empty("noCandidate") : .kept
        case .cached(let candidate, let memory, let photoIds):
            work.days[index].state = .asking(candidate)
            log(index, candidate, .cachedOk, since: deps.now())
            let place = await placeName(candidate.fragment)
            await schedule(index, candidate, memory: memory, photoIds: photoIds, place: place, context: context)
        case .ask(let candidate):
            work.days[index].state = .asking(candidate)
            return true
        }
        return false
    }

    /// The night's next move. A candidate another night has taken is
    /// skipped; one another undecided night may keep waits for it.
    private func step(_ index: Int) -> DayStep {
        let others = work.days.indices.filter { $0 != index }
        let taken = others.compactMap { work.days[$0].claim } + work.orphans
        let held = others.compactMap { work.days[$0].holds }
        let day = work.days[index]
        var next = day.next
        defer { work.days[index].next = next }
        while next < day.plan.queue.count {
            let candidate = day.plan.queue[next]
            if taken.contains(where: { $0.group == candidate.groupKey || $0.day == candidate.belongsTo }) {
                next += 1
                continue
            }
            if held.contains(where: { $0.groupKey == candidate.groupKey || $0.belongsTo == candidate.belongsTo }) {
                return .deferred
            }
            next += 1
            if candidate.groupKey == day.plan.existing?.groupKey { return .keep }
            if case .ok(let memory, let photoIds) = work.verdicts[candidate.cacheKey] {
                return .cached(candidate, memory: memory, photoIds: photoIds)
            }
            return .ask(candidate)
        }
        return .exhausted
    }

    // MARK: Submitting

    /// Reads and submits every asked night's photos at once (or builds the
    /// fake AI's memory, or picks up a job submitted under an hour ago).
    private func send(_ indices: [Int], context: RunContext, resubmitting: [Int: AIJob] = [:]) async {
        let now = deps.now()
        let outstanding = deps.state.load().outstanding
        let asks = indices.compactMap { index -> AIAsk? in
            if let job = resubmitting[index] {
                return AIAsk(day: index, candidate: job.candidate, picks: context.picks[job.candidate.groupKey] ?? [],
                             resume: nil, prepared: job.prepared, waited: job.waited, resubmitted: true)
            }
            guard case .asking(let candidate) = work.days[index].state else { return nil }
            let fresh = outstanding[candidate.cacheKey].flatMap {
                now.timeIntervalSince($0.submittedAt) < Self.jobLifetime ? $0 : nil
            }
            return AIAsk(day: index, candidate: candidate, picks: context.picks[candidate.groupKey] ?? [],
                         resume: fresh, prepared: nil, waited: 0, resubmitted: false)
        }
        let deps = self.deps
        let fake = deps.fakeAI()
        let recent = deps.records.recentQuestionIds()
        let results = await withTaskGroup(of: (AIAsk, AISent).self) { group in
            for ask in asks {
                group.addTask {
                    (ask, await Self.send(ask, deps: deps, context: context, fake: fake, recent: recent, now: now))
                }
            }
            var all: [(AIAsk, AISent)] = []
            for await result in group { all.append(result) }
            return all.sorted { $0.0.day < $1.0.day }
        }
        guard context.generation == generation else { return }
        for (ask, sent) in results { await apply(sent, for: ask, context: context) }
    }

    private func apply(_ sent: AISent, for ask: AIAsk, context: RunContext) async {
        let index = ask.day
        let candidate = ask.candidate
        switch sent {
        case .job(let job, let submitted):
            if submitted {
                work.aiSent += 1
                try? deps.state.update {
                    $0.outstanding[candidate.cacheKey] = OutstandingJob(
                        jobId: job.jobId, submittedAt: job.startedAt, slotDay: work.days[index].plan.slotDay,
                        photoIds: job.photoIds)
                }
            }
            work.days[index].state = .waiting(job)
        case .fake(let memory, let photoIds, let place):
            let verdict = AIVerdict.ok(memory: memory, photoIds: photoIds)
            remember(verdict, candidate)
            log(index, candidate, .ok, since: deps.now())
            await schedule(index, candidate, memory: memory, photoIds: photoIds, place: place, context: context)
        case .unreadable:
            log(index, candidate, .rejected, since: deps.now(), message: ComposeSession.unreadableMessage)
            work.days[index].state = .open
        case .failed(let message):
            end(index, candidate, since: deps.now(), message: message)
        }
    }

    // swiftlint:disable function_parameter_count
    /// One night's photos read and submitted, off the actor.
    private static func send(_ ask: AIAsk, deps: SchedulerDependencies, context: RunContext, fake: Bool,
                             recent: [String], now: Date) async -> AISent {
        let fragment = ask.candidate.fragment
        var place: String?
        if let center = fragment.center { place = await deps.places.name(for: center) }
        let ranking = context.ranking
        let built = ComposeMeta.build(fragment: fragment, picks: ask.picks, analyses: ranking.analyses,
                                      library: ranking.library, place: place, bucket: ask.candidate.bucket,
                                      recentQuestionIds: recent, calendar: context.calendar)
        if fake {
            let memory = FakeAIMemory.build(meta: built.meta, photoIds: built.photoIds, picks: ask.picks,
                                            calendar: context.calendar, zh: deps.zh)
            return .fake(memory, photoIds: built.photoIds, place: place)
        }
        if let resume = ask.resume {
            let job = AIJob(candidate: ask.candidate, jobId: resume.jobId, prepared: nil,
                            photoIds: resume.photoIds ?? built.photoIds, place: place, startedAt: resume.submittedAt,
                            waited: 0, resubmitted: false)
            return .job(job, submitted: false)
        }
        let session = ComposeSession(library: deps.library, client: deps.client, sleep: deps.sleep)
        var prepared = ask.prepared
        if prepared == nil { prepared = await session.prepare(built.meta, photoIds: built.photoIds) }
        guard let prepared else { return .unreadable }
        var waited = ask.waited
        switch await session.submit(prepared.meta, photos: prepared.uploads, waited: &waited) {
        case .success(let jobId):
            let job = AIJob(candidate: ask.candidate, jobId: jobId, prepared: prepared, photoIds: prepared.photoIds,
                            place: place, startedAt: now, waited: waited, resubmitted: ask.resubmitted)
            return .job(job, submitted: true)
        case .failure(let box):
            return .failed(Self.describe(box.attempt))
        }
    }
    // swiftlint:enable function_parameter_count

    // MARK: Polling

    /// One batch poll of every job out, 15 s after the last.
    private func pollWave(_ context: RunContext) async {
        try? await deps.sleep(Self.pollInterval)
        addWait(Self.pollInterval)
        guard context.generation == generation else { return }
        let jobs = work.days.indices.compactMap { index -> (Int, AIJob)? in
            if case .waiting(let job) = work.days[index].state { return (index, job) }
            return nil
        }
        guard !jobs.isEmpty else { return }
        let statuses: [String: ComposeJobStatus]
        do {
            statuses = try await deps.client.pollMany(jobs.map(\.1.jobId))
            work.transportFailures = 0
        } catch {
            return await pollFailed(error)
        }
        guard context.generation == generation else { return }
        var resubmits: [Int: AIJob] = [:]
        for (index, sent) in jobs {
            // Re-read: the night may have changed while a push was being scheduled.
            guard case .waiting(let job) = work.days[index].state, job.jobId == sent.jobId else { continue }
            if await answer(statuses[job.jobId] ?? .expired, job: job, index: index, context: context) {
                resubmits[index] = job
            }
        }
        if !resubmits.isEmpty {
            await send(Array(resubmits.keys).sorted(), context: context, resubmitting: resubmits)
        }
    }

    /// Acts on one job's status; true when it expired and goes out again.
    private func answer(_ status: ComposeJobStatus, job: AIJob, index: Int, context: RunContext) async -> Bool {
        if case .running = status {
            guard job.waited >= ComposeSession.budget else { return false }
            forget(job)
            end(index, job.candidate, since: job.startedAt, message: Self.describe(.stop(.aiTimeout)))
            return false
        }
        forget(job)
        switch status {
        case .running: break
        case .ok(let memory):
            remember(.ok(memory: memory, photoIds: job.photoIds), job.candidate)
            log(index, job.candidate, .ok, since: job.startedAt)
            await schedule(index, job.candidate, memory: memory, photoIds: job.photoIds, place: job.place,
                           context: context)
        case .rejected(let reason, let message):
            remember(.rejected(reason: reason, message: message), job.candidate)
            log(index, job.candidate, .rejected, since: job.startedAt, message: message)
            work.days[index].state = .open
        case .failed(let reason, let message):
            let failure: TriggerFailure = reason == "timeout" ? .aiTimeout
                : .backend(message.isEmpty ? reason : message)
            end(index, job.candidate, since: job.startedAt, message: Self.describe(.stop(failure)))
        case .expired:
            guard job.resubmitted else { return true }
            end(index, job.candidate, since: job.startedAt, message: Self.describe(.stop(.aiTimeout)))
        }
        return false
    }

    /// A 429 waits 10 s; no connection three polls in a row, or any other
    /// error, ends every night still waiting.
    private func pollFailed(_ error: Error) async {
        switch error as? ComposeError {
        case .rateLimited:
            try? await deps.sleep(ComposeSession.rateLimitWait)
            addWait(ComposeSession.rateLimitWait)
        case .unreachable:
            work.transportFailures += 1
            guard work.transportFailures >= ComposeSession.transportRetries else { return }
            endAllWaiting(message: Self.describe(.stop(.backendUnreachable)))
        default:
            endAllWaiting(message: Self.describe(.stop(ComposeSession.failure(for: error))))
        }
    }

    private func addWait(_ seconds: TimeInterval) {
        for index in work.days.indices {
            if case .waiting(var job) = work.days[index].state {
                job.waited += seconds
                work.days[index].state = .waiting(job)
            }
        }
    }

    private func endAllWaiting(message: String) {
        for index in work.days.indices {
            if case .waiting(let job) = work.days[index].state {
                forget(job)
                end(index, job.candidate, since: job.startedAt, message: message)
            }
        }
    }

    /// The night is left as it was: its push kept, or empty.
    private func end(_ index: Int, _ candidate: PushCandidate, since: Date, message: String) {
        log(index, candidate, .error, since: since, message: message)
        let reason = work.leftDays.contains(index) ? "leftBeforeResult" : "aiError"
        work.days[index].state = work.days[index].plan.existing == nil ? .empty(reason) : .kept
    }

    private func remember(_ verdict: AIVerdict, _ candidate: PushCandidate) {
        work.verdicts[candidate.cacheKey] = verdict
        try? deps.cache.store(verdict, key: candidate.cacheKey, belongsTo: candidate.belongsTo, at: deps.now())
    }

    /// The job is answered: a relaunch need not poll it.
    private func forget(_ job: AIJob) {
        try? deps.state.update { $0.outstanding[job.candidate.cacheKey] = nil }
    }

    func log(_ index: Int, _ candidate: PushCandidate, _ outcome: ScheduleRun.GroupOutcome.Outcome, since: Date,
             message: String? = nil) {
        work.outcomes.append(ScheduleRun.GroupOutcome(
            slotDay: work.days[index].plan.slotDay, groupKey: candidate.groupKey, belongsTo: candidate.belongsTo,
            outcome: outcome, seconds: max(0, deps.now().timeIntervalSince(since)), message: message))
    }

    func placeName(_ fragment: Fragment) async -> String? {
        guard let center = fragment.center else { return nil }
        return await deps.places.name(for: center)
    }

    static func describe(_ attempt: TriggerAttempt) -> String {
        switch attempt {
        case .pushed: return "pushed"
        case .rejected(let message): return message
        case .stop(let failure):
            switch failure {
            case .backendUnreachable: return "backendUnreachable"
            case .aiTimeout: return "aiTimeout"
            case .noFragment: return "noFragment"
            case .notificationsOff: return "notificationsOff"
            case .photosDenied: return "photosDenied"
            case .unauthorized: return "unauthorized"
            case .backend(let message): return message
            }
        }
    }

    // MARK: Scheduling

    // swiftlint:disable function_parameter_count
    /// Saves the record, schedules the night's notification, writes the
    /// ledger row, then takes back the push it replaces.
    func schedule(_ index: Int, _ candidate: PushCandidate, memory: TriggerMemory, photoIds: [String: String],
                  place: String?, context: RunContext) async {
        guard context.generation == generation else { return }
        let plan = work.days[index].plan
        let fallback: DayState = plan.existing == nil ? .empty("notificationsOff") : .kept
        let pushId = UUID().uuidString
        let record = PushRecord(
            pushId: pushId, memory: memory, photoIds: photoIds, createdAt: deps.now(), rank: index + 1,
            score: candidate.score.total, bucket: memory.bucket.isEmpty ? deps.zh(candidate.bucket.catalogKey)
                : memory.bucket,
            bucketId: candidate.bucket, belongsTo: candidate.belongsTo, isDebug: false)
        guard (try? deps.records.save(record)) != nil else {
            work.days[index].state = plan.existing == nil ? .empty("aiError") : .kept
            return
        }
        let parts = context.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.slot)
        guard await deps.notifications.schedule(record, identifier: PushIdentifier.make(pushId), at: parts,
                                                relevance: candidate.score.total)
        else {
            work.days[index].state = fallback
            return
        }
        try? deps.ledger.append(LedgerEntry(
            pushId: pushId, belongsTo: candidate.belongsTo, groupKey: candidate.groupKey,
            photoIds: candidate.fragment.photos.map(\.id), bucket: candidate.bucket, place: place,
            score: candidate.score, body: memory.push.body, questionId: memory.ending.questionId,
            scheduledFor: plan.slot))
        if let existing = plan.existing {
            await removeActive(.replaced) { $0.pushId == existing.pushId }
        }
        work.days[index].state = .scheduled(candidate)
    }
    // swiftlint:enable function_parameter_count
}

import Foundation

extension PushScheduler {
    // MARK: Walking the nights

    /// Decides every night: kept, cached, or sent to the AI; then polls the
    /// jobs, scheduling each night as its answer comes back. A cancelled
    /// task stops polling (its sleeps would return at once): the nights
    /// still waiting count as AI errors and the next return runs again.
    func walk(_ context: RunContext) async {
        work.orphans = orphanClaims()
        await settle(context)
        while work.days.contains(where: \.isWaiting), context.generation == generation, !Task.isCancelled {
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
                guard context.generation == generation else { return }
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
            if work.failedGroups.contains(candidate.groupKey) || isRejected(candidate)
                || taken.contains(where: { $0.group == candidate.groupKey || $0.day == candidate.belongsTo }) {
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

    /// Turned down earlier in this run (or cached so): never sent again.
    private func isRejected(_ candidate: PushCandidate) -> Bool {
        if case .rejected = work.verdicts[candidate.cacheKey] { return true }
        return false
    }

    // MARK: Submitting

    /// Reads and submits every asked night's photos at once (or builds the
    /// fake AI's memory, or picks up a job submitted under an hour ago).
    private func send(_ indices: [Int], context: RunContext, resubmitting: [Int: AIJob] = [:]) async {
        let now = deps.now()
        let outstanding = deps.state.load().outstanding
        let entries = deps.ledger.load()
        let asks = indices.compactMap { index -> AIAsk? in
            // The questions fixed so far around the night this group may land on.
            let nearby = QuestionPicker.nearbyTypes(entries, around: work.days[index].plan.slot,
                                                    calendar: context.calendar)
            if let job = resubmitting[index] {
                return AIAsk(day: index, candidate: job.candidate, picks: context.picks[job.candidate.groupKey] ?? [],
                             recentTypes: nearby, resume: nil, prepared: job.prepared, budgetFrom: job.budgetFrom,
                             resubmitted: true)
            }
            guard case .asking(let candidate) = work.days[index].state else { return nil }
            let fresh = outstanding[candidate.cacheKey].flatMap {
                now.timeIntervalSince($0.submittedAt) < Self.jobLifetime ? $0 : nil
            }
            return AIAsk(day: index, candidate: candidate, picks: context.picks[candidate.groupKey] ?? [],
                         recentTypes: nearby, resume: fresh, prepared: nil, budgetFrom: nil, resubmitted: false)
        }
        let deps = self.deps
        let fake = deps.fakeAI()
        // A task of its own, so `turnOff` can cancel the uploads not yet sent.
        let wave = Task {
            await withTaskGroup(of: (AIAsk, AISent).self) { group in
                for ask in asks {
                    group.addTask {
                        (ask, await Self.send(ask, deps: deps, context: context, fake: fake, now: now))
                    }
                }
                var all: [(AIAsk, AISent)] = []
                for await result in group { all.append(result) }
                return all.sorted { $0.0.day < $1.0.day }
            }
        }
        self.wave = wave
        let results = await wave.value
        if self.wave == wave { self.wave = nil }
        guard context.generation == generation else { return }
        for (ask, sent) in results where context.generation == generation {
            await apply(sent, for: ask, context: context)
        }
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
            // Known to this run only: the fake AI's words never enter the cache.
            work.verdicts[candidate.cacheKey] = .ok(memory: memory, photoIds: photoIds)
            log(index, candidate, .ok, since: deps.now())
            await schedule(index, candidate, memory: memory, photoIds: photoIds, place: place, context: context)
        case .unreadable:
            log(index, candidate, .rejected, since: deps.now(), message: ComposeSession.unreadableMessage)
            work.days[index].state = .open
        case .failed(let message):
            end(index, candidate, since: deps.now(), message: message)
        }
    }

    /// The run log's message for a night left for a geocoder error.
    static let placeUnavailable = "placeUnavailable"

    /// One night's photos read and submitted, off the actor.
    private static func send(_ ask: AIAsk, deps: SchedulerDependencies, context: RunContext, fake: Bool,
                             now: Date) async -> AISent {
        let fragment = ask.candidate.fragment
        var place: String?
        if let center = fragment.center {
            do {
                place = try await deps.places.name(for: center)
            } catch {
                // A failed lookup is not "no place": composed now, the night
                // would be cached without it. It is tried on a later run.
                // A job already out keeps the place it was sent with.
                guard ask.resume != nil else { return .failed(Self.placeUnavailable) }
            }
        }
        let ranking = context.ranking
        let built = ComposeMeta.build(fragment: fragment, picks: ask.picks, analyses: ranking.analyses,
                                      library: ranking.library, place: place, bucket: ask.candidate.bucket,
                                      recentQuestionTypes: ask.recentTypes,
                                      calendar: context.calendar)
        if fake {
            let memory = FakeAIMemory.build(meta: built.meta, photoIds: built.photoIds, picks: ask.picks,
                                            calendar: context.calendar, zh: deps.zh)
            return .fake(memory, photoIds: built.photoIds, place: place)
        }
        if let resume = ask.resume {
            let job = AIJob(candidate: ask.candidate, jobId: resume.jobId, prepared: nil,
                            photoIds: resume.photoIds ?? built.photoIds, place: place, startedAt: resume.submittedAt,
                            budgetFrom: now, resubmitted: false)
            return .job(job, submitted: false)
        }
        let session = ComposeSession(library: deps.library, client: deps.client, sleep: deps.sleep)
        var prepared = ask.prepared
        if prepared == nil { prepared = await session.prepare(built.meta, photoIds: built.photoIds) }
        guard let prepared else { return .unreadable }
        var waited: TimeInterval = 0
        switch await session.submit(prepared.meta, photos: prepared.uploads, waited: &waited) {
        case .success(let jobId):
            // Timed from the submit: slow photo reads (iCloud) do not use up the job's 6 minutes.
            let submitted = deps.now()
            let job = AIJob(candidate: ask.candidate, jobId: jobId, prepared: prepared, photoIds: prepared.photoIds,
                            place: place, startedAt: submitted, budgetFrom: ask.budgetFrom ?? submitted,
                            resubmitted: ask.resubmitted)
            return .job(job, submitted: true)
        case .failure(let box):
            return .failed(Self.describe(box.attempt))
        }
    }

    // MARK: Polling

    /// One batch poll of every job out, 15 s after the last.
    private func pollWave(_ context: RunContext) async {
        try? await deps.sleep(Self.pollInterval)
        guard context.generation == generation else { return }
        endOverBudget()
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
        for (index, sent) in jobs where context.generation == generation {
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
            guard isOverBudget(job) else { return false }
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

    /// A 429 waits 10 s; no connection, a server error or a body that is
    /// not JSON three polls in a row (`ComposeSession.isTransient`), or any
    /// other error at once, ends every night still waiting.
    private func pollFailed(_ error: Error) async {
        if case .rateLimited = error as? ComposeError {
            try? await deps.sleep(ComposeSession.rateLimitWait)
            return
        }
        if ComposeSession.isTransient(error) {
            work.transportFailures += 1
            guard work.transportFailures >= ComposeSession.transportRetries else { return }
        }
        endAllWaiting(message: Self.describe(.stop(ComposeSession.failure(for: error))))
    }

    /// Never while the app is in the background: a poll woken after a long
    /// suspension can reach the actor before `appBecameActive` restarts the
    /// budgets, and must not end jobs the backend still holds.
    private func isOverBudget(_ job: AIJob) -> Bool {
        guard !inBackground else { return false }
        return deps.now().timeIntervalSince(job.budgetFrom) >= ComposeSession.budget
    }

    /// Ends every night whose job has waited 6 minutes, whatever the last
    /// poll said (a steady 429 must not keep the run open).
    private func endOverBudget() {
        for index in work.days.indices {
            if case .waiting(let job) = work.days[index].state, isOverBudget(job) {
                forget(job)
                end(index, job.candidate, since: job.startedAt, message: Self.describe(.stop(.aiTimeout)))
            }
        }
    }

    /// Back at the front: time suspended in the background does not use up
    /// a job's budget; polling resumes with the full 6 minutes.
    func restartBudgets() {
        let now = deps.now()
        for index in work.days.indices {
            if case .waiting(var job) = work.days[index].state {
                job.budgetFrom = now
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
        work.failedGroups.insert(candidate.groupKey)
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
}

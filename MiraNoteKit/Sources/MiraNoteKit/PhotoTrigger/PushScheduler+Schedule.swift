import Foundation

/// Scheduling one night, and the run log.
extension PushScheduler {
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
    /// Picks the question for the night, saves the record, schedules the
    /// night's notification, writes the ledger row, then takes back the
    /// push it replaces. Nights are scheduled one at a time on the actor,
    /// so each pick sees the ledger rows of the picks before it. A memory
    /// the fake AI made is refused once the switch is off (the run that
    /// follows asks the backend).
    func schedule(_ index: Int, _ candidate: PushCandidate, memory answered: TriggerMemory,
                  photoIds: [String: String], place: String?, context: RunContext) async {
        guard context.generation == generation else { return }
        let plan = work.days[index].plan
        let unfaked: DayState = plan.existing == nil ? .empty("aiError") : .kept
        guard !answered.isFakeMade || deps.fakeAI() else {
            work.days[index].state = unfaked
            return
        }
        // The wave may have run into the hour before the old push fires: it stays.
        if let existing = plan.existing,
           existing.scheduledFor.timeIntervalSince(deps.now()) <= SchedulePlanner.lockWindow {
            work.days[index].state = .kept
            return
        }
        let fallback: DayState = plan.existing == nil ? .empty("notificationsOff") : .kept
        let nearby = QuestionPicker.nearbyTypes(deps.ledger.load(), around: plan.slot, calendar: context.calendar)
        let (memory, clashed) = QuestionPicker.picking(answered, nearby: nearby)
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
        let identifier = PushIdentifier.make(pushId)
        adding.insert(identifier)
        defer { adding.remove(identifier) }
        let parts = context.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.slot)
        guard await deps.notifications.schedule(record, identifier: identifier, at: parts,
                                                relevance: candidate.score.total)
        else {
            try? deps.records.remove(pushId)
            work.days[index].state = fallback
            return
        }
        guard context.generation == generation else {
            // Cleared while it was being scheduled: take it back.
            await deps.notifications.removePending([identifier])
            try? deps.records.remove(pushId)
            return
        }
        guard !answered.isFakeMade || deps.fakeAI() else {
            // The switch went off while it was being scheduled: take it back.
            await deps.notifications.removePending([identifier])
            try? deps.records.remove(pushId)
            work.days[index].state = unfaked
            return
        }
        try? deps.ledger.append(LedgerEntry(
            pushId: pushId, belongsTo: candidate.belongsTo, groupKey: candidate.groupKey,
            photoIds: candidate.fragment.photos.map(\.id), bucket: candidate.bucket, place: place,
            score: candidate.score, body: memory.push.body, question: memory.ending.question,
            questionType: memory.ending.questionType, scheduledFor: plan.slot))
        if clashed {
            work.questionClashes.append(ScheduleRun.QuestionClash(
                slotDay: plan.slotDay, types: answered.ending.questions.map(\.type), nearby: nearby))
        }
        if let existing = plan.existing {
            await removeActive(.replaced) { $0.pushId == existing.pushId }
        }
        work.days[index].state = .scheduled(candidate)
    }
    // swiftlint:enable function_parameter_count
}

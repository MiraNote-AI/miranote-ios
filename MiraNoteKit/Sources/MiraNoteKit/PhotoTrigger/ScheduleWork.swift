import Foundation

/// One night through a run.
struct DayWork: Sendable {
    let plan: DayPlan
    /// The next queue position to look at.
    var next = 0
    var state: DayState

    init(_ plan: DayPlan) {
        self.plan = plan
        state = plan.locked ? .kept : .open
    }

    /// The group and belongs-to day this night has taken: its pick, or the
    /// push it keeps.
    var claim: (group: String, day: String)? {
        switch state {
        case .kept: return plan.existing.map { ($0.groupKey, $0.belongsTo) }
        case .scheduled(let candidate), .asking(let candidate): return (candidate.groupKey, candidate.belongsTo)
        case .waiting(let job): return (job.candidate.groupKey, job.candidate.belongsTo)
        case .open, .empty: return nil
        }
    }

    /// Still undecided with a push scheduled: it may yet keep that push.
    var holds: LedgerEntry? {
        switch state {
        case .open, .asking, .waiting: return plan.existing
        case .kept, .scheduled, .empty: return nil
        }
    }

    var isWaiting: Bool {
        switch state {
        case .waiting, .asking: return true
        default: return false
        }
    }
}

enum DayState: Sendable {
    /// Not decided: the queue is walked from `next`.
    case open
    /// Being read and submitted.
    case asking(PushCandidate)
    /// Its job is out.
    case waiting(AIJob)
    /// The existing push stays.
    case kept
    case scheduled(PushCandidate)
    /// Nothing tonight, and why.
    case empty(String)
}

/// A backend job out for one night.
struct AIJob: Sendable {
    let candidate: PushCandidate
    var jobId: String
    /// The files sent (nil for a job picked up after a relaunch).
    var prepared: ComposeSession.Prepared?
    var photoIds: [String: String]
    var place: String?
    let startedAt: Date
    /// Waiting counted against the 6-minute budget.
    var waited: TimeInterval
    var resubmitted: Bool
}

/// What a night does next.
enum DayStep {
    case keep, deferred, exhausted
    case cached(PushCandidate, memory: TriggerMemory, photoIds: [String: String])
    case ask(PushCandidate)
}

/// One submit's inputs and answer.
struct AIAsk: Sendable {
    let day: Int
    let candidate: PushCandidate
    let picks: [Preselected]
    /// A job of the same photos submitted under an hour ago (after a relaunch).
    let resume: OutstandingJob?
    let prepared: ComposeSession.Prepared?
    let waited: TimeInterval
    let resubmitted: Bool
}

enum AISent: Sendable {
    case job(AIJob, submitted: Bool)
    case fake(TriggerMemory, photoIds: [String: String], place: String?)
    case unreadable
    case failed(String)
}

/// What one run plans with, fixed for the run.
struct RunContext: Sendable {
    let ranking: TriggerRanking
    /// Group key -> its preselected photos.
    let picks: [String: [Preselected]]
    let calendar: Calendar
    let generation: Int
    let candidateCount: Int
    let preferences: PushPreferences
    let pushedDays: Set<String>
    let firstSlot: Date
}

/// The run in progress: each night's state, what the AI said, the log rows.
struct RunWork: Sendable {
    var days: [DayWork] = []
    var verdicts: [String: AIVerdict] = [:]
    var outcomes: [ScheduleRun.GroupOutcome] = []
    var aiSent = 0
    /// Active pushes outside the seven nights: their group and day are taken.
    var orphans: [(group: String, day: String)] = []
    /// Batch polls in a row that found no connection.
    var transportFailures = 0
    /// Nights whose job was out when the background time ran out.
    var leftDays: Set<Int> = []
    /// Groups whose trip to the AI failed this run: not sent again for another night.
    var failedGroups: Set<String> = []
}

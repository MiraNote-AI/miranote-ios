import Foundation

/// A backend job submitted and not yet collected.
public struct OutstandingJob: Codable, Equatable, Sendable {
    public var jobId: String
    public var submittedAt: Date
    public var slotDay: String

    public init(jobId: String, submittedAt: Date, slotDay: String) {
        self.jobId = jobId
        self.submittedAt = submittedAt
        self.slotDay = slotDay
    }
}

/// What the scheduler remembers between runs.
public struct SchedulerState: Codable, Equatable, Sendable {
    public var lastFullRunAt: Date?
    public var lastRunLeftDaysUnfilled: Bool
    public var timeZoneId: String?
    public var threshold: ThresholdResult?
    public var thresholdComputedAt: Date?
    /// AI cache key -> job.
    public var outstanding: [String: OutstandingJob]

    /// T is recomputed when older than this.
    static let thresholdMaxAge: TimeInterval = 7 * 86_400

    public init(lastFullRunAt: Date? = nil, lastRunLeftDaysUnfilled: Bool = false, timeZoneId: String? = nil,
                threshold: ThresholdResult? = nil, thresholdComputedAt: Date? = nil,
                outstanding: [String: OutstandingJob] = [:]) {
        self.lastFullRunAt = lastFullRunAt
        self.lastRunLeftDaysUnfilled = lastRunLeftDaysUnfilled
        self.timeZoneId = timeZoneId
        self.threshold = threshold
        self.thresholdComputedAt = thresholdComputedAt
        self.outstanding = outstanding
    }

    /// No T yet, or T is 7 days old or more.
    public func needsThreshold(now: Date) -> Bool {
        guard threshold != nil, let computed = thresholdComputedAt else { return true }
        return now.timeIntervalSince(computed) >= Self.thresholdMaxAge
    }
}

/// The scheduler state as one JSON file. A missing or damaged file loads as empty.
public struct SchedulerStateStore: Sendable {
    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `Application Support/PhotoTrigger/scheduler-state.json`.
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("scheduler-state.json")
    }

    public func load() -> SchedulerState {
        guard let data = try? Data(contentsOf: file),
              let value = try? TriggerMemory.decoder.decode(SchedulerState.self, from: data) else {
            return SchedulerState()
        }
        return value
    }

    public func save(_ state: SchedulerState) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try TriggerMemory.encoder.encode(state).write(to: file, options: .atomic)
    }

    public func update(_ change: (inout SchedulerState) -> Void) throws {
        var value = load()
        change(&value)
        try save(value)
    }
}

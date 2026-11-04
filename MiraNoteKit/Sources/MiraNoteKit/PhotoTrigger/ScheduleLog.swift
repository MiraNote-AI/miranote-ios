import Foundation

/// One scheduling run, for the debug page and the copied report.
public struct ScheduleRun: Codable, Equatable, Sendable {
    /// What one group's trip through the AI came to.
    public struct GroupOutcome: Codable, Equatable, Sendable {
        public enum Outcome: String, Codable, Sendable {
            case cachedOk, cachedRejected, ok, rejected, error, left
        }

        public var slotDay: String
        public var groupKey: String
        public var belongsTo: String
        public var outcome: Outcome
        public var seconds: Double
        public var message: String?

        public init(slotDay: String, groupKey: String, belongsTo: String, outcome: Outcome, seconds: Double,
                    message: String? = nil) {
            self.slotDay = slotDay
            self.groupKey = groupKey
            self.belongsTo = belongsTo
            self.outcome = outcome
            self.seconds = seconds
            self.message = message
        }
    }

    public var startedAt: Date
    public var finishedAt: Date
    /// `foreground`, `menu`, `replan`, `timeZone`, `clearAll`.
    public var trigger: String
    public var fragments: Int
    public var candidates: Int
    public var aiSent: Int
    public var groups: [GroupOutcome]
    public var scheduledDays: [String]
    /// Slot day -> why nothing was scheduled: `noCandidate`, `aiError`,
    /// `leftBeforeResult`, `notificationsOff`, `photosDenied`.
    public var emptyDays: [String: String]
    public var error: String?

    public init(startedAt: Date, finishedAt: Date, trigger: String, fragments: Int = 0, candidates: Int = 0,
                aiSent: Int = 0, groups: [GroupOutcome] = [], scheduledDays: [String] = [],
                emptyDays: [String: String] = [:], error: String? = nil) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.trigger = trigger
        self.fragments = fragments
        self.candidates = candidates
        self.aiSent = aiSent
        self.groups = groups
        self.scheduledDays = scheduledDays
        self.emptyDays = emptyDays
        self.error = error
    }

    /// A run error, or a group that failed.
    public var hasError: Bool {
        error != nil || groups.contains { $0.outcome == .error }
    }
}

/// Counts that outlive single runs.
public struct ScheduleCounters: Codable, Equatable, Sendable {
    /// Days that ended unscheduled because the app left while the job was out.
    public var leftBeforeResult: Int

    public init(leftBeforeResult: Int = 0) {
        self.leftBeforeResult = leftBeforeResult
    }
}

/// The last 20 runs and the counters, as one JSON file. A missing or
/// damaged file loads as empty.
public struct ScheduleLogStore: Sendable {
    static let keepRuns = 20

    private struct Contents: Codable {
        var runs: [ScheduleRun] = []
        var counters = ScheduleCounters()
    }

    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `Application Support/PhotoTrigger/schedule-log.json`.
    public static var defaultFile: URL {
        PhotoTriggerPaths.root.appendingPathComponent("schedule-log.json")
    }

    /// Newest first, at most 20.
    public func runs() -> [ScheduleRun] {
        load().runs
    }

    public func append(_ run: ScheduleRun) throws {
        var contents = load()
        contents.runs = Array(([run] + contents.runs).prefix(Self.keepRuns))
        try save(contents)
    }

    public func counters() -> ScheduleCounters {
        load().counters
    }

    public func bumpLeftBeforeResult(by amount: Int) throws {
        var contents = load()
        contents.counters.leftBeforeResult += amount
        try save(contents)
    }

    public func clear() throws {
        try save(Contents())
    }

    private func load() -> Contents {
        guard let data = try? Data(contentsOf: file),
              let value = try? TriggerMemory.decoder.decode(Contents.self, from: data) else { return Contents() }
        return value
    }

    private func save(_ contents: Contents) throws {
        try PhotoTriggerPaths.prepare(file.deletingLastPathComponent())
        try TriggerMemory.encoder.encode(contents).write(to: file, options: .atomic)
    }
}

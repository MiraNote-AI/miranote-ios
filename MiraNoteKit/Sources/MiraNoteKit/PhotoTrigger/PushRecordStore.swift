import Foundation

/// Everything a push needs when it is tapped, saved before it is
/// scheduled: the notification itself carries only `pushId` (handoff 7.6).
public struct PushRecord: Codable, Equatable, Sendable {
    /// New for every push (the same group may be pushed again).
    public let pushId: String
    public let memory: TriggerMemory
    /// "P1" -> PhotoKit localIdentifier.
    public let photoIds: [String: String]
    public let createdAt: Date
    /// 1-based rank of the group when it was pushed.
    public let rank: Int
    public let score: Double
    /// The push bucket's Chinese name.
    public let bucket: String

    public init(pushId: String, memory: TriggerMemory, photoIds: [String: String], createdAt: Date, rank: Int,
                score: Double, bucket: String) {
        self.pushId = pushId
        self.memory = memory
        self.photoIds = photoIds
        self.createdAt = createdAt
        self.rank = rank
        self.score = score
        self.bucket = bucket
    }
}

/// One line of the push ledger (phase 2: "a pushed day is not pushed
/// again", cooldowns, feedback). The shape is kept now; nothing writes it
/// in phase 1.
public struct PushLedgerEntry: Codable, Equatable, Sendable {
    public let pushId: String
    public let groupKey: String
    public let belongsTo: String
    public let bucket: String
    public let deliverAt: Date
    public let opened: Bool
    public let madePage: Bool

    public init(pushId: String, groupKey: String, belongsTo: String, bucket: String, deliverAt: Date, opened: Bool,
                madePage: Bool) {
        self.pushId = pushId
        self.groupKey = groupKey
        self.belongsTo = belongsTo
        self.bucket = bucket
        self.deliverAt = deliverAt
        self.opened = opened
        self.madePage = madePage
    }
}

/// Where a tapped push finds its memory: by the id the notification
/// carries. Never regroups and never calls the backend (handoff 7.6).
public protocol TriggerMemorySource: Sendable {
    func record(_ pushId: String) -> PushRecord?
    /// The newest record (debug and UI tests).
    func latest() -> PushRecord?
}

/// Push records, one JSON file per `pushId` under Application Support
/// (`PhotoTrigger/pushes/`). Local only.
public struct PushRecordStore: TriggerMemorySource {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        PhotoTriggerPaths.root.appendingPathComponent("pushes", isDirectory: true)
    }

    public func save(_ record: PushRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TriggerMemory.encoder.encode(record).write(to: file(record.pushId), options: .atomic)
    }

    public func load(_ pushId: String) -> PushRecord? {
        guard let data = try? Data(contentsOf: file(pushId)) else { return nil }
        return try? TriggerMemory.decoder.decode(PushRecord.self, from: data)
    }

    public func record(_ pushId: String) -> PushRecord? {
        load(pushId)
    }

    public func latest() -> PushRecord? {
        all().first
    }

    /// Every record, newest first.
    public func all() -> [PushRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { load(String($0.dropLast(5))) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The question ids of the last `limit` pushes, newest first: the
    /// backend avoids them (handoff 5.1 `recent_question_ids`).
    public func recentQuestionIds(limit: Int = 5) -> [String] {
        all().prefix(limit).map(\.memory.ending.questionId).filter { !$0.isEmpty }
    }

    private func file(_ pushId: String) -> URL {
        // UUID strings are file-name safe; anything else is reduced to be.
        let safe = pushId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent("\(safe).json")
    }
}

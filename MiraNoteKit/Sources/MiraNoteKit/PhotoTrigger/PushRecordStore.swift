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
    /// The push bucket's id; nil in records saved before phase 2.
    public let bucketId: PushBucket?
    /// The belongs-to day, "yyyy-MM-dd"; nil in older records.
    public let belongsTo: String?
    /// Pushed from a debug press; nil in older records.
    public let isDebug: Bool?

    public init(pushId: String, memory: TriggerMemory, photoIds: [String: String], createdAt: Date, rank: Int,
                score: Double, bucket: String, bucketId: PushBucket? = nil, belongsTo: String? = nil,
                isDebug: Bool? = nil) {
        self.pushId = pushId
        self.memory = memory
        self.photoIds = photoIds
        self.createdAt = createdAt
        self.rank = rank
        self.score = score
        self.bucket = bucket
        self.bucketId = bucketId
        self.belongsTo = belongsTo
        self.isDebug = isDebug
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
/// (`PhotoTrigger/pushes/`). Local only: excluded from backup.
public struct PushRecordStore: TriggerMemorySource {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        PhotoTriggerPaths.root.appendingPathComponent("pushes", isDirectory: true)
    }

    public func save(_ record: PushRecord) throws {
        try PhotoTriggerPaths.prepare(directory)
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

    /// Deletes one record; an unknown id changes nothing.
    public func remove(_ pushId: String) throws {
        let url = file(pushId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Deletes every record.
    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func file(_ pushId: String) -> URL {
        // UUID strings are file-name safe; anything else is reduced to be.
        let safe = pushId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent("\(safe).json")
    }
}

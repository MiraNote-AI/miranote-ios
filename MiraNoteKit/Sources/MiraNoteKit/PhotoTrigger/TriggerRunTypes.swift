import Foundation

// MARK: - What a run needs from the app

public enum PhotoAccess: Equatable, Sendable {
    case full, limited, denied
}

/// PhotoKit, as far as a run needs it.
public protocol PhotoLibraryReading: Sendable {
    /// Asks the first time; limited access is access.
    func requestAccess() async -> PhotoAccess
    /// Image assets taken at or after `date`: metadata only, no pixels.
    func assets(since date: Date) async -> [LibraryAsset]
    /// The photo's bytes for upload (any size from about 1000 px), or nil.
    func uploadData(for id: String) async -> Data?
}

/// On-device Vision.
public protocol PhotoAnalyzing: Sendable {
    /// Nil when the photo cannot be read (it is tried again next time).
    func analyze(_ id: String) async -> PhotoAnalysis?
    /// FeaturePrint distance between two archived prints.
    func distance(_ first: Data, _ second: Data) -> Float?
}

/// Apple's reverse geocoder.
public protocol PlaceNaming: Sendable {
    func name(for point: GeoPoint) async -> String?
}

/// Local notifications.
public protocol TriggerNotifying: Sendable {
    /// Asks the first time; false when notifications are off.
    func requestPermission() async -> Bool
    /// Schedules the push for `record` (saved already) 10 s out.
    func schedule(_ record: PushRecord) async -> Bool
}

// MARK: - Progress

public enum TriggerFailure: Equatable, Sendable {
    case backendUnreachable
    case aiTimeout
    case noFragment
    case notificationsOff
    case photosDenied
    /// 401: this build has no valid beta token.
    case unauthorized
    /// Any other refusal or error, with the backend's message.
    case backend(String)
}

/// What the debug entry shows under its buttons (handoff 7.5), in order.
public enum TriggerProgress: Equatable, Sendable {
    case preparing
    /// Only part of the library is shared: a note, the run goes on.
    case partialLibrary
    case analyzing(done: Int, total: Int)
    /// "M.DD" date, the place when known, unique photos in the group.
    case askingAI(rank: Int, date: String, place: String?, count: Int)
    /// "Push next" ran past the last group and starts from the top.
    case wrapped
    case rejected(rank: Int, message: String, next: Int)
    case scheduled(rank: Int, score: Double)
    case allThreeFailed
    case failed(TriggerFailure)
}

/// A pushable fragment and its place in the ranking.
public struct RankedGroup: Equatable, Sendable {
    /// 1-based.
    public let rank: Int
    public let fragment: Fragment
    public let score: FragmentScore
}

/// Everything a run talks to, injectable for tests.
public struct TriggerDependencies: Sendable {
    public var library: PhotoLibraryReading
    public var analyzer: PhotoAnalyzing
    public var places: PlaceNaming
    public var client: ComposeClient
    public var notifier: TriggerNotifying
    public var analyses: AnalysisStore
    public var records: PushRecordStore
    public var calendar: Calendar
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (TimeInterval) async throws -> Void
    /// The fake-AI switch, read at each press.
    public var fakeAI: @Sendable () -> Bool
    /// zh-Hans catalog lookup for content (`TriggerContentKey`).
    public var zh: @Sendable (String) -> String

    public init(
        library: PhotoLibraryReading, analyzer: PhotoAnalyzing, places: PlaceNaming, client: ComposeClient,
        notifier: TriggerNotifying, analyses: AnalysisStore, records: PushRecordStore, calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        fakeAI: @escaping @Sendable () -> Bool, zh: @escaping @Sendable (String) -> String
    ) {
        self.library = library
        self.analyzer = analyzer
        self.places = places
        self.client = client
        self.notifier = notifier
        self.analyses = analyses
        self.records = records
        self.calendar = calendar
        self.now = now
        self.sleep = sleep
        self.fakeAI = fakeAI
        self.zh = zh
    }
}

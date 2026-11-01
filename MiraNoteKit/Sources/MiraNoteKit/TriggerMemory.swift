import Foundation

/// One photo-trigger memory: a few photos from one outing, the push that
/// surfaces them, and the words on the ending page. This is the shape the
/// photo-collections backend returns (`memory` of a finished job, handoff
/// 5.2) and the shape the on-device fake AI builds; a push record keeps it
/// on disk until the push is tapped.
///
/// Fields added after v0 (`bucket`, `ending.detail`, `ending.questionId`,
/// `facts`, `generation`) decode with defaults when absent, so older JSON
/// keeps decoding.
public struct TriggerMemory: Codable, Equatable, Sendable {
    public struct Push: Codable, Equatable, Sendable {
        public let title: String
        public let body: String
        public let coverPhotoId: String

        public init(title: String, body: String, coverPhotoId: String) {
            self.title = title
            self.body = body
            self.coverPhotoId = coverPhotoId
        }
    }

    public struct Photo: Codable, Equatable, Sendable, Identifiable {
        /// "P1"...: the number the photo was sent under.
        public let id: String
        /// A bundled or stored file; nil for a library photo, which is read
        /// from PhotoKit by the push record's localIdentifier.
        public let file: String?
        public let takenAt: Date
        public let isPeak: Bool

        public init(id: String, file: String? = nil, takenAt: Date, isPeak: Bool) {
            self.id = id
            self.file = file
            self.takenAt = takenAt
            self.isPeak = isPeak
        }
    }

    public struct Story: Codable, Equatable, Sendable {
        public let firstFrameLabel: String
        public let photos: [Photo]

        public init(firstFrameLabel: String, photos: [Photo]) {
            self.firstFrameLabel = firstFrameLabel
            self.photos = photos
        }
    }

    public struct Ending: Codable, Equatable, Sendable {
        /// Date and place only ("10.18 . <place>"), never a time.
        public let factLine: String
        /// The detail line; "" when there is none (no row on the ending).
        public let detail: String
        public let question: String
        /// The question bank's id ("A1", "B1"...); "" when unknown.
        public let questionId: String
        public let ctaLabel: String

        public init(factLine: String, detail: String, question: String, questionId: String, ctaLabel: String) {
            self.factLine = factLine
            self.detail = detail
            self.question = question
            self.questionId = questionId
            self.ctaLabel = ctaLabel
        }

        private enum CodingKeys: String, CodingKey {
            case factLine, detail, question, questionId, ctaLabel
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            factLine = try container.decode(String.self, forKey: .factLine)
            detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
            question = try container.decode(String.self, forKey: .question)
            questionId = try container.decodeIfPresent(String.self, forKey: .questionId) ?? ""
            ctaLabel = try container.decode(String.self, forKey: .ctaLabel)
        }
    }

    /// How the words were made, for the debug log and later analysis.
    public struct Generation: Codable, Equatable, Sendable {
        public let bodySource: String
        public let questionSource: String
        public let model: String
        public let costCny: Double
        public let latencyMs: Int

        public init(bodySource: String, questionSource: String, model: String, costCny: Double, latencyMs: Int) {
            self.bodySource = bodySource
            self.questionSource = questionSource
            self.model = model
            self.costCny = costCny
            self.latencyMs = latencyMs
        }

        private enum CodingKeys: String, CodingKey {
            case bodySource, questionSource, model, costCny, latencyMs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bodySource = try container.decodeIfPresent(String.self, forKey: .bodySource) ?? ""
            questionSource = try container.decodeIfPresent(String.self, forKey: .questionSource) ?? ""
            model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
            costCny = try container.decodeIfPresent(Double.self, forKey: .costCny) ?? 0
            latencyMs = try container.decodeIfPresent(Int.self, forKey: .latencyMs) ?? 0
        }
    }

    public let id: String
    public let mode: String
    public let date: String
    public let daypart: Daypart
    /// The push bucket's Chinese name ("fewer like this" names it); "" when
    /// unknown.
    public let bucket: String
    public let push: Push
    public let story: Story
    public let ending: Ending
    /// One Chinese sentence per selected photo id: it becomes the canvas
    /// photo's `ImageRef.summary`, so the editor does not describe it again.
    public let facts: [String: String]
    public let generation: Generation?

    public init(
        id: String,
        mode: String = "life_fragment",
        date: String,
        daypart: Daypart,
        bucket: String = "",
        push: Push,
        story: Story,
        ending: Ending,
        facts: [String: String] = [:],
        generation: Generation? = nil
    ) {
        self.id = id
        self.mode = mode
        self.date = date
        self.daypart = daypart
        self.bucket = bucket
        self.push = push
        self.story = story
        self.ending = ending
        self.facts = facts
        self.generation = generation
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, date, daypart, bucket, push, story, ending, facts, generation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "life_fragment"
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        daypart = try container.decode(Daypart.self, forKey: .daypart)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        push = try container.decode(Push.self, forKey: .push)
        story = try container.decode(Story.self, forKey: .story)
        ending = try container.decode(Ending.self, forKey: .ending)
        facts = try container.decodeIfPresent([String: String].self, forKey: .facts) ?? [:]
        generation = try container.decodeIfPresent(Generation.self, forKey: .generation)
    }

    /// The photo the story opens on and the ending grid leads with: the one
    /// marked `isPeak`, or the earliest when none is.
    public var peak: Photo? {
        story.photos.first(where: \.isPeak) ?? story.photos.min { $0.takenAt < $1.takenAt }
    }

    /// The order the story plays in: the peak first (flagged `isPeak`, even
    /// when the file flagged none), then every other photo by `takenAt`.
    public var storyPhotos: [Photo] {
        guard let peak else { return [] }
        let others = story.photos
            .filter { $0.id != peak.id }
            .sorted { $0.takenAt < $1.takenAt }
            .map { Photo(id: $0.id, file: $0.file, takenAt: $0.takenAt, isPeak: false) }
        return [Photo(id: peak.id, file: peak.file, takenAt: peak.takenAt, isPeak: true)] + others
    }

    /// The push's attachment, falling back to the peak photo.
    public var coverPhoto: Photo? {
        story.photos.first { $0.id == push.coverPhotoId } ?? peak
    }

    /// The memory with only the photos still in the library (`present`
    /// holds their ids). Nil when fewer than three remain: the story is not
    /// worth playing (handoff 7.6, acceptance D4). A missing peak is
    /// replaced by the earliest remaining photo, which then opens the story
    /// and takes the big cell.
    public func replacingMissing(present: Set<String>) -> TriggerMemory? {
        let remaining = story.photos.filter { present.contains($0.id) }
        guard remaining.count >= 3 else { return nil }
        let peakID = remaining.first(where: \.isPeak)?.id
            ?? remaining.min { $0.takenAt < $1.takenAt }?.id
        let photos = remaining.map {
            Photo(id: $0.id, file: $0.file, takenAt: $0.takenAt, isPeak: $0.id == peakID)
        }
        return TriggerMemory(
            id: id, mode: mode, date: date, daypart: daypart, bucket: bucket, push: push,
            story: Story(firstFrameLabel: story.firstFrameLabel, photos: photos),
            ending: ending, facts: facts, generation: generation
        )
    }

    /// Seconds a photo stays on screen in the story: the peak lingers.
    public static func dwell(for photo: Photo) -> TimeInterval {
        photo.isPeak ? 3 : 2
    }

    /// Decodes the JSON the backend speaks: ISO 8601 timestamps with an
    /// offset.
    public static func decode(_ data: Data) throws -> TriggerMemory {
        try decoder.decode(TriggerMemory.self, from: data)
    }

    /// The decoder for this shape and anything that embeds it.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The matching encoder (push records on disk).
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// The part of the day a set of photos was taken in, which names the ending's
/// button ("keep this afternoon"). `init(hour:)` is the rule the backend
/// follows, by the peak photo's hour.
public enum Daypart: String, Codable, Sendable, CaseIterable {
    case morning, noon, afternoon, evening, night

    /// 5-11 morning, 11-14 noon, 14-17 afternoon, 17-19 evening, and 19 on
    /// (through the small hours) night.
    public init(hour: Int) {
        switch hour {
        case 5..<11: self = .morning
        case 11..<14: self = .noon
        case 14..<17: self = .afternoon
        case 17..<19: self = .evening
        default: self = .night
        }
    }
}

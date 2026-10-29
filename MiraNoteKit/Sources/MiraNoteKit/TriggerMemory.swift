import Foundation

/// One photo-trigger memory: a few photos from one outing, the push that
/// surfaces them, and the words on the ending page. This is the shape the
/// backend will return; v0 reads it from a bundled demo file instead
/// (`DemoMemoryLoader`).
public struct TriggerMemory: Codable, Equatable, Sendable {
    public struct Push: Codable, Equatable, Sendable {
        public let title: String
        public let body: String
        public let coverPhotoId: String
    }

    public struct Photo: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let file: String
        public let takenAt: Date
        public let isPeak: Bool
    }

    public struct Story: Codable, Equatable, Sendable {
        public let firstFrameLabel: String
        public let photos: [Photo]
    }

    public struct Ending: Codable, Equatable, Sendable {
        /// Date and place only ("10.18 . <place>"), never a time.
        public let factLine: String
        public let question: String
        public let ctaLabel: String
    }

    public let id: String
    public let mode: String
    public let date: String
    public let daypart: Daypart
    public let push: Push
    public let story: Story
    public let ending: Ending

    /// The order the story plays in: every ordinary photo by `takenAt`, then
    /// the peak photo last, whatever order the file lists them in.
    public var storyPhotos: [Photo] {
        let ordinary = story.photos.filter { !$0.isPeak }.sorted { $0.takenAt < $1.takenAt }
        return ordinary + story.photos.filter(\.isPeak)
    }

    /// The photo the story ends on and the ending grid leads with: the one
    /// marked `isPeak`, or the last photo when none is.
    public var peak: Photo? {
        storyPhotos.last
    }

    /// The push's attachment, falling back to the peak photo.
    public var coverPhoto: Photo? {
        story.photos.first { $0.id == push.coverPhotoId } ?? peak
    }

    /// Seconds a photo stays on screen in the story: the peak lingers.
    public static func dwell(for photo: Photo) -> TimeInterval {
        photo.isPeak ? 3 : 2
    }

    /// Decodes the JSON the backend (and the demo file) speaks: ISO 8601
    /// timestamps with an offset.
    public static func decode(_ data: Data) throws -> TriggerMemory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TriggerMemory.self, from: data)
    }
}

/// The part of the day a set of photos was taken in, which names the ending's
/// button ("keep this afternoon"). v0 takes it from the JSON; `init(hour:)` is
/// the rule the backend follows.
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

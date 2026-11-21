import CryptoKit
import Foundation

/// The `meta` field of a repeat theme's `POST /collections/compose`
/// (backend Task 3), encoded snake_case. No coordinates: the theme goes by
/// its name and its `where` facts, the photos by time and labels.
public struct RepeatComposeMeta: Encodable, Equatable, Sendable {
    /// `mode` of a repeat meta, memory, push record and ledger row.
    public static let mode = "repeat"

    public struct Theme: Encodable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// May be empty.
        public let noun: String
        /// May be empty.
        public let samePart: String
        /// Sent as null when the theme has none (a big theme).
        public let `where`: WhereFacts?

        public init(id: String, name: String, noun: String, samePart: String, where: WhereFacts?) {
            self.id = id
            self.name = name
            self.noun = noun
            self.samePart = samePart
            self.where = `where`
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, noun
            case samePart = "same_part"
            case `where`
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(noun, forKey: .noun)
            try container.encode(samePart, forKey: .samePart)
            try container.encode(`where`, forKey: .where)
        }
    }

    public struct Photo: Encodable, Equatable, Sendable {
        /// "P1"...: the photo's number in this request and in the memory.
        public let id: String
        /// ISO 8601 with the local offset.
        public let takenAt: String
        /// Broad category names (`BroadCategory.rawValue`), as a life fragment's.
        public let labels: [String]
        public let faces: Int
        public let favorite: Bool
        public let edited: Bool

        public init(id: String, takenAt: String, labels: [String], faces: Int, favorite: Bool, edited: Bool) {
            self.id = id
            self.takenAt = takenAt
            self.labels = labels
            self.faces = faces
            self.favorite = favorite
            self.edited = edited
        }

        private enum CodingKeys: String, CodingKey {
            case id, labels, faces, favorite, edited
            case takenAt = "taken_at"
        }
    }

    public let mode = Self.mode
    public let groupKey: String
    /// The IANA time zone the times are local to.
    public let tz: String
    public let theme: Theme
    /// As a life fragment's (`QuestionPicker.nearbyTypes`); always sent.
    public let recentQuestionTypes: [String]
    /// 5-9, one a day, by date.
    public let photos: [Photo]

    public init(groupKey: String, tz: String, theme: Theme, recentQuestionTypes: [String], photos: [Photo]) {
        self.groupKey = groupKey
        self.tz = tz
        self.theme = theme
        self.recentQuestionTypes = recentQuestionTypes
        self.photos = photos
    }

    private enum CodingKeys: String, CodingKey {
        case mode, tz, theme, photos
        case groupKey = "group_key"
        case recentQuestionTypes = "recent_question_types"
    }

    /// The JSON sent as the `meta` field.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    // swiftlint:disable function_parameter_count
    /// The meta for `photoIds` of `theme` (localIdentifiers, any order),
    /// numbering them P1... in time order, and the number ->
    /// localIdentifier map the push record keeps. A photo without a theme
    /// record is left out.
    public static func build(theme: ThemeRow, photoIds: [String], photos: [String: ThemePhoto],
                             library: [String: LibraryAsset], recentQuestionTypes: [String],
                             calendar: Calendar) -> (meta: RepeatComposeMeta, photoIds: [String: String]) {
        let ordered = photoIds.compactMap { photos[$0] }
            .sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
        let iso = ISO8601DateFormatter()
        iso.timeZone = calendar.timeZone
        iso.formatOptions = [.withInternetDateTime]
        var numbers: [String: String] = [:]
        let sent = ordered.enumerated().map { index, photo -> Photo in
            let number = "P\(index + 1)"
            numbers[number] = photo.id
            let broad = BroadCategory.from(labels: photo.labels.map(\.id))
            return Photo(id: number, takenAt: iso.string(from: photo.takenAt),
                         labels: BroadCategory.allCases.filter(broad.contains).map(\.rawValue), faces: photo.faces,
                         favorite: library[photo.id]?.isFavorite ?? false, edited: library[photo.id]?.isEdited ?? false)
        }
        let meta = RepeatComposeMeta(
            groupKey: groupKey(themeId: theme.id, photoIds: ordered.map(\.id)), tz: calendar.timeZone.identifier,
            theme: Theme(id: theme.id, name: theme.name, noun: theme.noun, samePart: theme.samePart,
                         where: theme.where),
            recentQuestionTypes: recentQuestionTypes, photos: sent)
        return (meta, numbers)
    }
    // swiftlint:enable function_parameter_count

    /// "repeat_<first 8 hex of SHA-256 of the theme id and the sorted photo ids>".
    static func groupKey(themeId: String, photoIds: [String]) -> String {
        let joined = ([themeId] + photoIds.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        return "repeat_\(digest.prefix(8))"
    }
}

extension RepeatComposeMeta: ComposeRequest {
    var photoNumbers: [String] { photos.map(\.id) }
    static var minimumPhotos: Int { PushPhotoPicker.minPhotos }

    func keeping(_ read: Set<String>) -> (meta: RepeatComposeMeta, numbers: [String: String]) {
        var numbers: [String: String] = [:]
        var kept: [Photo] = []
        for photo in photos where read.contains(photo.id) {
            let number = "P\(kept.count + 1)"
            numbers[number] = photo.id
            kept.append(Photo(id: number, takenAt: photo.takenAt, labels: photo.labels, faces: photo.faces,
                              favorite: photo.favorite, edited: photo.edited))
        }
        return (RepeatComposeMeta(groupKey: groupKey, tz: tz, theme: theme, recentQuestionTypes: recentQuestionTypes,
                                  photos: kept), numbers)
    }
}

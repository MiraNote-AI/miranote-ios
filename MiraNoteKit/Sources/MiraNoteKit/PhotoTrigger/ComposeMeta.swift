import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The `meta` field of `POST /collections/compose` (handoff 5.1), encoded
/// snake_case. It carries no coordinates: the place goes by name only.
public struct ComposeMeta: Codable, Equatable, Sendable {
    public struct Photo: Codable, Equatable, Sendable {
        /// "P1"...: the photo's number in this request and in the memory.
        public let id: String
        /// ISO 8601 with the local offset.
        public let takenAt: String
        /// Broad category names (`BroadCategory.rawValue`).
        public let labels: [String]
        public let faces: Int
        public let favorite: Bool
        public let edited: Bool
        /// Photos this one stands for, itself included.
        public let represents: Int

        public init(id: String, takenAt: String, labels: [String], faces: Int, favorite: Bool, edited: Bool,
                    represents: Int) {
            self.id = id
            self.takenAt = takenAt
            self.labels = labels
            self.faces = faces
            self.favorite = favorite
            self.edited = edited
            self.represents = represents
        }

        private enum CodingKeys: String, CodingKey {
            case id, labels, faces, favorite, edited, represents
            case takenAt = "taken_at"
        }
    }

    public let groupKey: String
    /// The belongs-to day, "yyyy-MM-dd".
    public let date: String
    /// 1 Monday ... 7 Sunday.
    public let weekday: Int
    /// "HH:mm", local.
    public let startTime: String
    public let endTime: String
    /// Apple's name for the place, in Chinese; nil (sent as null) unknown.
    public let place: String?
    /// Every photo of the fragment, duplicates included.
    public let rawCount: Int
    /// Whether every photo not sent is represented by one that is.
    public let coversAll: Bool
    public let recentQuestionIds: [String]
    public let photos: [Photo]

    public init(groupKey: String, date: String, weekday: Int, startTime: String, endTime: String, place: String?,
                rawCount: Int, coversAll: Bool, recentQuestionIds: [String], photos: [Photo]) {
        self.groupKey = groupKey
        self.date = date
        self.weekday = weekday
        self.startTime = startTime
        self.endTime = endTime
        self.place = place
        self.rawCount = rawCount
        self.coversAll = coversAll
        self.recentQuestionIds = recentQuestionIds
        self.photos = photos
    }

    private enum CodingKeys: String, CodingKey {
        case date, weekday, place, photos
        case groupKey = "group_key"
        case startTime = "start_time"
        case endTime = "end_time"
        case rawCount = "raw_count"
        case coversAll = "covers_all"
        case recentQuestionIds = "recent_question_ids"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupKey, forKey: .groupKey)
        try container.encode(date, forKey: .date)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        // An unknown place is an explicit null, as the contract says.
        try container.encode(place, forKey: .place)
        try container.encode(rawCount, forKey: .rawCount)
        try container.encode(coversAll, forKey: .coversAll)
        try container.encode(recentQuestionIds, forKey: .recentQuestionIds)
        try container.encode(photos, forKey: .photos)
    }

    /// The JSON string sent as the `meta` field.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    // swiftlint:disable function_parameter_count
    /// The meta for `picks` of `fragment`, numbering them P1... in time
    /// order, and the number -> localIdentifier map the push record keeps.
    public static func build(
        fragment: Fragment, picks: [Preselected], analyses: [String: PhotoAnalysis], library: [String: LibraryAsset],
        place: String?, recentQuestionIds: [String], calendar: Calendar
    ) -> (meta: ComposeMeta, photoIds: [String: String]) {
        let byID = Dictionary(fragment.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = picks.sorted { (byID[$0.id]?.takenAt ?? .distantPast) < (byID[$1.id]?.takenAt ?? .distantPast) }
        var photoIds: [String: String] = [:]
        let iso = ISO8601DateFormatter()
        iso.timeZone = calendar.timeZone
        iso.formatOptions = [.withInternetDateTime]
        let photos = ordered.enumerated().map { index, pick -> Photo in
            let number = "P\(index + 1)"
            photoIds[number] = pick.id
            let analysis = analyses[pick.id]
            let labels = BroadCategory.allCases.filter { analysis?.broad.contains($0) ?? false }.map(\.rawValue)
            return Photo(id: number, takenAt: iso.string(from: byID[pick.id]?.takenAt ?? fragment.start),
                         labels: labels, faces: analysis?.faces ?? 0,
                         favorite: library[pick.id]?.isFavorite ?? false, edited: library[pick.id]?.isEdited ?? false,
                         represents: pick.represents)
        }
        let sent = Set(picks.map(\.id))
        let coversAll = fragment.uniquePhotos.allSatisfy { sent.contains($0.id) }
        let meta = ComposeMeta(
            groupKey: groupKey(fragment), date: fragment.belongsTo, weekday: weekday(fragment.belongsTo),
            startTime: clock(fragment.start, calendar), endTime: clock(fragment.end, calendar), place: place,
            rawCount: fragment.photos.count, coversAll: coversAll, recentQuestionIds: recentQuestionIds,
            photos: photos
        )
        return (meta, photoIds)
    }
    // swiftlint:enable function_parameter_count

    /// "<belongs-to day>_<first 8 hex of SHA-256 of the sorted photo ids>".
    public static func groupKey(_ fragment: Fragment) -> String {
        let joined = fragment.photos.map(\.id).sorted().joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(fragment.belongsTo)_\(digest.prefix(8))"
    }

    /// 1 Monday ... 7 Sunday for a "yyyy-MM-dd" day.
    static func weekday(_ day: String) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return 1 }
        // Calendar: 1 Sunday ... 7 Saturday.
        return (utc.component(.weekday, from: date) + 5) % 7 + 1
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// A photo as it is uploaded: a JPEG no larger than 768 px on its long
/// side, upright, with no metadata at all (no GPS, no capture date, no
/// camera) -- handoff 5.1 / acceptance B6.
public enum UploadImage {
    public static func prepare(_ imageData: Data, maxPixel: Int = 768) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        // A bare CGImage carries no properties; only the quality is set.
        let quality = [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        CGImageDestinationAddImage(destination, image, quality)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

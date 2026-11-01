import Foundation

/// A point on the earth. Coordinates stay on the phone: they go to Apple's
/// reverse geocoder and nowhere else (never into the compose meta).
public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    /// Great-circle distance (haversine), as the prototype measures it.
    public func km(to other: GeoPoint) -> Double {
        let radius = 6371.0088
        let lat1 = lat * .pi / 180
        let lat2 = other.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.lon - lon) * .pi / 180
        let half = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(half)))
    }

    /// The plain average of `points` (fine at the scale of one outing); nil
    /// when there are none.
    public static func center(of points: [GeoPoint]) -> GeoPoint? {
        guard !points.isEmpty else { return nil }
        let count = Double(points.count)
        return GeoPoint(lat: points.map(\.lat).reduce(0, +) / count,
                        lon: points.map(\.lon).reduce(0, +) / count)
    }
}

/// What the app knows about one library asset without looking at its
/// pixels: PhotoKit metadata only. (`LibraryAsset`, not `LibraryPhoto`: the
/// app target already has a `LibraryPhoto` for the Recents grid.)
public struct LibraryAsset: Equatable, Sendable {
    /// PhotoKit's localIdentifier.
    public let id: String
    /// Nil when PhotoKit has no creation date.
    public let takenAt: Date?
    public let location: GeoPoint?
    public let isFavorite: Bool
    /// `hasAdjustments`: edited in Photos.
    public let isEdited: Bool
    public let isScreenshot: Bool
    public let isHidden: Bool
    public let isVideo: Bool
    /// The original resource's file name (`PHAssetResource`), when known.
    public let originalFilename: String?
    public let burstId: String?

    public init(
        id: String, takenAt: Date?, location: GeoPoint?, isFavorite: Bool, isEdited: Bool,
        isScreenshot: Bool, isHidden: Bool, isVideo: Bool, originalFilename: String?, burstId: String?
    ) {
        self.id = id
        self.takenAt = takenAt
        self.location = location
        self.isFavorite = isFavorite
        self.isEdited = isEdited
        self.isScreenshot = isScreenshot
        self.isHidden = isHidden
        self.isVideo = isVideo
        self.originalFilename = originalFilename
        self.burstId = burstId
    }
}

/// Whether a photo came out of a camera, judged by its original file name
/// (handoff 7.1: never by reading EXIF, which may live in iCloud).
public enum CameraOrigin: Equatable, Sendable {
    case camera, notCamera, unknown

    private static let cameraPrefixes = ["img_", "dsc", "_dsc", "pxl_", "dji_"]
    private static let savedPrefixes = ["mmexport", "screenshot", "wx_", "weixin"]
    private static let uuidStem = try? NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        options: [.caseInsensitive]
    )

    /// Saved, downloaded and forwarded names win over camera names; a name
    /// that is neither is kept (`unknown`).
    public static func classify(filename: String?) -> CameraOrigin {
        guard let filename, !filename.isEmpty else { return .unknown }
        let name = filename.lowercased()
        let stem = (filename as NSString).deletingPathExtension
        if savedPrefixes.contains(where: name.hasPrefix) || name.contains("download") {
            return .notCamera
        }
        if let uuidStem,
           uuidStem.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) != nil {
            return .notCamera
        }
        if cameraPrefixes.contains(where: name.hasPrefix) { return .camera }
        return .unknown
    }
}

/// Grouping step 1: screenshots, hidden photos, videos and photos not from
/// a camera never take part. A camera photo without GPS stays (time alone
/// groups it). Utility/document photos are dropped later, once analysed.
public enum LibraryFilter {
    /// A capture date further ahead of the clock than this is a wrong clock,
    /// not a photo to rank (review focus 1).
    static let futureSlack: TimeInterval = 3600

    public static func eligible(_ asset: LibraryAsset, now: Date = .now) -> Bool {
        guard let takenAt = asset.takenAt, takenAt <= now.addingTimeInterval(futureSlack) else { return false }
        guard !asset.isScreenshot, !asset.isHidden, !asset.isVideo else { return false }
        return CameraOrigin.classify(filename: asset.originalFilename) != .notCamera
    }
}

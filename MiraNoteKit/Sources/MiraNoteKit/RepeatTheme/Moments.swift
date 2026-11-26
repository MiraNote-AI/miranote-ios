import Foundation

/// Photos taken close together in time that look alike: one occasion
/// (a burst, a few retakes). The repeat-theme finder counts a moment once,
/// not once per photo.
public struct Moment: Equatable, Sendable {
    /// The representative photo's id.
    public let id: String
    /// Every member photo id, in time order.
    public let photoIds: [String]
    /// The local calendar day, `yyyy-MM-dd`.
    public let day: String
    /// When the first member was taken.
    public let start: Date
    /// The representative's feature vector.
    public let vector: [Float]
    /// Per label, the highest confidence over the members.
    public let labels: [LabelScore]
    /// The representative's place, else the first member's that has one.
    public let location: GeoPoint?

    public init(id: String, photoIds: [String], day: String, start: Date, vector: [Float],
                labels: [LabelScore], location: GeoPoint?) {
        self.id = id
        self.photoIds = photoIds
        self.day = day
        self.start = start
        self.vector = vector
        self.labels = labels
        self.location = location
    }
}

/// Groups one day's photos into moments.
public enum MomentBuilder {
    /// A photo joins a moment only when it is closer than this (cosine
    /// distance) to the moment's first photo.
    public static let mergeDistance: Float = 0.2
    /// ...and at most this many seconds after the moment's first photo.
    public static let mergeSeconds: TimeInterval = 600

    /// The unit-length mean direction of `vectors`, summed in the given order
    /// in Double. Vectors whose length differs from the first are skipped;
    /// `[]` when there are none.
    public static func meanCenter(_ vectors: [[Float]]) -> [Float] {
        guard let length = vectors.first?.count else { return [] }
        var sum = [Double](repeating: 0, count: length)
        for vector in vectors where vector.count == length {
            for (offset, value) in vector.enumerated() { sum[offset] += Double(value) }
        }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return sum.map { Float(norm > 0 ? $0 / norm : $0) }
    }

    /// Moments sorted by start. Photos are only compared with the moment's
    /// FIRST photo, never with the previous one, so a slow drift cannot chain
    /// unlike shots into one moment. Days never mix. Groups whatever it is
    /// given: choosing theme photos is the caller's job.
    public static func build(_ photos: [ThemePhoto], calendar: Calendar) -> [Moment] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var byDay: [String: [ThemePhoto]] = [:]
        for photo in photos {
            byDay[formatter.string(from: photo.takenAt), default: []].append(photo)
        }

        var moments: [Moment] = []
        for (day, dayPhotos) in byDay {
            let sorted = dayPhotos.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
            var group: [ThemePhoto] = []
            var firstVector: [Float] = []
            for photo in sorted {
                let vector = photo.vector
                if let first = group.first,
                   photo.takenAt.timeIntervalSince(first.takenAt) <= mergeSeconds,
                   cosineDistance(firstVector, vector) < mergeDistance {
                    group.append(photo)
                } else {
                    if !group.isEmpty { moments.append(moment(group, day: day)) }
                    group = [photo]
                    firstVector = vector
                }
            }
            if !group.isEmpty { moments.append(moment(group, day: day)) }
        }
        return moments.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// `1 - cosine similarity`, normalising both vectors. A zero vector, or
    /// vectors of different lengths, are at distance 1. Summed in Double, as
    /// the tree and the desktop reference do.
    public static func cosineDistance(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count, !left.isEmpty else { return 1 }
        var dot = 0.0
        var leftLength = 0.0
        var rightLength = 0.0
        for index in left.indices {
            let leftValue = Double(left[index])
            let rightValue = Double(right[index])
            dot += leftValue * rightValue
            leftLength += leftValue * leftValue
            rightLength += rightValue * rightValue
        }
        let denominator = leftLength.squareRoot() * rightLength.squareRoot()
        guard denominator > 0 else { return 1 }
        return Float(1 - dot / denominator)
    }

    private static func moment(_ group: [ThemePhoto], day: String) -> Moment {
        // Highest aesthetics (nil is 0); the earliest wins a tie.
        var representative = group[0]
        for photo in group.dropFirst()
        where (photo.aesthetics ?? 0) > (representative.aesthetics ?? 0) {
            representative = photo
        }
        var best: [String: Float] = [:]
        for photo in group {
            for label in photo.labels {
                best[label.id] = max(best[label.id] ?? label.confidence, label.confidence)
            }
        }
        let labels = best.map { LabelScore(id: $0.key, confidence: $0.value) }
            .sorted { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.id < $1.id }
        return Moment(
            id: representative.id,
            photoIds: group.map(\.id),
            day: day,
            start: group[0].takenAt,
            vector: representative.vector,
            labels: labels,
            location: representative.location ?? group.lazy.compactMap(\.location).first)
    }
}

import Foundation

/// The recent photos sorted into the seven buckets, for checking the
/// mapping on a real phone (handoff 6.8 "export category report"): how
/// many photos each bucket has, a few examples, and the raw labels most
/// often seen in `other`. Photo ids only; thumbnails render on the phone.
public struct CategoryReport: Codable, Equatable, Sendable {
    public struct Bucket: Codable, Equatable, Sendable {
        public let bucket: PushBucket
        public let count: Int
        /// Up to six localIdentifiers, newest first.
        public let examples: [String]
    }

    public struct Label: Codable, Equatable, Sendable {
        public let label: String
        public let count: Int
    }

    public static let maxExamples = 6
    public static let maxLabels = 20

    /// All seven, in bucket order.
    public let buckets: [Bucket]
    /// The raw Vision labels of the photos in `other`, most frequent first.
    public let otherLabels: [Label]

    public static let empty = CategoryReport(buckets: [], otherLabels: [])

    /// - Parameter ids: the photos to sort, newest first.
    public static func make(ids: [String], analyses: [String: PhotoAnalysis]) -> CategoryReport {
        var byBucket: [PushBucket: [String]] = [:]
        var labels: [String: Int] = [:]
        for id in ids {
            guard let analysis = analyses[id] else { continue }
            let bucket = analysis.photoBucket
            byBucket[bucket, default: []].append(id)
            if bucket == .other {
                for label in Set(analysis.labels) { labels[label, default: 0] += 1 }
            }
        }
        let buckets = PushBucket.allCases.map { bucket in
            let all = byBucket[bucket] ?? []
            return Bucket(bucket: bucket, count: all.count, examples: Array(all.prefix(maxExamples)))
        }
        let top = labels.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(maxLabels).map { Label(label: $0.key, count: $0.value) }
        return CategoryReport(buckets: buckets, otherLabels: Array(top))
    }
}

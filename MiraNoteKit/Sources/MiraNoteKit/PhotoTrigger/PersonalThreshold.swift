import Foundation

/// T, the personal "a long time without a photo" (grouping step 4).
public struct ThresholdResult: Codable, Equatable, Sendable {
    public enum Fallback: String, Codable, Equatable, Sendable {
        /// Fewer than 50 gaps: 2 hours.
        case tooFewGaps
        /// The two piles' centres are under 10x apart: 2 hours.
        case weakSeparation
        /// The computed T lay outside 1-4 hours and was clamped.
        case clamped
    }

    public let value: TimeInterval
    public let fallback: Fallback?

    public init(value: TimeInterval, fallback: Fallback?) {
        self.value = value
        self.fallback = fallback
    }
}

/// Grouping step 4: the gaps between neighbouring photos of the last 90
/// days, split into a short and a long pile by 2-means on a log scale
/// (Loui & Savakis 2003); T is the geometric mean of the two centres.
public enum PersonalThreshold {
    public static let fallbackValue: TimeInterval = 7200
    public static let minimumGaps = 50
    public static let minimumSeparation: Double = 10
    public static let range: ClosedRange<TimeInterval> = 3600...14_400
    /// Gaps under half a minute count as half a minute (the reference
    /// script's floor), so bursts do not drag the short centre to zero.
    static let floor: TimeInterval = 30

    public static func compute(gaps: [TimeInterval]) -> ThresholdResult {
        guard gaps.count >= minimumGaps else { return ThresholdResult(value: fallbackValue, fallback: .tooFewGaps) }
        let logs = gaps.map { log(max($0, floor)) }
        guard var short = logs.min(), var long = logs.max(), long > short else {
            return ThresholdResult(value: fallbackValue, fallback: .weakSeparation)
        }
        for _ in 0..<100 {
            let near = logs.filter { abs($0 - short) <= abs($0 - long) }
            let far = logs.filter { abs($0 - short) > abs($0 - long) }
            guard !near.isEmpty, !far.isEmpty else { break }
            let next = (near.reduce(0, +) / Double(near.count), far.reduce(0, +) / Double(far.count))
            if next == (short, long) { break }
            (short, long) = next
        }
        guard exp(long) / exp(short) >= minimumSeparation else {
            return ThresholdResult(value: fallbackValue, fallback: .weakSeparation)
        }
        let raw = exp((short + long) / 2)
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return ThresholdResult(value: clamped, fallback: clamped == raw ? nil : .clamped)
    }

    /// The gaps between neighbouring capture times, in time order.
    public static func gaps(between dates: [Date]) -> [TimeInterval] {
        let sorted = dates.sorted()
        return zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
    }
}

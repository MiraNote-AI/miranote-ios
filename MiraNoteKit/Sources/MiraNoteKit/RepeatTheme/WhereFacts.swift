import Foundation

/// The "when and where" facts of one split group, in the backend's `Where`
/// shape (snake_case keys; a missing value is an explicit JSON null).
public struct WhereFacts: Codable, Equatable, Sendable {
    /// The most common daypart (`Daypart` raw value); nil for no moments.
    public let daypart: String?
    /// The dominant daypart's share of the group's moments.
    public let daypartShare: Double
    /// The 10th percentile of the moments' hours.
    public let hourFrom: Int?
    /// The 90th percentile of the moments' hours.
    public let hourTo: Int?
    /// `weekday` or `weekend` when at least 70% of the moments are, else `mixed`.
    public let weekpart: String
    /// How many different places the moments are at; nil when none has a location.
    public let places: Int?

    public init(daypart: String?, daypartShare: Double, hourFrom: Int?, hourTo: Int?,
                weekpart: String, places: Int?) {
        self.daypart = daypart
        self.daypartShare = daypartShare
        self.hourFrom = hourFrom
        self.hourTo = hourTo
        self.weekpart = weekpart
        self.places = places
    }

    private enum CodingKeys: String, CodingKey {
        case daypart
        case daypartShare = "daypart_share"
        case hourFrom = "hour_from"
        case hourTo = "hour_to"
        case weekpart
        case places
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        daypart = try container.decodeIfPresent(String.self, forKey: .daypart)
        daypartShare = try container.decode(Double.self, forKey: .daypartShare)
        hourFrom = try container.decodeIfPresent(Int.self, forKey: .hourFrom)
        hourTo = try container.decodeIfPresent(Int.self, forKey: .hourTo)
        weekpart = try container.decode(String.self, forKey: .weekpart)
        places = try container.decodeIfPresent(Int.self, forKey: .places)
    }

    /// Writes nil as null (the backend wants every key present).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(daypart, forKey: .daypart)
        try container.encode(daypartShare, forKey: .daypartShare)
        try container.encode(hourFrom, forKey: .hourFrom)
        try container.encode(hourTo, forKey: .hourTo)
        try container.encode(weekpart, forKey: .weekpart)
        try container.encode(places, forKey: .places)
    }
}

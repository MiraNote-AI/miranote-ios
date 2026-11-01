import Foundation

/// The 15 broad categories Vision's scene labels map onto (the prototype's
/// `BROAD_CATEGORIES`, with `sign` taken out of `document`: menus and signs
/// are worth keeping, handoff 7.1). The raw values are what the compose
/// meta sends as `labels`.
public enum BroadCategory: String, Codable, CaseIterable, Sendable {
    // swiftlint:disable identifier_name
    case people, animal, food_drink, tableware, plant, water, sky, built, street, vehicle
    case interior, event, recreation, art, document
    // swiftlint:enable identifier_name

    /// Vision label identifier -> category.
    static let labelMap: [String: BroadCategory] = {
        let table: [BroadCategory: [String]] = [
            .people: ["people", "adult", "child", "baby", "crowd"],
            .animal: ["animal", "canine", "feline", "bird", "mammal", "reptile"],
            .food_drink: ["food", "dessert", "drink", "fruit", "vegetable", "baked_goods"],
            .tableware: ["tableware", "utensil"],
            .plant: ["plant", "flower", "foliage", "tree", "grass", "shrub"],
            .water: ["water", "water_body", "shore"],
            .sky: ["sky", "sunset_sunrise", "night_sky", "cloudy", "blue_sky"],
            .built: ["building", "structure", "cityscape", "skyscraper"],
            .street: ["street", "road", "crosswalk", "parking_lot"],
            .vehicle: ["vehicle", "automobile", "conveyance"],
            .interior: ["interior_room", "furniture", "kitchen", "interior_shop", "restaurant"],
            .event: ["concert", "performance", "celebration", "music", "musical_instrument"],
            .recreation: ["recreation", "sport", "games", "toy"],
            .art: ["art", "decoration"],
            .document: ["document", "screenshot", "printed_page", "chart"]
        ]
        var map: [String: BroadCategory] = [:]
        for (category, labels) in table {
            for label in labels { map[label] = category }
        }
        return map
    }()

    /// The categories of a photo's high-precision labels.
    public static func from(labels: [String]) -> Set<BroadCategory> {
        Set(labels.compactMap { labelMap[$0] })
    }

    /// Preselection step 3's priority (1 first): people; animals; what you
    /// did; where and the mood; background. The rule's table does not list
    /// tableware: it ranks with the background (5). Documents never get
    /// this far.
    public var priority: Int {
        switch self {
        case .people: return 1
        case .animal: return 2
        case .event, .food_drink, .recreation: return 3
        case .sky, .water, .plant: return 4
        case .built, .street, .interior, .vehicle, .art, .tableware: return 5
        case .document: return 6
        }
    }

    /// The push bucket it counts toward (handoff 7.3).
    public var bucket: PushBucket {
        switch self {
        case .food_drink: return .food
        case .sky: return .sky
        case .plant, .water: return .nature
        case .animal: return .animals
        case .people: return .people
        case .built, .street, .vehicle: return .city
        case .interior, .tableware: return .home
        case .event, .recreation: return .events
        case .art, .document: return .other
        }
    }
}

/// The nine push buckets (handoff 7.3), in the handoff's order, which also
/// breaks ties. The Chinese name the user sees is content: the catalog's
/// zh-Hans entry for `catalogKey`.
public enum PushBucket: String, Codable, CaseIterable, Sendable {
    case food, sky, nature, animals, people, city, home, events, other

    /// The English catalog key whose zh-Hans value is the bucket's name.
    public var catalogKey: String {
        switch self {
        case .food: return "Food and drink"
        case .sky: return "Sky and sunsets"
        case .nature: return "Nature and plants"
        case .animals: return "Pets and animals"
        case .people: return "People and gatherings"
        case .city: return "City and buildings"
        case .home: return "Indoors and home"
        case .events: return "Events and shows"
        case .other: return "Other"
        }
    }

    /// The bucket most of the photos' categories map to; a tie goes to the
    /// bucket listed first. Nothing at all is `other`.
    public static func majority(of photos: [Set<BroadCategory>]) -> PushBucket {
        var counts: [PushBucket: Int] = [:]
        for categories in photos {
            for category in categories { counts[category.bucket, default: 0] += 1 }
        }
        guard let best = counts.values.max() else { return .other }
        return allCases.first { counts[$0] == best } ?? .other
    }
}

/// What on-device Vision found in one photo, kept on disk per photo so a
/// first run can be interrupted and resumed (handoff 7.1).
public struct PhotoAnalysis: Codable, Equatable, Sendable {
    /// PhotoKit's localIdentifier.
    public let id: String
    /// High-precision scene label identifiers.
    public let labels: [String]
    public let broad: Set<BroadCategory>
    public let faces: Int
    /// Apple's overall aesthetics score, -1...1; nil before iOS 18 (and on
    /// a simulator that cannot run it).
    public let aesthetics: Double?
    /// A receipt, document or the like: never grouped.
    public let isUtility: Bool
    /// An archived `VNFeaturePrintObservation` (near-duplicates, MMR).
    public let featurePrint: Data?

    public init(
        id: String, labels: [String], broad: Set<BroadCategory>, faces: Int,
        aesthetics: Double?, isUtility: Bool, featurePrint: Data?
    ) {
        self.id = id
        self.labels = labels
        self.broad = broad
        self.faces = faces
        self.aesthetics = aesthetics
        self.isUtility = isUtility
        self.featurePrint = featurePrint
    }

    /// Preselection's quality: the aesthetics score mapped to 0...1, or a
    /// neutral 0.5 without one.
    public var quality: Double {
        aesthetics.map { ($0 + 1) / 2 } ?? 0.5
    }
}

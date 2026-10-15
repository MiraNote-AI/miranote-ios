import SwiftUI

/// A preset sticker set bundled from the design handoff (screen 35): the
/// images live in the asset catalog under `Stickers/<folder>/<name>`.
struct StickerSet: Identifiable, Equatable {
    let id: String
    let title: String
    let folder: String
    /// In the designer's grid order.
    let names: [String]
    /// The set's tab icon.
    let hero: String

    func imageName(_ name: String) -> String { "Stickers/\(folder)/\(name)" }

    static let food = StickerSet(
        id: "food",
        title: "Food",
        folder: "Food",
        names: [
            "focaccia", "burrito", "hotpot", "martini", "coffee",
            "salad", "chocolate-cake", "donuts", "bibimbap", "sandwich",
            "pizza", "pasta", "sushi", "cream-soup", "iced-tea",
            "fried-chicken", "taco", "ramen", "steak", "quesadilla",
            "dumplings", "boba", "fries", "bakeries", "pudding",
            "burgers", "hotdog", "pancake", "ice-cream", "bao",
        ],
        hero: "focaccia"
    )

    /// The sets the panel offers after Make and Favorites. The handoff's
    /// other tab icons (heart, croissant, cat) have no sets behind them yet.
    static let all: [StickerSet] = [.food]
}

import UIKit

/// Owner-feedback options (2026-10-19), side by side for the owner to pick
/// from. One DEBUG launch argument chooses an option per item:
///
///     -UI_VARIANT canvas=B,stickerAdd=A,type=C
///
/// Release builds, and DEBUG without the argument, keep today's look. Once an
/// option is chosen it becomes the only path and this switch goes away.
enum UIVariant {
    enum Option: String {
        case current, a = "A", b = "B", c = "C"

        func pick<T>(_ current: T, a: T, b: T, c: T) -> T {
            switch self {
            case .current: return current
            case .a: return a
            case .b: return b
            case .c: return c
            }
        }
    }

    /// Round 2 of item 3 (owner picked A, with changes): the header Add is
    /// gone while a made sticker shows, and the sheet adds it.
    enum StickerAdd: String {
        case current, a = "A", b = "B", c = "C"
        /// A full-width "Add to page" under the preview; a tap on it adds.
        case a1 = "A1"
        /// "Add to page" with a compact Favorite beside it, one row.
        case a2 = "A2"
        /// A1, and the preview drags out onto the page.
        case a3 = "A3"

        /// Round 2: the sheet's own Add replaces the header's.
        var hidesHeaderAdd: Bool { [.a1, .a2, .a3].contains(self) }
        /// A full-width "Add to page" pill under the preview.
        var addPill: Bool { [.a, .a1, .a2, .a3].contains(self) }
        /// A tap on the preview adds it.
        var previewAdds: Bool { self != .current && self != .b }
    }

    /// Item 1, a bigger canvas card.
    static let canvas = option("canvas") ?? Option.current
    /// Item 3, the made sticker's Add within thumb reach.
    static let stickerAdd = option("stickerAdd") ?? StickerAdd.current
    /// Item 4, the UI type scale.
    static let type = option("type") ?? Option.current

    private static func option<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        #if DEBUG
        let pairs = UserDefaults.standard.string(forKey: "UI_VARIANT")?.split(separator: ",") ?? []
        for pair in pairs {
            let parts = pair.split(separator: "=")
            if parts.count == 2, parts[0] == key { return Value(rawValue: String(parts[1])) }
        }
        #endif
        return nil
    }
}

// MARK: - Item 1: canvas card

extension UIVariant {
    /// The card's side inset when it fills the width (the page scales up to
    /// fill it); nil keeps the page's own 360 pt width.
    static let canvasSideInset: CGFloat? = canvas.pick(nil, a: nil, b: 12, c: 8)
}

// MARK: - Item 4: type scale

extension UIVariant {
    /// The UI size for a role drawn at `size` today. `standard` is the role's
    /// iOS-standard size (option B); without one the size is mapped by band.
    static func typeSize(_ size: CGFloat, standard: CGFloat? = nil) -> CGFloat {
        switch type {
        case .current: return size
        case .a: return max(12, size + 2)
        case .b: return standard ?? standardSize(size)
        case .c: return dynamic(standard ?? standardSize(size))
        }
    }

    /// The iOS-standard band for today's sizes: 12 at the smallest, 13 for
    /// secondary lines, 15-17 for controls and body, 20-22 for titles.
    private static func standardSize(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<10.5: return 12
        case ..<11.5: return 13
        case ..<12.75: return 14
        case ..<13.5: return 15
        case ..<15.5: return 16
        case ..<17.5: return 17
        case ..<19: return 20
        case ..<23: return 22
        default: return size + 2
        }
    }

    /// Option C: the standard size follows the system text size, up to 1.35x
    /// (XXXL) so fixed chrome never runs out of room.
    private static func dynamic(_ size: CGFloat) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
        return min(UIFontMetrics.default.scaledValue(for: size, compatibleWith: traits), size * 1.35)
    }

    private static let contentSize = UIApplication.shared.preferredContentSizeCategory
}

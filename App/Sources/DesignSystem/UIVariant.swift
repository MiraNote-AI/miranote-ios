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

    /// Round 3 of item 3: what Add does with a made sticker. Today the
    /// canvas asks "Tap where it should go".
    enum PlaceFlow: String {
        case current
        /// Lands at once on a free spot in view, dropping in, selected.
        case direct = "1"
        /// A breathing ghost in view: drag it into place, or tap to drop.
        case ghost = "2"
        /// Flies from the sheet onto the page; a toast offers Undo.
        case flyIn = "3"
        /// Dragging the preview out is the main way; Add does `direct`.
        case dragFirst = "4"
        /// Lands beside the newest element while the panel stays open, so
        /// the page shows it arrive and another can follow.
        case stayAndStack = "5"
        /// Flow 3, quick: a 0.25 s hop onto flow 1's spot, a settle, the
        /// toast; a touch mid-flight lands it at once.
        case quickFly = "6"

        var flies: Bool { self == .flyIn || self == .quickFly }
    }

    static let placeFlow = option("placeFlow") ?? PlaceFlow.current

    /// DEBUG `-OWNER_SHOTS`: screenshots for the owner keep the -UITEST mock
    /// services but none of its test-only controls (the Samples pill), so
    /// frames match a Release build.
    static let ownerShots: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-OWNER_SHOTS")
        #else
        return false
        #endif
    }()

    /// DEBUG `-PLACE_SLOWMO <factor>`: the placement animations run that many
    /// times slower, for storyboard frames caught mid-motion.
    static let slowmo: Double = {
        #if DEBUG
        let factor = UserDefaults.standard.double(forKey: "PLACE_SLOWMO")
        if factor > 0 { return factor }
        #endif
        return 1
    }()

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

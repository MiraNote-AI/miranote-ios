import CoreText
import SwiftUI
import UIKit

/// Fraunces -- the bundled variable serif that carries the Flow 7 identity.
/// Weight and optical size are pinned through CoreText variation axes so a
/// single font file covers every display cut. If the face is not registered
/// (e.g. a stripped build), it falls back to the system serif ("New York").
enum Serif {
    private static let familyName = "Fraunces"
    private static let weightAxis = 0x77676874   // 'wght'
    private static let opticalAxis = 0x6F70737A  // 'opsz'

    private static let isAvailable = UIFont.familyNames.contains(familyName)

    static func font(size: CGFloat, weight: CGFloat, optical: CGFloat) -> Font {
        Font(uiFont(size: size, weight: weight, optical: optical))
    }

    static func uiFont(size: CGFloat, weight: CGFloat, optical: CGFloat) -> UIFont {
        guard isAvailable else { return systemSerif(size: size, weight: weight) }
        let variations: [Int: CGFloat] = [weightAxis: weight, opticalAxis: optical]
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: familyName,
            variationKey: variations
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func systemSerif(size: CGFloat, weight: CGFloat) -> UIFont {
        let named: UIFont.Weight
        switch weight {
        case ..<350: named = .light
        case ..<450: named = .regular
        case ..<550: named = .medium
        case ..<650: named = .semibold
        default: named = .bold
        }
        let base = UIFont.systemFont(ofSize: size, weight: named)
        if let serif = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: serif, size: size)
        }
        return base
    }
}

/// Josefin Sans -- the UI face of the 2026-10-07 redesign, a bundled variable
/// font whose weight is pinned through the 'wght' axis. Falls back to SF Pro
/// at the nearest named weight when the face is not registered.
enum Sans {
    private static let familyName = "Josefin Sans"
    private static let weightAxis = 0x77676874   // 'wght'

    private static let isAvailable = UIFont.familyNames.contains(familyName)

    static func font(size: CGFloat, weight: CGFloat) -> Font {
        Font(uiFont(size: size, weight: weight))
    }

    static func uiFont(size: CGFloat, weight: CGFloat) -> UIFont {
        guard isAvailable else { return UIFont.systemFont(ofSize: size, weight: named(weight)) }
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: familyName,
            variationKey: [weightAxis: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func named(_ weight: CGFloat) -> UIFont.Weight {
        switch weight {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        default: return .bold
        }
    }
}

/// Semantic type scale. Josefin Sans carries the UI and titles; Fraunces stays
/// only on the home display lines (hero, date), where the design uses a
/// high-contrast serif. No role goes below 11 pt -- the design's 8-10 px
/// labels are not legible on a phone.
extension Font {
    static let miraHero = Serif.font(size: 39, weight: 410, optical: 144)
    static let miraDate = Serif.font(size: 22, weight: 480, optical: 40)
    static let miraPageTitle = Sans.font(size: 22, weight: 700)
    static let miraScreenTitle = Sans.font(size: 18, weight: 600)
    static let miraLogo = Sans.font(size: 15, weight: 600)

    static let miraCardTitle = Sans.font(size: 15, weight: 600)
    static let miraStatus = Sans.font(size: 15, weight: 600)
    static let miraPill = Sans.font(size: 15, weight: 600)
    static let miraBody = Sans.font(size: 14, weight: 400)
    static let miraLabel = Sans.font(size: 13, weight: 500)
    static let miraCaption = Sans.font(size: 12.5, weight: 400)
    static let miraChip = Sans.font(size: 12.5, weight: 500)
}

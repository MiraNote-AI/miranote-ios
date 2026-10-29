import CoreText
import MiraNoteKit
import SwiftUI
import UIKit

/// Settings > Text size: the app's own type -- its chrome -- is set at
/// `AppSettings.textScale` times the size each call site asks for. A page's
/// content (text blocks, titles and markers drawn on the canvas, the reading
/// view's page, exports) keeps its own point sizes: it asks with
/// `scaled: false` (see `TextFace`). SF Symbol glyphs keep their sizes.
enum TextScale {
    /// Read inside a view's body, it also redraws that view when the
    /// setting changes (`AppSettings` is observable), so the whole app
    /// follows the slider at once.
    static var current: CGFloat { CGFloat(AppSettings.shared.textScale) }

    static func scaled(_ size: CGFloat) -> CGFloat {
        size * current
    }
}

/// Fraunces -- the bundled variable serif that carries the Flow 7 identity.
/// Weight and optical size are pinned through CoreText variation axes so a
/// single font file covers every display cut. If the face is not registered
/// (e.g. a stripped build), it falls back to the system serif ("New York").
enum Serif {
    private static let familyName = "Fraunces"
    private static let weightAxis = 0x77676874   // 'wght'
    private static let opticalAxis = 0x6F70737A  // 'opsz'

    private static let isAvailable = UIFont.familyNames.contains(familyName)

    static func font(size: CGFloat, weight: CGFloat, optical: CGFloat, scaled: Bool = true) -> Font {
        Font(uiFont(size: size, weight: weight, optical: optical, scaled: scaled))
    }

    /// `scaled` applies the text-size setting (`TextScale`); page content
    /// passes false.
    static func uiFont(size: CGFloat, weight: CGFloat, optical: CGFloat, scaled: Bool = true) -> UIFont {
        let size = scaled ? TextScale.scaled(size) : size
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

    static func font(size: CGFloat, weight: CGFloat, scaled: Bool = true) -> Font {
        Font(uiFont(size: size, weight: weight, scaled: scaled))
    }

    /// `scaled` applies the text-size setting (`TextScale`); page content
    /// passes false.
    static func uiFont(size: CGFloat, weight: CGFloat, scaled: Bool = true) -> UIFont {
        let size = scaled ? TextScale.scaled(size) : size
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
/// only on the home hero, where the design uses a high-contrast display face
/// (1769_W05, not bundled).
///
/// Sizes follow the iOS-standard scale the owner chose on 2026-10-19 over the
/// handoff's (it read small beside the system keyboard): inputs 17, controls
/// 15-16, body 16, secondary 13, nothing under 12, titles 20-22. The roles
/// below follow it; a few sizes off it remain (14 at call sites, and the
/// home's 24.6 and 26). Each role is read anew so it follows the text-size
/// setting.
extension Font {
    /// Nav pills: Josefin SemiBold 15.
    static var miraNav: Font { Sans.font(size: 15, weight: 600) }
    /// The Mira composer's field and placeholder: Medium 17, as iOS inputs.
    static var miraComposer: Font { Sans.font(size: 17, weight: 500) }
    /// The composer's action pill (Go, Apply): Bold 16.
    static var miraComposerAction: Font { Sans.font(size: 16, weight: 700) }

    static var miraHero: Font { Serif.font(size: 39, weight: 410, optical: 144) }
    /// Home dateline (screen 01): Josefin Bold 26.
    static var miraDate: Font { Sans.font(size: 26, weight: 700) }
    static var miraPageTitle: Font { Sans.font(size: 22, weight: 700) }
    static var miraScreenTitle: Font { Sans.font(size: 20, weight: 600) }
    static var miraLogo: Font { Sans.font(size: 17, weight: 700) }

    static var miraCardTitle: Font { Sans.font(size: 17, weight: 600) }
    static var miraPill: Font { Sans.font(size: 16, weight: 600) }
    static var miraBody: Font { Sans.font(size: 16, weight: 400) }
    static var miraLabel: Font { Sans.font(size: 15, weight: 500) }
    static var miraCaption: Font { Sans.font(size: 13, weight: 400) }
    static var miraChip: Font { Sans.font(size: 15, weight: 500) }
}

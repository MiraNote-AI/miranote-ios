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

/// Semantic type scale. Serif roles use Fraunces; UI roles use system SF Pro.
extension Font {
    static let miraHero = Serif.font(size: 39, weight: 410, optical: 144)
    static let miraPageTitle = Serif.font(size: 23, weight: 560, optical: 72)
    static let miraScreenTitle = Serif.font(size: 18, weight: 540, optical: 44)
    static let miraDate = Serif.font(size: 22, weight: 480, optical: 40)
    static let miraLogo = Serif.font(size: 15, weight: 580, optical: 24)

    static let miraCardTitle = Font.system(size: 15, weight: .semibold)
    static let miraStatus = Font.system(size: 15, weight: .semibold)
    static let miraPill = Font.system(size: 15, weight: .medium)
    static let miraBody = Font.system(size: 14, weight: .regular)
    static let miraLabel = Font.system(size: 13, weight: .medium)
    static let miraCaption = Font.system(size: 12.5, weight: .regular)
    static let miraChip = Font.system(size: 12.5, weight: .medium)
}

import MiraNoteKit
import SwiftUI
import UIKit

/// How a canvas text block is set: one place decides its face, line height
/// and insets, so the editor, the reading view and the height measurement
/// can never disagree (a mismatch truncates the last line).
enum TextFace {
    /// The font carousel (handoff screen 11): Futura, Josefin, Optima,
    /// Helvetica, Raleway as drawn, then the faces the carousel overflows
    /// into. "" is the pre-redesign default (system body, Fraunces titles),
    /// kept so older blocks can be set back to it.
    static let choices: [(name: String, label: String)] = [
        ("Futura", "Futura"),
        ("Josefin Sans", "Josefin"),
        ("Optima", "Optima"),
        ("Helvetica Neue", "Helvetica"),
        ("Raleway", "Raleway"),
        ("Didot", "Didot"),
        ("", "Classic"),
    ]

    /// A new block (handoff screens 11-20): Josefin Medium 21, ink #293322.
    static let newBlockFont = "Josefin Sans"
    static let newBlockSize: CGFloat = 21
    static let newBlockColor = "#293322"

    /// The words sit 12 in from the block's sides and 14 from its top and
    /// bottom, with or without a text background (screen 18: the
    /// background rect is the block, the words do not move when it lands).
    static let inset = EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
    /// The handoff sets 21 pt type on a 30 pt line.
    static let lineHeightRatio: CGFloat = 30 / 21
    /// The text background (screen 18): r24.
    static let backgroundCorner: CGFloat = 24

    /// Looked up once: every render and every height measurement asks.
    private static let installedFamilies = Set(UIFont.familyNames)

    /// Bundled variable faces of the curated sets (screen 05). Their default
    /// instance is often Thin or Light, so a weight is always set on the
    /// axis (Regular unless asked). Raleway has its own Medium default below.
    private static let variableFamilies: Set<String> = [
        "Lora", "Merriweather", "Montserrat", "Open Sans", "Playfair Display",
        "Oswald", "Darker Grotesque"
    ]

    /// `weight` is a CSS weight. The bundled variable faces (Josefin,
    /// Raleway, the curated-set faces) set it on their axis; Josefin and
    /// Raleway body text is Medium as drawn. System faces go bold from 600.
    static func uiFont(name: String, size: CGFloat, weight: CGFloat? = nil) -> UIFont {
        switch name {
        case "":
            // Larger blocks are display type and take the serif identity.
            return size >= CanvasViewModel.displayPointSize
                ? Serif.uiFont(size: size, weight: weight ?? 560, optical: 72)
                : UIFont.systemFont(ofSize: size, weight: (weight ?? 400) >= 600 ? .bold : .regular)
        case "Josefin Sans":
            return Sans.uiFont(size: size, weight: weight ?? 500)
        case "Raleway":
            return variable("Raleway", size: size, weight: weight ?? 500)
        default:
            // A face this device lacks falls back to the system font
            // instead of an invisible or mismatched one.
            guard installedFamilies.contains(name) else { return UIFont.systemFont(ofSize: size) }
            if variableFamilies.contains(name) {
                return variable(name, size: size, weight: weight ?? 400)
            }
            var descriptor = UIFontDescriptor(fontAttributes: [.family: name])
            if (weight ?? 400) >= 600, let bold = descriptor.withSymbolicTraits(.traitBold) {
                descriptor = bold
            }
            return UIFont(descriptor: descriptor, size: size)
        }
    }

    static func font(for block: TextBlock) -> Font {
        Font(uiFont(name: block.fontName, size: block.pointSize))
    }

    /// Extra space between lines that puts the block's lines on the
    /// handoff's 30-on-21 rhythm at any size.
    static func lineSpacing(for block: TextBlock) -> CGFloat {
        lineSpacing(font: uiFont(name: block.fontName, size: block.pointSize))
    }

    static func lineSpacing(font: UIFont) -> CGFloat {
        max(0, font.pointSize * lineHeightRatio - font.lineHeight)
    }

    private static func variable(_ family: String, size: CGFloat, weight: CGFloat) -> UIFont {
        guard installedFamilies.contains(family) else { return UIFont.systemFont(ofSize: size) }
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            variationKey: [0x77676874: weight],  // 'wght'
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension TextAlign {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Where the lines sit inside the block's frame.
    var frameAlignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }
}

extension View {
    /// The block's own text background (screen 18: r24 behind the inset
    /// words), lifted by the handoff's `0 14 12 #263521@0.18` shadow
    /// (screen 21); nothing when the block has none.
    func textBlockBackground(_ block: TextBlock) -> some View {
        background {
            if !block.backgroundColorName.isEmpty {
                RoundedRectangle(cornerRadius: TextFace.backgroundCorner)
                    .fill(Palette.color(named: block.backgroundColorName))
                    .shadow(color: Color(hex: 0x263521).opacity(0.18), radius: 6, y: 14)
            }
        }
    }
}

import MiraNoteKit
import SwiftUI
import UIKit

/// How a canvas text block is set: one place decides its face, so the editor,
/// the reading view and the height measurement can never disagree (a
/// mismatch truncates the last line).
enum TextFace {
    /// The editor's font row. "" is the default; the rest are Josefin Sans
    /// (bundled) and faces every iPhone already has.
    static let choices: [(name: String, label: String)] = [
        ("", "Default"),
        ("Josefin Sans", "Josefin"),
        ("Futura", "Futura"),
        ("Optima", "Optima"),
        ("Didot", "Didot"),
        ("Helvetica Neue", "Helvetica"),
    ]

    /// Looked up once: every render and every height measurement asks.
    private static let installedFamilies = Set(UIFont.familyNames)

    static func uiFont(name: String, size: CGFloat) -> UIFont {
        switch name {
        case "":
            // Larger blocks are display type and take the serif identity.
            return size >= 24
                ? Serif.uiFont(size: size, weight: 560, optical: 72)
                : UIFont.systemFont(ofSize: size)
        case "Josefin Sans":
            return Sans.uiFont(size: size, weight: 400)
        default:
            // A face this device lacks falls back to the system font
            // instead of an invisible or mismatched one.
            guard installedFamilies.contains(name) else { return UIFont.systemFont(ofSize: size) }
            return UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: name]), size: size)
        }
    }

    static func font(for block: TextBlock) -> Font {
        Font(uiFont(name: block.fontName, size: block.pointSize))
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

    var symbol: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
}

extension View {
    /// The block's own text background (phase B1), drawn behind the padded
    /// words; nothing when the block has none.
    func textBlockBackground(_ block: TextBlock) -> some View {
        background {
            if !block.backgroundColorName.isEmpty {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Palette.color(named: block.backgroundColorName))
            }
        }
    }
}

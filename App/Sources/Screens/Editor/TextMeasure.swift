import MiraNoteKit
import SwiftUI
import UIKit

/// Measures a text block's rendered height so blocks grow with their
/// content instead of scrolling inside a fixed frame. Uses TextFace's face,
/// line spacing and insets -- the same ones the block is drawn with.
enum TextMeasure {
    static func blockHeight(
        text: String, pointSize: CGFloat, fontName: String = "", width: CGFloat
    ) -> CGFloat {
        let font = TextFace.uiFont(name: fontName, size: pointSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = TextFace.lineSpacing(font: font)
        let inset = TextFace.inset
        let sample = text.isEmpty ? "Ag" : text
        let bounds = (sample as NSString).boundingRect(
            with: CGSize(
                width: max(40, width - inset.leading - inset.trailing),
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        )
        // The insets plus a little caret breathing room.
        return max(36, ceil(bounds.height) + inset.top + inset.bottom + 4)
    }
}

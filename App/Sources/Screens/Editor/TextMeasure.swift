import MiraNoteKit
import SwiftUI
import UIKit

/// Measures a text block's rendered height so blocks grow with their
/// content instead of scrolling inside a fixed frame.
enum TextMeasure {
    static func blockHeight(text: String, pointSize: CGFloat, width: CGFloat) -> CGFloat {
        let font: UIFont = pointSize >= 24
            ? Serif.uiFont(size: pointSize, weight: 560, optical: 72)
            : UIFont.systemFont(ofSize: pointSize)
        let sample = text.isEmpty ? "Ag" : text
        let bounds = (sample as NSString).boundingRect(
            with: CGSize(width: max(40, width - 12), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        // 6pt padding top and bottom plus a little caret breathing room.
        return max(36, ceil(bounds.height) + 20)
    }
}

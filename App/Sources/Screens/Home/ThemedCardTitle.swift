import SwiftUI
import UIKit

/// A Home card title in a theme face (handoff 2026-10-24, screens 01-02):
/// up to two lines at the design's 23-on-20 pitch. The face's own line box
/// is taller and SwiftUI cannot tighten it, so the lines are wrapped here
/// and stacked; a word too wide for the card shrinks the title (to 80% at
/// most) rather than break.
struct ThemedCardTitle: View {
    let title: String
    let face: UIFont
    let width: CGFloat

    var body: some View {
        let fitted = Self.fitting(title, font: face, width: width)
        let lines = Self.wrap(title, font: fitted, width: width)
        VStack(alignment: .leading, spacing: fitted.pointSize * 23 / 20 - fitted.lineHeight) {
            Text(lines[0])
            if lines.count > 1 {
                Text(lines.dropFirst().joined(separator: " "))
            }
        }
        .font(Font(fitted))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // The first line's cap at the design's 27 below the card top.
        .padding(.top, -4)
    }

    private static func fitting(_ text: String, font: UIFont, width: CGFloat) -> UIFont {
        let widest = text.split(separator: " ")
            .map { String($0).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        guard widest > width else { return font }
        return font.withSize(font.pointSize * max(0.8, width / widest))
    }

    /// The lines `text` breaks into at `width`, as UIKit wraps them.
    private static func wrap(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var lines: [String] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.isEmpty ? [text] : lines
    }
}

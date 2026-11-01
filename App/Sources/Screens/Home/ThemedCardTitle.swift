import SwiftUI
import UIKit

/// A Home card title in a theme face (handoff 2026-10-24, screens 01-02):
/// up to two lines at the design's 23-on-20 pitch. The face's own line box
/// is taller and SwiftUI cannot tighten it, so the lines are wrapped here
/// and stacked; a word too wide for the card shrinks the title (to 80% of
/// the design size at most) rather than break. Chinese and Japanese break between any two
/// characters, so each character counts as a word there.
struct ThemedCardTitle: View {
    let title: String
    let face: UIFont
    let width: CGFloat

    var body: some View {
        let fitted = Self.fitting(title, font: face, width: width, scale: TextScale.current)
        let lines = Self.wrap(title, font: fitted, width: width)
        VStack(alignment: .leading, spacing: fitted.pointSize * 23 / 20 - fitted.lineHeight) {
            Text(lines[0])
            if lines.count > 1 {
                Text(Self.joined(lines.dropFirst()))
            }
        }
        // One element for VoiceOver, read as typed, not line by line.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .font(Font(fitted))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // The first line's cap at the design's 27 below the card top.
        .padding(.top, -4)
    }

    /// `font` at the text-size setting `scale`, shrunk until its widest word
    /// fits `width`. The floor is 80% of the design size, not of the scaled
    /// one, so a larger text size never brings back a broken word.
    static func fitting(_ text: String, font: UIFont, width: CGFloat, scale: CGFloat) -> UIFont {
        let widest = text.split(separator: " ")
            .flatMap { word in word.contains(where: \.isCJK) ? word.map { String($0) } : [String(word)] }
            .map { $0.size(withAttributes: [.font: font]).width }
            .max() ?? 0
        guard widest > width else { return font }
        return font.withSize(font.pointSize * max(0.8 / scale, width / widest))
    }

    /// Lines rejoined with the space the wrap took out -- none between
    /// two CJK characters.
    static func joined(_ lines: ArraySlice<String>) -> String {
        lines.reduce("") { text, line in
            guard let last = text.last, let first = line.first else { return text + line }
            return text + (last.isCJK && first.isCJK ? "" : " ") + line
        }
    }

    /// Wrapped titles by face, size, width and text: Home redraws its cards
    /// often, the titles rarely change.
    @MainActor private static var wrapped: [String: [String]] = [:]

    /// The lines `text` breaks into at `width`, as UIKit wraps them.
    @MainActor private static func wrap(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        let key = "\(font.fontName)|\(font.pointSize)|\(width)|\(text)"
        if let lines = wrapped[key] { return lines }
        let lines = layOut(text, font: font, width: width)
        wrapped[key] = lines
        return lines
    }

    private static func layOut(_ text: String, font: UIFont, width: CGFloat) -> [String] {
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

private extension Character {
    /// Han, kana, CJK punctuation and fullwidth forms: scripts written
    /// without spaces between words.
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}

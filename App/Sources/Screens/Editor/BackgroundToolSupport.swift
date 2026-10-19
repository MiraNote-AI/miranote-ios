import MiraNoteKit
import SwiftUI
import UIKit

/// The preview card's two lines: the page's title (its largest words,
/// topmost on a tie) and the first line of the next block, in the faces and
/// colors they wear. A page without words shows the handoff's sample.
struct PreviewWords {
    let title: String
    let line: String
    let titleFont: Font
    let lineFont: Font
    let titleColor: Color
    let lineColor: Color

    @MainActor init(editor: CanvasViewModel) {
        let blocks: [(TextBlock, CGFloat)] = editor.items.compactMap {
            guard case .text(let block) = $0.content,
                  !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (block, $0.position.y)
        }
        let titleIndex = blocks.indices.min { lhs, rhs in
            let (left, right) = (blocks[lhs], blocks[rhs])
            return left.0.pointSize != right.0.pointSize ? left.0.pointSize > right.0.pointSize : left.1 < right.1
        }
        let titleBlock = titleIndex.map { blocks[$0].0 }
        let lineBlock = blocks.indices.filter { $0 != titleIndex }.min { blocks[$0].1 < blocks[$1].1 }
            .map { blocks[$0].0 }

        title = titleBlock.map { Self.firstLine($0.text) } ?? "Lunch by the river"
        line = lineBlock.map { Self.firstLine($0.text) } ?? (titleBlock == nil ? "A small moment worth keeping." : "")
        titleFont = Self.font(titleBlock?.fontName ?? "", size: 14, fallbackWeight: 700)
        lineFont = Self.font(lineBlock?.fontName ?? "", size: 10, fallbackWeight: 500)
        titleColor = Self.color(titleBlock?.colorName, fallback: Palette.ink)
        lineColor = Self.color(lineBlock?.colorName, fallback: Palette.muted)
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }

    /// The default face previews as the handoff's Josefin; a chosen face
    /// as itself.
    private static func font(_ name: String, size: CGFloat, fallbackWeight: CGFloat) -> Font {
        // Page faces at page sizes: never the UI type option.
        Font(name.isEmpty ? Sans.uiFont(size: size, weight: fallbackWeight) : TextFace.uiFont(name: name, size: size))
    }

    /// Default ink words preview in the handoff's colors; chosen colors as
    /// themselves.
    private static func color(_ name: String?, fallback: Color) -> Color {
        guard let name, name != "ink" else { return fallback }
        return Palette.color(named: name)
    }
}

import MiraNoteKit
import SwiftUI

// MARK: - One-tap layout (#183)

extension CanvasScene {
    /// Offered on a bare canvas with something to arrange. A temporary
    /// entry over the tool bar until the editor menus settle (#180).
    var offersLayout: Bool {
        editor.memory.items.count >= 2 && editor.selectedItemID == nil && !mira.isWorking
    }

    var layoutEntry: some View {
        HStack {
            Spacer()
            Button(action: openLayout) {
                Label("Layout", systemImage: "square.grid.2x2")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Palette.toolSurface))
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityIdentifier("layout.open")
        }
        .padding(.horizontal, Metrics.toolBarInset)
    }

    func openLayout() {
        editor.select(nil)
        layoutPick = nil
        layoutOriginal = editor.memory.items
    }

    /// The page as `template` lays it out, shown at once; nothing is kept
    /// until Done.
    func tryLayout(_ template: PageLayout.Template) {
        guard let original = layoutOriginal else { return }
        layoutPick = template
        withAnimation(.spring(duration: 0.35)) {
            editor.previewLayout(laidOut(template, original))
        }
        // Templates start at the page's top: show it.
        revealItem = editor.memory.items.min { $0.position.y - $0.size.height / 2 < $1.position.y - $1.size.height / 2 }?.id
    }

    /// The header's undo while the strip is open: the page as it was, the
    /// strip still open.
    func undoLayoutTry() {
        guard let original = layoutOriginal else { return }
        withAnimation(.spring(duration: 0.35)) { editor.previewLayout(original) }
        layoutPick = nil
    }

    func cancelLayout() {
        guard let original = layoutOriginal else { return }
        withAnimation(.spring(duration: 0.35)) { editor.previewLayout(original) }
        layoutOriginal = nil
        layoutPick = nil
    }

    /// Keeps the layout tried last: one undo step back to the page before.
    func keepLayout() {
        guard let original = layoutOriginal else { return }
        editor.commitLayout(from: original)
        layoutOriginal = nil
        layoutPick = nil
    }

    func laidOut(_ template: PageLayout.Template, _ items: [CanvasItem]) -> [CanvasItem] {
        PageLayout.apply(template, to: items, pageWidth: MiraNoteConfig.pageWidth, textHeight: Self.textHeight)
    }

    var layoutStrip: some View {
        let original = layoutOriginal ?? []
        let templates = PageLayout.templates(for: original, pageWidth: MiraNoteConfig.pageWidth,
                                             textHeight: Self.textHeight)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(templates) { template in
                    Button {
                        tryLayout(template)
                    } label: {
                        LayoutThumbnail(template: template, items: laidOut(template, original),
                                        picked: template == layoutPick)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(template.title)
                    .accessibilityAddTraits(template == layoutPick ? .isSelected : [])
                    .accessibilityIdentifier("layout.template.\(template.rawValue)")
                }
            }
            .padding(.horizontal, Metrics.toolBarInset)
        }
    }

    private static func textHeight(_ item: CanvasItem, _ width: CGFloat) -> CGFloat {
        guard case .text(let block) = item.content else { return item.size.height }
        return max(36, TextMeasure.blockHeight(text: block.text, pointSize: block.pointSize,
                                               fontName: block.fontName, width: width))
    }
}

extension PageLayout.Template {
    var title: String {
        switch self {
        case .grid: return String(appCopy: "Photo grid")
        case .titleGrid: return String(appCopy: "Title grid")
        case .hero: return String(appCopy: "Big photo")
        case .column: return String(appCopy: "Diary")
        case .collage: return String(appCopy: "Collage")
        }
    }
}

/// A template drawn small: photos as blocks, words as lines, stickers as
/// dots, the whole laid-out page fitted in the card.
private struct LayoutThumbnail: View {
    let template: PageLayout.Template
    let items: [CanvasItem]
    let picked: Bool

    private let card = CGSize(width: 64, height: 84)

    var body: some View {
        VStack(spacing: 5) {
            Canvas { context, size in
                let bottom = items.map { $0.position.y + $0.size.height / 2 }.max() ?? 1
                let scale = min(size.width / MiraNoteConfig.pageWidth, size.height / max(bottom + 12, 1))
                let left = (size.width - MiraNoteConfig.pageWidth * scale) / 2
                for item in items.sorted(by: { $0.zIndex < $1.zIndex }) {
                    let rect = CGRect(x: -item.size.width / 2 * scale, y: -item.size.height / 2 * scale,
                                      width: item.size.width * scale, height: item.size.height * scale)
                    var piece = context
                    piece.translateBy(x: left + item.position.x * scale, y: 4 + item.position.y * scale)
                    piece.rotate(by: .degrees(item.rotation))
                    switch item.content {
                    case .image:
                        piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Palette.ink.opacity(0.35)))
                    case .text:
                        let lines = max(1, min(3, Int(rect.height / 4)))
                        for n in 0..<lines {
                            let width = rect.width * (n == lines - 1 && lines > 1 ? 0.6 : 1)
                            let line = CGRect(x: rect.minX, y: rect.minY + CGFloat(n) * 4 + 1, width: width, height: 2)
                            piece.fill(Path(roundedRect: line, cornerRadius: 1), with: .color(Palette.ink.opacity(0.55)))
                        }
                    case .sticker:
                        piece.fill(Path(ellipseIn: rect), with: .color(Palette.forest.opacity(0.7)))
                    case .sound:
                        piece.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                                   with: .color(Palette.ink.opacity(0.2)))
                    }
                }
            }
            .frame(width: card.width, height: card.height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.toolSurface))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(picked ? Palette.ink : Palette.hairline, lineWidth: picked ? 2 : 1))
            Text(template.title)
                .font(.miraCaption)
                .foregroundStyle(picked ? Palette.ink : Palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 76)
    }
}

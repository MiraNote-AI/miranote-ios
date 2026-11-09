import MiraNoteKit
import SwiftUI

// MARK: - One-tap layout (#183)

extension CanvasScene {
    /// The tool bar's Layout: something to arrange takes two elements.
    var canLayout: Bool {
        editor.memory.items.count >= 2
    }

    func openLayout() {
        editor.select(nil)
        layoutPick = nil
        layoutOriginal = editor.memory.items
        layoutScroll = scrollMemory.offset
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
        scrollBack = layoutScroll
    }

    func cancelLayout() {
        guard let original = layoutOriginal else { return }
        withAnimation(.spring(duration: 0.35)) { editor.previewLayout(original) }
        layoutOriginal = nil
        layoutPick = nil
        scrollBack = layoutScroll
    }

    /// Keeps the layout tried last: one undo step back to the page before.
    func keepLayout() {
        guard let original = layoutOriginal else { return }
        editor.commitLayout(from: original)
        layoutOriginal = nil
        layoutPick = nil
    }

    func laidOut(_ template: PageLayout.Template, _ items: [CanvasItem]) -> [CanvasItem] {
        PageLayout.apply(template, to: items, pageWidth: MiraNoteConfig.pageWidth, textHeight: Self.textHeight,
                         photoAspect: Self.photoAspect)
    }

    var layoutStrip: some View {
        let original = layoutOriginal ?? []
        let templates = PageLayout.templates(for: original)
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

    /// The photo's own shape (height over width), not its box's: a box an
    /// earlier template cropped would say nothing about the picture.
    private static func photoAspect(_ item: CanvasItem) -> CGFloat {
        if case .image(let ref) = item.content,
           let image = CanvasImageCache.image(fileName: ref.fileName, filterName: ref.filterName,
                                              store: ImageFileStore(), maxPixels: CanvasImageCache.displayPixels),
           image.size.width > 0 {
            return image.size.height / image.size.width
        }
        return item.size.height / max(item.size.width, 1)
    }
}

extension PageLayout.Template {
    var title: String {
        switch self {
        case .cover: return String(appCopy: "Cover")
        case .polaroid: return String(appCopy: "Polaroid")
        case .minimal: return String(appCopy: "Minimal air")
        case .stagger: return String(appCopy: "Stagger")
        case .scrapbook: return String(appCopy: "Scrapbook tape")
        case .onePlusTwo: return String(appCopy: "1 + 2")
        case .tShape: return String(appCopy: "T-shape")
        case .grid2x2: return String(appCopy: "2 x 2")
        case .heroThree: return String(appCopy: "Hero + 3")
        case .polaroidWall: return String(appCopy: "Polaroid wall")
        case .magazine: return String(appCopy: "Magazine")
        case .journal: return String(appCopy: "Journal")
        case .nineGrid: return String(appCopy: "Nine grid")
        case .twinHero: return String(appCopy: "Twin hero")
        case .masonry: return String(appCopy: "Masonry")
        case .strip: return String(appCopy: "Long strip")
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

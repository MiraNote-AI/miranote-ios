import MiraNoteKit
import SwiftUI

// MARK: - One-tap layout (#183)

extension CanvasScene {
    /// Why the tool bar's Layout is dimmed, shown when it is tapped; nil
    /// when it can open.
    var layoutBlocked: String? {
        if mira.isWorking { return String(appCopy: "Layout waits for Mira to finish") }
        if case .recording = recorderState { return String(appCopy: "Layout waits for the recording to finish") }
        // Landing under a template being tried, the new pixels would go with
        // Cancel and leave the template as the step under them.
        if photoEditors.anyWorking { return String(appCopy: "Layout waits for the photo edit to finish") }
        return Self.layoutHint(for: editor.memory.items)
    }

    /// What the page still needs for Layout; nil when it can be arranged.
    /// The Sticker panels' tool bars say it too.
    static func layoutHint(for items: [CanvasItem]) -> String? {
        if PageLayout.isOffered(for: items) { return nil }
        return items.contains { if case .image = $0.content { return true }; return false }
            ? String(appCopy: "Add words or another photo to use Layout")
            : String(appCopy: "Add a photo to use Layout")
    }

    /// The strip open (Layout again closes it) or a page it can arrange.
    var canLayout: Bool {
        layoutOriginal != nil || layoutBlocked == nil
    }

    func openLayout() {
        editor.select(nil)
        // A waiting result moves on (Keep), as Background does: its Revert
        // would act under the preview, which then put the page back over it.
        if receipt != nil { mira.dismiss() }
        let items = editor.memory.items
        // A page laid out by a template already shows that card picked.
        layoutPick = PageLayout.templates(for: items).first { PageLayout.sameArrangement(laidOut($0, items), items) }
        layoutOriginal = items
        layoutScroll = scrollMemory.offset
    }

    /// The page as `template` lays it out, shown at once; nothing is kept
    /// until Done.
    func tryLayout(_ template: PageLayout.Template) {
        guard let original = layoutOriginal else { return }
        layoutPick = template
        withAnimation(layoutMotion) {
            editor.previewLayout(laidOut(template, original))
        }
        // Templates start at the page's top: show it.
        let top = { (item: CanvasItem) in item.position.y - item.size.height / 2 }
        revealItem = editor.memory.items.min { top($0) < top($1) }?.id
    }

    /// The header's undo while the strip is open: the page as it was, the
    /// strip still open.
    func undoLayoutTry() {
        guard let original = layoutOriginal else { return }
        withAnimation(layoutMotion) { editor.previewLayout(original) }
        layoutPick = nil
        scrollBack = layoutScroll
    }

    func cancelLayout() {
        guard let original = layoutOriginal else { return }
        withAnimation(layoutMotion) { editor.cancelLayout(to: original) }
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

    /// Elements moving to a template's places; at once with Reduce Motion.
    private var layoutMotion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.35)
    }

    func laidOut(_ template: PageLayout.Template, _ items: [CanvasItem]) -> [CanvasItem] {
        PageLayout.apply(template, to: items, pageWidth: MiraNoteConfig.pageWidth, textHeight: Self.textHeight,
                         photoAspect: Self.photoAspect)
    }

    var layoutStrip: some View {
        let original = layoutOriginal ?? []
        let templates = PageLayout.templates(for: original)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(templates) { template in
                        Button {
                            tryLayout(template)
                        } label: {
                            LayoutThumbnail(template: template, items: laidOut(template, original),
                                            picked: template == layoutPick)
                        }
                        .buttonStyle(.plain)
                        .id(template)
                        .accessibilityLabel(template.title)
                        .accessibilityAddTraits(template == layoutPick ? .isSelected : [])
                        .accessibilityIdentifier("layout.template.\(template.rawValue)")
                    }
                }
                .padding(.horizontal, Metrics.toolBarInset)
            }
            // The picked card in full view, a half-shown one too.
            .onAppear { if let layoutPick { proxy.scrollTo(layoutPick) } }
            .onChange(of: layoutPick) { _, pick in
                guard let pick else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(pick) }
            }
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
        case .minimal: return String(appCopy: "Minimal")
        case .stagger: return String(appCopy: "Stagger")
        case .scrapbook: return String(appCopy: "Scrapbook")
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
                        for row in 0..<lines {
                            let width = rect.width * (row == lines - 1 && lines > 1 ? 0.6 : 1)
                            let line = CGRect(x: rect.minX, y: rect.minY + CGFloat(row) * 4 + 1,
                                              width: width, height: 2)
                            piece.fill(Path(roundedRect: line, cornerRadius: 1),
                                       with: .color(Palette.ink.opacity(0.55)))
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

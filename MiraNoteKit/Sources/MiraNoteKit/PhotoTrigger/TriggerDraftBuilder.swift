import CoreGraphics
import Foundation

/// The canvas page a trigger's button opens (handoff 7.8): from the top,
/// the fact line at 30 pt (the largest, topmost text, so the saved page's
/// title is the fact line), the photos as the ending grid laid them out
/// (the peak in the big cell), the detail line in the ending's detail
/// font (none when empty), and the question at 17 pt in the body face.
/// Real text, not placeholders: saved untouched, it stays on the page.
public enum TriggerDraftBuilder {
    public static let margin: CGFloat = 20
    static let top: CGFloat = 24
    static let factHeight: CGFloat = 56
    static let gap: CGFloat = 16
    static let detailSize: CGFloat = 22
    static let questionSize: CGFloat = 17

    /// - Parameters:
    ///   - imageFiles: photo id ("P1") -> its `ImageFileStore` file name;
    ///     a photo without one is left out.
    ///   - detailFont: the ending's detail face (a `TextBlock.fontName`).
    public static func build(memory: TriggerMemory, imageFiles: [String: String], detailFont: String) -> Memory {
        let width = MiraNoteConfig.pageWidth - 2 * margin
        var items: [CanvasItem] = []
        var zIndex = 0
        func addText(_ block: TextBlock, top: CGFloat, height: CGFloat) {
            items.append(CanvasItem(content: .text(block), position: CGPoint(x: MiraNoteConfig.pageWidth / 2,
                                                                              y: top + height / 2),
                                    size: CGSize(width: width, height: height), zIndex: zIndex))
            zIndex += 1
        }

        addText(TextBlock(text: memory.ending.factLine, pointSize: 30), top: top, height: factHeight)

        let photos = memory.storyPhotos.filter { imageFiles[$0.id] != nil }
        let gridTop = top + factHeight + gap / 2
        let grid = TriggerGridLayout(photoCount: max(1, photos.count), width: width)
        for (index, photo) in photos.enumerated() {
            guard let file = imageFiles[photo.id] else { continue }
            let cell = index == 0 || index > grid.small.count ? grid.big : grid.small[index - 1]
            let frame = cell.offsetBy(dx: margin, dy: gridTop)
            let ref = ImageRef(displayName: "Photo \(photo.id)", fileName: file, summary: memory.facts[photo.id] ?? "")
            items.append(CanvasItem(content: .image(ref), position: CGPoint(x: frame.midX, y: frame.midY),
                                    size: frame.size, zIndex: zIndex))
            zIndex += 1
        }

        var next = gridTop + grid.size.height + gap
        if !memory.ending.detail.isEmpty {
            let height = textHeight(memory.ending.detail, size: detailSize, width: width)
            addText(TextBlock(text: memory.ending.detail, pointSize: detailSize, fontName: detailFont),
                    top: next, height: height)
            next += height + gap / 2
        }
        addText(TextBlock(text: memory.ending.question, pointSize: questionSize), top: next,
                height: textHeight(memory.ending.question, size: questionSize, width: width))

        return Memory(title: memory.ending.factLine, memoryDate: shootingDay(memory), items: items)
    }

    /// A generous box for `text`: the canvas measures and fits text itself;
    /// this only keeps the blocks from overlapping on arrival.
    static func textHeight(_ text: String, size: CGFloat, width: CGFloat) -> CGFloat {
        let perLine = max(1, Int((width - 24) / size))
        let lines = max(1, Int(ceil(Double(text.count) / Double(perLine))))
        return CGFloat(lines) * size * 30 / 21 + 28
    }

    /// Noon of the memory's day, in the phone's calendar.
    static func shootingDay(_ memory: TriggerMemory) -> Date {
        let parts = memory.date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return memory.peak?.takenAt ?? .now }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
            ?? memory.peak?.takenAt ?? .now
    }
}

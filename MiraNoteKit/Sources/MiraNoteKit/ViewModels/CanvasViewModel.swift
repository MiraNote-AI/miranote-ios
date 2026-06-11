import CoreGraphics
import Foundation
import Observation

/// Canvas screen (sketch 2): free placement, long-press insert menu,
/// bottom toolbar with expandable drawer, Save and Quick organize.
@MainActor
@Observable
public final class CanvasViewModel {
    public private(set) var memory: Memory

    /// Long-press insert menu state (sketch 2: Text / Image / AI).
    public var insertMenuLocation: CGPoint?

    /// A1: bottom drawer expands like a sticker library.
    public var isDrawerExpanded = false

    public init(memory: Memory) {
        self.memory = memory
    }

    public var items: [CanvasItem] { memory.items }

    // MARK: Insertion

    public func addText(_ text: String, at position: CGPoint) {
        memory.items.append(CanvasItem(content: .text(text), position: position))
    }

    public func addImages(_ images: [ImageRef], around position: CGPoint) {
        for (offset, image) in images.enumerated() {
            let shifted = CGPoint(x: position.x + CGFloat(offset) * 24, y: position.y + CGFloat(offset) * 24)
            memory.items.append(CanvasItem(content: .image(image), position: shifted))
        }
    }

    public func addSticker(_ sticker: GeneratedSticker, at position: CGPoint) {
        memory.items.append(CanvasItem(content: .sticker(sticker), position: position))
    }

    public func move(itemID: CanvasItem.ID, to position: CGPoint) {
        guard let index = memory.items.firstIndex(where: { $0.id == itemID }) else { return }
        memory.items[index].position = position
    }

    // MARK: Top bar actions

    public func save() {
        memory.savedAt = .now
    }

    /// A2 "Quick organize": deterministic tidy-up -- items snap to a grid,
    /// reading order preserved. Real auto-organization arrives with the
    /// backend feature; the deterministic layout keeps this testable.
    public func quickOrganize(canvasWidth: CGFloat, spacing: CGFloat = 120) {
        let columns = max(1, Int(canvasWidth / spacing))
        for (offset, item) in memory.items.enumerated() {
            let column = offset % columns
            let row = offset / columns
            let position = CGPoint(
                x: spacing / 2 + CGFloat(column) * spacing,
                y: spacing / 2 + CGFloat(row) * spacing
            )
            move(itemID: item.id, to: position)
        }
    }
}

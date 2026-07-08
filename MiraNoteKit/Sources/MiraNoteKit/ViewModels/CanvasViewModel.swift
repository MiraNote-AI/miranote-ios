import CoreGraphics
import Foundation
import Observation

/// The v2.1 canvas editor core: an element list with selection, geometry
/// (move / resize / rotate), stacking order, duplication, deletion, and a
/// snapshot undo stack. The view layer owns gestures; every mutation that a
/// user would call "one change" is bracketed by `beginChange()` so a single
/// undo steps back a whole gesture, not a drag tick.
@MainActor
@Observable
public final class CanvasViewModel {
    public private(set) var memory: Memory

    /// The currently selected element, if any (shows handles in the view).
    public var selectedItemID: CanvasItem.ID?

    /// The text element currently being edited in place, if any.
    public var editingTextItemID: CanvasItem.ID?

    private var history: [[CanvasItem]] = []
    private static let historyCap = 50

    public init(memory: Memory) {
        self.memory = memory
    }

    public var items: [CanvasItem] { memory.items }

    /// Items in stacking order (lowest z first -- painter's order).
    public var orderedItems: [CanvasItem] {
        memory.items.sorted { $0.zIndex < $1.zIndex }
    }

    public func item(_ id: CanvasItem.ID) -> CanvasItem? {
        memory.items.first { $0.id == id }
    }

    /// Bottom edge of the lowest element -- the infinite canvas grows to
    /// wrap this (plus breathing room added by the view).
    public var contentBottom: CGFloat {
        memory.items.map { $0.position.y + $0.size.height / 2 }.max() ?? 0
    }

    // MARK: Undo

    public var canUndo: Bool { !history.isEmpty }

    /// Snapshot the current items. Call once before a discrete change or at
    /// the START of a continuous gesture (drag / resize / rotate).
    public func beginChange() {
        history.append(memory.items)
        if history.count > Self.historyCap {
            history.removeFirst()
        }
    }

    public func undo() {
        guard let snapshot = history.popLast() else { return }
        memory.items = snapshot
        if let selected = selectedItemID, item(selected) == nil {
            selectedItemID = nil
        }
        if let editing = editingTextItemID, item(editing) == nil {
            editingTextItemID = nil
        }
    }

    // MARK: Selection

    public func select(_ id: CanvasItem.ID?) {
        selectedItemID = id
        if editingTextItemID != id {
            editingTextItemID = nil
        }
    }

    /// Begin in-place text editing (records one undo point for the whole
    /// editing session).
    public func startEditingText(_ id: CanvasItem.ID) {
        guard case .text = item(id)?.content else { return }
        beginChange()
        selectedItemID = id
        editingTextItemID = id
    }

    public func endEditingText() {
        editingTextItemID = nil
    }

    // MARK: Insertion

    @discardableResult
    public func addText(
        _ text: String,
        at position: CGPoint,
        pointSize: CGFloat = 17,
        size: CGSize = CGSize(width: 220, height: 84)
    ) -> CanvasItem.ID {
        beginChange()
        let item = CanvasItem(
            content: .text(TextBlock(text: text, pointSize: pointSize)),
            position: position,
            size: size,
            zIndex: topZ + 1
        )
        memory.items.append(item)
        return item.id
    }

    public func addImages(_ images: [ImageRef], around position: CGPoint) {
        beginChange()
        for (offset, image) in images.enumerated() {
            let shifted = CGPoint(x: position.x + CGFloat(offset) * 24, y: position.y + CGFloat(offset) * 24)
            memory.items.append(CanvasItem(
                content: .image(image),
                position: shifted,
                size: CGSize(width: 170, height: 150),
                zIndex: topZ + 1 + offset
            ))
        }
    }

    public func addSticker(_ sticker: GeneratedSticker, at position: CGPoint) {
        beginChange()
        memory.items.append(CanvasItem(
            content: .sticker(sticker),
            position: position,
            size: CGSize(width: 88, height: 88),
            zIndex: topZ + 1
        ))
    }

    @discardableResult
    public func addSound(_ clip: SoundClip, at position: CGPoint) -> CanvasItem.ID {
        beginChange()
        let item = CanvasItem(
            content: .sound(clip),
            position: position,
            size: CGSize(width: 200, height: 44),
            zIndex: topZ + 1
        )
        memory.items.append(item)
        return item.id
    }

    // MARK: Geometry (continuous -- caller brackets with beginChange())

    public func move(itemID: CanvasItem.ID, to position: CGPoint) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].position = position
    }

    public func resize(itemID: CanvasItem.ID, to size: CGSize) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].size = CGSize(
            width: max(44, size.width),
            height: max(36, size.height)
        )
    }

    public func rotate(itemID: CanvasItem.ID, degrees: Double) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].rotation = degrees
    }

    // MARK: Content edits

    public func setText(itemID: CanvasItem.ID, to text: String) {
        guard let index = index(of: itemID),
              case .text(var block) = memory.items[index].content else { return }
        block.text = text
        memory.items[index].content = .text(block)
    }

    public func setTextPointSize(itemID: CanvasItem.ID, to pointSize: CGFloat) {
        guard let index = index(of: itemID),
              case .text(var block) = memory.items[index].content else { return }
        beginChange()
        block.pointSize = pointSize
        memory.items[index].content = .text(block)
    }

    public func setTextColorName(itemID: CanvasItem.ID, to colorName: String) {
        guard let index = index(of: itemID),
              case .text(var block) = memory.items[index].content else { return }
        beginChange()
        block.colorName = colorName
        memory.items[index].content = .text(block)
    }

    public func setSoundNote(itemID: CanvasItem.ID, to note: String) {
        guard let index = index(of: itemID),
              case .sound(var clip) = memory.items[index].content else { return }
        beginChange()
        clip.note = note
        memory.items[index].content = .sound(clip)
    }

    // MARK: Element operations (long-press menu)

    @discardableResult
    public func duplicate(itemID: CanvasItem.ID) -> CanvasItem.ID? {
        guard let source = item(itemID) else { return nil }
        beginChange()
        let copy = CanvasItem(
            content: source.content,
            position: CGPoint(x: source.position.x + 16, y: source.position.y + 16),
            size: source.size,
            rotation: source.rotation,
            zIndex: topZ + 1
        )
        memory.items.append(copy)
        selectedItemID = copy.id
        return copy.id
    }

    public func delete(itemID: CanvasItem.ID) {
        guard let index = index(of: itemID) else { return }
        beginChange()
        memory.items.remove(at: index)
        if selectedItemID == itemID { selectedItemID = nil }
        if editingTextItemID == itemID { editingTextItemID = nil }
    }

    public func bringToFront(itemID: CanvasItem.ID) {
        guard let index = index(of: itemID) else { return }
        beginChange()
        memory.items[index].zIndex = topZ + 1
    }

    public func sendToBack(itemID: CanvasItem.ID) {
        guard let index = index(of: itemID) else { return }
        beginChange()
        memory.items[index].zIndex = bottomZ - 1
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

    // MARK: Private

    private func index(of id: CanvasItem.ID) -> Int? {
        memory.items.firstIndex { $0.id == id }
    }

    private var topZ: Int { memory.items.map(\.zIndex).max() ?? 0 }
    private var bottomZ: Int { memory.items.map(\.zIndex).min() ?? 0 }
}

extension Memory {
    /// The starter draft a new memory opens with: a serif title, a caption,
    /// an image placeholder, and a body line -- real elements the user can
    /// immediately move, edit, or delete.
    public static func starterDraft(title: String = "Lunch by the river") -> [CanvasItem] {
        [
            CanvasItem(
                content: .text(TextBlock(text: title, pointSize: 30)),
                position: CGPoint(x: 118, y: 46),
                size: CGSize(width: 200, height: 76),
                zIndex: 1
            ),
            CanvasItem(
                content: .text(TextBlock(text: "June 21 - calm afternoon", pointSize: 12, colorName: "textSecondary")),
                position: CGPoint(x: 106, y: 96),
                size: CGSize(width: 176, height: 24),
                zIndex: 2
            ),
            CanvasItem(
                content: .image(ImageRef(displayName: "placeholder")),
                position: CGPoint(x: 180, y: 226),
                size: CGSize(width: 328, height: 210),
                zIndex: 3
            ),
            CanvasItem(
                content: .text(TextBlock(text: "Sunny afternoon, tiny noodle shop by the bridge", pointSize: 15)),
                position: CGPoint(x: 160, y: 396),
                size: CGSize(width: 288, height: 66),
                zIndex: 4
            )
        ]
    }
}

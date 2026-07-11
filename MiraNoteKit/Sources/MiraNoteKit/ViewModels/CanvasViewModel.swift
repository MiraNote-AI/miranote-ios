import CoreGraphics
import Foundation
import Observation

/// The v2.1 canvas editor core: elements, selection, geometry, stacking,
/// and a snapshot undo stack. Views own gestures; whatever a user would
/// call "one change" is bracketed by beginChange() -- one undo per gesture.
@MainActor
@Observable
public final class CanvasViewModel {
    // internal(set): same-module extension files mutate items too
    // (CanvasViewModel+Stickers.swift); still read-only outside the Kit.
    public internal(set) var memory: Memory

    /// The currently selected element, if any (shows handles in the view).
    public var selectedItemID: CanvasItem.ID?

    /// The text element currently being edited in place, if any.
    public var editingTextItemID: CanvasItem.ID?

    /// Bumps per recorded mutation and undo (receipt honesty).
    public private(set) var changeCount = 0

    /// One undo step: the canvas elements plus the page background.
    private struct UndoSnapshot: Equatable {
        let items: [CanvasItem]
        let backgroundFileName: String
    }
    private var history: [UndoSnapshot] = []
    private var currentSnapshot: UndoSnapshot {
        UndoSnapshot(items: memory.items, backgroundFileName: memory.backgroundFileName)
    }
    private static let historyCap = 50

    public init(memory: Memory) {
        self.memory = memory
    }

    public var items: [CanvasItem] { memory.items }

    public var orderedItems: [CanvasItem] {
        memory.items.sorted { $0.zIndex < $1.zIndex }
    }

    public func item(_ id: CanvasItem.ID) -> CanvasItem? {
        memory.items.first { $0.id == id }
    }

    public var contentBottom: CGFloat {
        memory.items.map { $0.position.y + $0.size.height / 2 }.max() ?? 0
    }

    // MARK: Undo

    public var canUndo: Bool { !history.isEmpty }

    public func beginChange() {
        changeCount += 1
        history.append(currentSnapshot)
        if history.count > Self.historyCap {
            history.removeFirst()
        }
    }

    public func undo() {
        guard let snapshot = history.popLast() else { return }
        changeCount += 1
        memory.items = snapshot.items
        memory.backgroundFileName = snapshot.backgroundFileName
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

    /// One undo point per editing session (or none if the caller made
    /// one); re-entry never burns snapshots.
    public func startEditingText(_ id: CanvasItem.ID, recordingUndo: Bool = true) {
        guard editingTextItemID != id, case .text = item(id)?.content else { return }
        if recordingUndo { beginChange() }
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

    @discardableResult
    public func addImages(_ images: [ImageRef], around position: CGPoint,
                          size: CGSize = CGSize(width: 170, height: 150)) -> [CanvasItem.ID] {
        beginChange()
        var ids: [CanvasItem.ID] = []
        for (offset, image) in images.enumerated() {
            let shifted = CGPoint(x: position.x + CGFloat(offset) * 24, y: position.y + CGFloat(offset) * 24)
            let item = CanvasItem(
                content: .image(image),
                position: shifted,
                size: size,
                zIndex: topZ + 1 + offset
            )
            memory.items.append(item)
            ids.append(item.id)
        }
        return ids
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

    public var canvasWidth: CGFloat?

    public func move(itemID: CanvasItem.ID, to position: CGPoint) {
        guard let index = index(of: itemID) else { return }
        var clamped = position
        clamped.y = max(24, clamped.y)
        if let width = canvasWidth, width > 48 {
            clamped.x = min(max(24, clamped.x), width - 24)
        }
        memory.items[index].position = clamped
    }

    public func resize(itemID: CanvasItem.ID, to size: CGSize) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].size = CGSize(
            width: max(44, size.width),
            height: max(36, size.height)
        )
    }

    /// Measured text height, TOP anchored; continuous, no undo step.
    public func autosizeTextHeight(itemID: CanvasItem.ID, to height: CGFloat) {
        guard let index = index(of: itemID),
              case .text = memory.items[index].content else { return }
        let old = memory.items[index].size.height
        let clamped = max(36, height)
        guard abs(old - clamped) > 0.5 else { return }
        memory.items[index].size.height = clamped
        memory.items[index].position.y += (clamped - old) / 2
    }

    public func rotate(itemID: CanvasItem.ID, degrees: Double) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].rotation = degrees
    }
}

// MARK: - Content edits

extension CanvasViewModel {
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

    /// Vision metadata from import-time describe. Silent: no undo step,
    /// no changeCount bump (receipts stay honest).
    public func setImageSummary(itemID: CanvasItem.ID, to summary: String) {
        guard let index = index(of: itemID),
              case .image(var ref) = memory.items[index].content else { return }
        ref.summary = summary
        memory.items[index].content = .image(ref)
    }

    public func setImageFilter(itemID: CanvasItem.ID, to filterName: String) {
        guard let index = index(of: itemID),
              case .image(var ref) = memory.items[index].content,
              ref.filterName != filterName else { return }
        beginChange()
        ref.filterName = filterName
        memory.items[index].content = .image(ref)
    }

    public func setImageFrame(itemID: CanvasItem.ID, to frameName: String) {
        guard let index = index(of: itemID),
              case .image(var ref) = memory.items[index].content,
              ref.frameName != frameName else { return }
        beginChange()
        ref.frameName = frameName
        memory.items[index].content = .image(ref)
    }

    /// "Make sticker": the photo element becomes a sticker in place (one
    /// undo step returns the photo).
    /// AI edit: new pixels in place; stale filter clears; one undo back.
    public func replaceImageFile(itemID: CanvasItem.ID, fileName: String) {
        guard let index = index(of: itemID),
              case .image(var ref) = memory.items[index].content else { return }
        beginChange()
        ref.fileName = fileName
        ref.filterName = ""
        memory.items[index].content = .image(ref)
    }

    public func setSoundNote(itemID: CanvasItem.ID, to note: String) {
        guard let index = index(of: itemID),
              case .sound(var clip) = memory.items[index].content else { return }
        beginChange()
        clip.note = note
        memory.items[index].content = .sound(clip)
    }
}

// MARK: - Element operations

extension CanvasViewModel {
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

    /// Removes an abandoned husk (e.g. an empty text block) without
    /// recording an undo step, then drops any trailing history snapshots
    /// identical to the result so undo never "restores" the husk state.
    public func discardAbandonedText(itemID: CanvasItem.ID) {
        guard let index = index(of: itemID) else { return }
        memory.items.remove(at: index)
        if selectedItemID == itemID { selectedItemID = nil }
        if editingTextItemID == itemID { editingTextItemID = nil }
        while let last = history.last, last == currentSnapshot {
            history.removeLast()
        }
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

    /// Filed-on-Done shape: title = most prominent text (v2.1 "the visual
    /// title IS a text element"), body = remaining text in reading order.
    public func composedMemory(defaultTitle: String = "New memory") -> Memory {
        var composed = memory
        let textBlocks: [(block: TextBlock, item: CanvasItem)] = memory.items.compactMap {
            guard case .text(let block) = $0.content,
                  !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (block, $0)
        }
        let titleEntry = textBlocks
            .sorted { lhs, rhs in
                if lhs.block.pointSize != rhs.block.pointSize {
                    return lhs.block.pointSize > rhs.block.pointSize
                }
                return lhs.item.position.y < rhs.item.position.y
            }
            .first
        // No text: keep the archive name (open+close must never rename).
        let fallbackTitle = memory.title.isEmpty ? defaultTitle : memory.title
        composed.title = titleEntry.map { String($0.block.text.prefix(48)) } ?? fallbackTitle
        // The title block is the name, not prose -- keep it out of body.
        let bodyBlocks = textBlocks.filter { $0.item.id != titleEntry?.item.id }
        composed.body = textBlocks.isEmpty
            ? memory.body
            : bodyBlocks
                .sorted { $0.item.position.y < $1.item.position.y }
                .map(\.block.text)
                .joined(separator: "\n\n")
        composed.savedAt = .now
        return composed
    }

    /// Tidy: one calm column -- title first, then top-to-bottom; gaps
    /// from REAL heights (no overlap); tilt resets. Deterministic.
    public func quickOrganize(canvasWidth: CGFloat, spacing: CGFloat = 24) {
        beginChange()
        func sortKey(_ item: CanvasItem) -> (Int, CGFloat) {
            if case .text(let block) = item.content, block.pointSize >= 24 {
                return (0, item.position.y - item.size.height / 2)
            }
            return (1, item.position.y - item.size.height / 2)
        }
        let orderedIDs = memory.items
            .sorted { sortKey($0) < sortKey($1) }
            .map(\.id)

        var nextTop: CGFloat = 28
        for id in orderedIDs {
            guard let itemIndex = index(of: id) else { continue }
            let size = memory.items[itemIndex].size
            memory.items[itemIndex].position = CGPoint(
                x: canvasWidth / 2,
                y: nextTop + size.height / 2
            )
            memory.items[itemIndex].rotation = 0
            nextTop += size.height + spacing
        }
    }

    // MARK: Private

    /// Internal (not private) so same-module extension files can mutate
    /// items too (CanvasViewModel+Stickers.swift).
    func index(of id: CanvasItem.ID) -> Int? {
        memory.items.firstIndex { $0.id == id }
    }

    private var topZ: Int { memory.items.map(\.zIndex).max() ?? 0 }
    private var bottomZ: Int { memory.items.map(\.zIndex).min() ?? 0 }
}

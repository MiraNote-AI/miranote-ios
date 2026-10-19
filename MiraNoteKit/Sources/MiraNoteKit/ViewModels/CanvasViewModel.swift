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
    public var editingTextItemID: CanvasItem.ID? {
        didSet {
            if editingTextItemID == nil {
                sessionSteps = nil
                sessionOrigin = nil
                sessionNeedsStart = false
                typingNeedsStep = false
            }
        }
    }

    /// A step was recorded while writing (Mira's title landing, a size):
    /// words typed after it record a step of their own, so one Undo never
    /// takes back that step and the words typed since.
    private var typingNeedsStep = false

    /// An undo took the session's starting point back while the session
    /// goes on: its next change (a word typed, a style) records a new one,
    /// so that change is undoable and Cancel takes it back.
    private var sessionNeedsStart = false

    /// Undo steps recorded since the open text editing session began, so
    /// Cancel can take the whole session back. Nil when no session is open,
    /// or when its starting point was undone or fell off the history cap.
    private var sessionSteps: Int?

    /// The edited block as it was when the session began; nil for a block
    /// the session made. Cancel puts back only this element: whatever else
    /// landed meanwhile (a Mira backdrop, a photo AI edit) is not the
    /// session's to take back.
    private var sessionOrigin: CanvasItem?

    /// Bumps per recorded mutation and undo (receipt honesty).
    public private(set) var changeCount = 0

    /// The page as it was before a live page color preview, while one is
    /// shown: the autosave files this, not a color nobody applied.
    var pagePreviewOrigin: PageLook?

    /// One undo step: the canvas elements plus the page background.
    // The backdrop and its description travel together: restoring one
    // without the other leaves the page describing a picture it lost.
    private struct UndoSnapshot: Equatable {
        let items: [CanvasItem]
        let backgroundFileName: String
        let backgroundSummary: String
        let paper: PaperKind
        let pageColorName: String

        /// The same page without one element.
        func removingItem(_ id: CanvasItem.ID) -> UndoSnapshot {
            replacingItems(items.filter { $0.id != id })
        }

        /// The same page with other elements.
        func replacingItems(_ items: [CanvasItem]) -> UndoSnapshot {
            UndoSnapshot(items: items, backgroundFileName: backgroundFileName, backgroundSummary: backgroundSummary,
                         paper: paper, pageColorName: pageColorName)
        }

        /// Equal as far as the user's edits go: a photo's description lands
        /// later without an undo step, so it never sets two steps apart.
        func sameEdits(as other: UndoSnapshot) -> Bool {
            withoutPhotoDescriptions == other.withoutPhotoDescriptions
        }

        private var withoutPhotoDescriptions: UndoSnapshot {
            UndoSnapshot(
                items: items.map { item in
                    guard case .image(var ref) = item.content else { return item }
                    var plain = item
                    ref.summary = ""
                    plain.content = .image(ref)
                    return plain
                },
                backgroundFileName: backgroundFileName, backgroundSummary: backgroundSummary,
                paper: paper, pageColorName: pageColorName
            )
        }
    }
    private var history: [UndoSnapshot] = []
    /// Steps undone since the last change, newest last; any new change
    /// drops them (a redo after an edit would rewrite the edit away).
    private var future: [UndoSnapshot] = []
    private var currentSnapshot: UndoSnapshot {
        UndoSnapshot(items: memory.items, backgroundFileName: memory.backgroundFileName,
                     backgroundSummary: memory.backgroundSummary,
                     paper: memory.paper, pageColorName: memory.pageColorName)
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

    /// Nothing the user made or chose: no elements, no painting, no page
    /// color, plain paper. Only such a page is dropped on leaving.
    public var isBlankPage: Bool {
        // The look the autosave files: not a color only previewed.
        let look = pagePreviewOrigin ?? pageLook
        return filedItems.isEmpty && look.backgroundFileName.isEmpty
            && look.pageColorName.isEmpty && memory.paper == .blank
    }

    /// The elements a filing keeps: not an empty block still being written
    /// (one waiting for dictated words when the app is backgrounded) -- the
    /// session's end removes it unless words land.
    private var filedItems: [CanvasItem] {
        memory.items.filter { !($0.id == editingTextItemID && $0.isEmptyText) }
    }

    public var contentBottom: CGFloat {
        memory.items.map { $0.position.y + $0.size.height / 2 }.max() ?? 0
    }

    // MARK: Undo

    public var canUndo: Bool { !history.isEmpty }

    /// How many steps undo can take back (a -UITEST probe reads it).
    public var undoDepth: Int { history.count }

    public var canRedo: Bool { !future.isEmpty }

    public func beginChange() {
        changeCount += 1
        future.removeAll()
        pushHistory(currentSnapshot)
        if editingTextItemID != nil { typingNeedsStep = true }
    }

    public func undo() {
        guard let snapshot = history.popLast() else { return }
        if let steps = sessionSteps {
            sessionSteps = steps > 0 ? steps - 1 : nil
            sessionNeedsStart = steps == 0
        }
        // An empty block being written that this undo takes off goes for
        // good: no redo brings back a husk outside its session.
        if let editing = editingTextItemID, item(editing)?.isEmptyText == true,
           !snapshot.items.contains(where: { $0.id == editing }) {
            let undone = currentSnapshot.removingItem(editing)
            if !undone.sameEdits(as: snapshot) { future.append(undone) }
        } else {
            future.append(currentSnapshot)
        }
        restore(snapshot)
        // The block as this undo left it is what Cancel takes it back to
        // (not a live preview the next change may find on it).
        if sessionNeedsStart, let editing = editingTextItemID { sessionOrigin = item(editing) }
    }

    /// Re-applies the step the last undo took back (handoff screens 32-34).
    public func redo() {
        guard let snapshot = future.popLast() else { return }
        pushHistory(currentSnapshot)
        restore(snapshot)
    }

    private func pushHistory(_ snapshot: UndoSnapshot) {
        let restarting = sessionNeedsStart && editingTextItemID != nil
        history.append(snapshot)
        if history.count > Self.historyCap {
            history.removeFirst()
        }
        if restarting {
            // The page before this change starts the session anew.
            sessionNeedsStart = false
            sessionSteps = 0
        } else if let steps = sessionSteps {
            sessionSteps = steps + 1 < history.count ? steps + 1 : nil
        }
    }

    private func restore(_ snapshot: UndoSnapshot) {
        changeCount += 1
        // A step taken while a new block was still empty: the block, words
        // since typed away, is a husk outside its session -- it goes, or it
        // would be filed as an empty block.
        memory.items = snapshot.items.filter { !$0.isEmptyText || $0.id == editingTextItemID }
        memory.backgroundFileName = snapshot.backgroundFileName
        memory.backgroundSummary = snapshot.backgroundSummary
        memory.paper = snapshot.paper
        memory.pageColorName = snapshot.pageColorName
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
        // The undo point on top of the history (this call's, or the one the
        // caller made) is the page as it was before the session.
        sessionSteps = history.isEmpty ? nil : 0
        sessionOrigin = history.last?.items.first { $0.id == id }
        sessionNeedsStart = false
        // The session's start is the typing's undo point.
        typingNeedsStep = false
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
        size: CGSize = CGSize(width: 220, height: 84),
        fontName: String = "",
        colorName: String = "ink"
    ) -> CanvasItem.ID {
        beginChange()
        let item = CanvasItem(
            content: .text(TextBlock(text: text, pointSize: pointSize, colorName: colorName, fontName: fontName)),
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

    @discardableResult
    public func addSticker(_ sticker: GeneratedSticker, at position: CGPoint) -> CanvasItem.ID {
        beginChange()
        let item = CanvasItem(content: .sticker(sticker), position: position,
                              size: CGSize(width: 88, height: 88), zIndex: topZ + 1)
        memory.items.append(item)
        return item.id
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
        // A new place: no fit lifts the element above it.
        memory.items[index].fitOffset = nil
    }

    /// Slides an element down by `offset` with the page (a Mira title making
    /// room): not a new place, so what fits pushed it stays theirs to take
    /// back.
    func slide(itemID: CanvasItem.ID, by offset: CGFloat) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].position.y += offset
    }

    public func resize(itemID: CanvasItem.ID, to size: CGSize) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].size = CGSize(
            width: max(44, size.width),
            height: max(36, size.height)
        )
        // A box sized by hand: what is below clears it as it stands, and its
        // earlier pushes are no longer its to take back (as after Tidy).
        memory.items[index].clearance = nil
    }

    /// Measured text height, TOP anchored; continuous, no undo step. A block
    /// that grows pushes what is below it down in the same change (TextFit),
    /// and one that shrinks takes that push back, so the step that records
    /// the growth records the push too.
    public func autosizeTextHeight(itemID: CanvasItem.ID, to height: CGFloat) {
        guard let index = index(of: itemID),
              case .text = memory.items[index].content else { return }
        let clamped = max(36, height)
        guard abs(memory.items[index].size.height - clamped) > 0.5 else { return }
        memory.items = TextFit.apply(to: memory.items) { $0.id == itemID ? clamped : nil }
    }

    public func rotate(itemID: CanvasItem.ID, degrees: Double) {
        guard let index = index(of: itemID) else { return }
        memory.items[index].rotation = degrees
    }
}

// MARK: - Previews

extension CanvasViewModel {
    /// Changes previewed live without undo steps (an AI rewrite, a custom
    /// color being dragged) become one undo step back to `original`; none
    /// when the item ends up unchanged. That step takes back the item and
    /// what its growth pushed (like Cancel), not what other actions moved
    /// meanwhile.
    public func commitPreview(of original: CanvasItem) {
        guard item(original.id) != nil else { return }
        let previewed = memory.items
        let before = TextFit.revert(previewed, box: original.id, to: original)
        guard before != previewed else { return }
        memory.items = before
        beginChange()
        memory.items = previewed
    }

    /// Drops a live preview: the item as it was and what its growth pushed
    /// taken back (a longer rewrite pushed the photo below), no undo step.
    public func discardPreview(of original: CanvasItem) {
        guard item(original.id) != nil else { return }
        memory.items = TextFit.revert(memory.items, box: original.id, to: original)
    }
}

// MARK: - Text session Cancel

extension CanvasViewModel {
    /// The header's Cancel: ends the session and takes the edited block back
    /// to how it was when the session began -- words, style and, for a new
    /// block, the block itself -- and what its growth pushed back up. Other
    /// elements and the page keep what landed meanwhile, and whatever moved
    /// them (a Mira title sliding the page down, a drag) -- the block too
    /// stays where they moved it. The session's undo steps lose the block's
    /// edits; a step left with nothing else in it goes.
    public func cancelEditingText() {
        guard let id = editingTextItemID else { return }
        if let steps = sessionSteps, steps < history.count {
            let origin = sessionOrigin
            func reverted(_ items: [CanvasItem]) -> [CanvasItem] {
                TextFit.revert(items, box: id, to: origin)
            }
            memory.items = reverted(memory.items)
            changeCount += 1
            // The session's steps plus its starting point, newest first:
            // each loses the block's edits, and one that then matches the
            // page above it recorded nothing else.
            var next = currentSnapshot
            var kept: [UndoSnapshot] = []
            for snapshot in history.suffix(steps + 1).reversed() {
                let step = snapshot.replacingItems(reverted(snapshot.items))
                if !step.sameEdits(as: next) {
                    kept.insert(step, at: 0)
                    next = step
                }
            }
            history.removeLast(steps + 1)
            history += kept
            // Nothing of a cancelled session comes back by redo.
            future.removeAll()
        }
        editingTextItemID = nil
        if selectedItemID == id, item(id) == nil { selectedItemID = nil }
    }
}

// MARK: - Content edits

extension CanvasViewModel {
    // MARK: Content edits

    public func setText(itemID: CanvasItem.ID, to text: String) {
        guard let index = index(of: itemID),
              case .text(var block) = memory.items[index].content else { return }
        // Typing records no step of its own: the session's start is its
        // undo point. After an undo past that start, or a step recorded
        // since (Mira's title), the first words typed record one.
        if sessionNeedsStart || typingNeedsStep, itemID == editingTextItemID, block.text != text {
            beginChange()
            typingNeedsStep = false
        }
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

    /// A palette name or "#RRGGBB". Pass `recordingUndo: false` for the live
    /// updates of a color picker drag, after one recorded call, so the whole
    /// drag is a single undo step.
    public func setTextColorName(itemID: CanvasItem.ID, to colorName: String, recordingUndo: Bool = true) {
        guard let index = index(of: itemID),
              case .text(var block) = memory.items[index].content else { return }
        if recordingUndo { beginChange() }
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

    /// Photo edit revert: the photo as it was when editing began -- pixels,
    /// filter and frame -- in one undo step; none if unchanged. The summary
    /// follows the pixels: same file, the current (possibly newer) summary
    /// stays.
    public func restoreImage(itemID: CanvasItem.ID, to original: ImageRef) {
        guard let index = index(of: itemID),
              case .image(let ref) = memory.items[index].content else { return }
        var restored = original
        if ref.fileName == original.fileName {
            restored.summary = ref.summary
        }
        guard ref != restored else { return }
        beginChange()
        memory.items[index].content = .image(restored)
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

    /// Takes several elements off the page as ONE undo step (the Image
    /// tool's Cancel takes back the photos it placed); ids no longer on the
    /// page are ignored, and nothing is recorded when none are.
    public func remove(itemIDs: [CanvasItem.ID]) {
        let ids = Set(itemIDs)
        guard memory.items.contains(where: { ids.contains($0.id) }) else { return }
        beginChange()
        memory.items.removeAll { ids.contains($0.id) }
        if let selected = selectedItemID, ids.contains(selected) { selectedItemID = nil }
        if let editing = editingTextItemID, ids.contains(editing) { editingTextItemID = nil }
    }

    /// Removes an abandoned husk (e.g. an empty text block) without
    /// recording an undo step, and takes it out of the trailing history
    /// snapshots taken while it was empty, so undo never "restores" a husk.
    /// Steps that then change nothing -- style taps on the empty block, the
    /// step that added it -- go; one that also changed something else (a
    /// photo moved meanwhile) stays, without the husk. A step where the
    /// block still had words is kept: emptying a written block stays
    /// undoable. Photo descriptions, which land without an undo step, never
    /// make a step count as a change (#101).
    public func discardAbandonedText(itemID: CanvasItem.ID) {
        guard let index = index(of: itemID) else { return }
        memory.items.remove(at: index)
        if selectedItemID == itemID { selectedItemID = nil }
        if editingTextItemID == itemID { editingTextItemID = nil }
        // Undone steps were taken with the husk on the page: redoing one
        // would bring it back.
        future.removeAll()
        var next = currentSnapshot
        var kept: [UndoSnapshot] = []
        while let last = history.last, last.items.contains(where: { $0.id == itemID && $0.isEmptyText }) {
            history.removeLast()
            let step = last.removingItem(itemID)
            if !step.sameEdits(as: next) {
                kept.insert(step, at: 0)
                next = step
            }
        }
        while let last = history.last, last.sameEdits(as: next) {
            history.removeLast()
        }
        history += kept
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
        composed.items = filedItems
        if let origin = pagePreviewOrigin {
            composed.pageColorName = origin.pageColorName
            composed.backgroundFileName = origin.backgroundFileName
            composed.backgroundSummary = origin.backgroundSummary
        }
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
            if case .text(let block) = item.content, block.pointSize >= Self.displayPointSize {
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
            // A new layout: no earlier push is left to take back.
            memory.items[itemIndex].clearance = nil
            memory.items[itemIndex].fitOffset = nil
            nextTop += size.height + spacing
        }
    }

    // MARK: Private

    /// Internal (not private) so same-module extension files can mutate
    /// items too (CanvasViewModel+Stickers.swift).
    func index(of id: CanvasItem.ID) -> Int? {
        memory.items.firstIndex { $0.id == id }
    }

    // Internal so +PageEdits can restack without the snapshotting helpers.
    var topZ: Int { memory.items.map(\.zIndex).max() ?? 0 }
    var bottomZ: Int { memory.items.map(\.zIndex).min() ?? 0 }
}

private extension CanvasItem {
    /// A text block with no words yet -- a husk if abandoned.
    var isEmptyText: Bool {
        if case .text(let block) = content {
            return block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}

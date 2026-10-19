import CoreGraphics
import Foundation
@testable import MiraNoteKit

/// The canvas editor (CanvasViewModel + TextFit) driven the way the canvas
/// scene drives it: a writing session's typing autosizes its block, every
/// recorded change re-measures every block, a session that ends keeps its
/// open previews and drops empty blocks, and Mira lands things mid-session.
///
/// Invariants, after every step:
/// - a fit (autosize, re-measure, Cancel, a committed preview) never creates
///   an overlap that was not there before it;
/// - an element the user moved is never moved up by a later fit: what was
///   pushed before the move is not the box's to take back any more;
/// - toggle pairs (grow then shrink back, a curated set, another, the first
///   again, words typed then erased, a rewrite then Original) leave every
///   element exactly where it was;
/// - Cancel takes the edited block back to its session start and takes back
///   only its own pushes: with nothing else done meanwhile the page is the
///   session's starting page exactly;
/// - Mira's Revert undoes Mira's change only, and only while it is the
///   newest thing on the page;
/// - the page survives a JSON round trip unchanged; ids are unique; the
///   edited and selected elements exist.
/// At the end of a sequence: undo all the way back reproduces the starting
/// page (or the page as last reloaded).
@MainActor
final class CanvasSequenceModel: SequenceModel {
    enum Action {
        // The Text tool: a new empty block and its writing session.
        case addText(x: Int, y: Int, width: Int)
        case addPhoto(x: Int, y: Int, width: Int, height: Int)
        case addSticker(x: Int, y: Int)
        case delete(Int)
        // A drag (one step), and a pinch (one step).
        case move(Int, dx: Int, dy: Int)
        case resize(Int, dw: Int, dh: Int)
        // Writing: tap a block, type, erase, size, the AI row, the color sheet.
        case startSession(Int)
        case type(words: Int)
        case erase(chars: Int)
        case pointSize(Int)
        case openRewrite
        case showRewrite(words: Int)
        case showOriginal
        case colorPreview(Int)
        case colorApply
        case colorDrop
        case done
        case cancel
        // Background tool.
        case curatedSet(Int)
        // Toggle pairs, checked to return every element exactly.
        case toggleSets(Int, Int)
        case toggleFit(Int, delta: Int)
        case toggleTyping(words: Int)
        case toggleRewrite(words: Int)
        // Mira landing work mid-anything (beginChange edits of her own).
        case miraTitle
        case miraMove(Int, top: Int)
        case miraBackground
        case miraRevert
        case undo
        case redo
        case saveReload
    }

    static let pageWidth: CGFloat = 390
    private static let vocabulary = ["lunch", "by", "the", "river,", "then", "a", "long", "walk", "home",
                                     "with", "Sam", "under", "golden", "light", "and", "noodles"]
    private static let colors = ["#D1E0F0", "#8B5962", "#2D372C", "ink"]

    private(set) var editor: CanvasViewModel
    private let mira = MiraCanvasCoordinator(text: MockTextTransformService(), chat: MockChatService(),
                                             imageStudio: MockImageStudioService())
    /// What undoing everything must give back.
    private var baseline: [CanvasItem]
    /// The AI row's original (the scene's RewriteState.original), and the
    /// color sheet's.
    private var rewrite: CanvasItem?
    private var colorSheet: CanvasItem?
    private var session: SessionRecord?
    /// Per user-moved element: how far fits have moved its top since.
    private var drift: [CanvasItem.ID: CGFloat] = [:]
    /// Mira's latest landing, for checking Revert.
    private var miraLanding: (page: [CanvasItem], changeCount: Int)?
    /// At most this many undo steps since the baseline; once it reaches the
    /// history cap, the oldest may be gone and undo cannot reach the start.
    private var historyDepth = 0
    private var historyCapped = false
    /// A step something else recorded while the color sheet previewed a
    /// color: that step's snapshot holds the preview, so undoing past it can
    /// bring back a color only previewed (known, narrow; text color only).
    private var previewInHistory = false
    private var problems: [String] = []

    private struct SessionRecord {
        let id: CanvasItem.ID
        /// The page right before the session began (without a new block).
        let startPage: [CanvasItem]
        /// What Cancel takes the block back to: as the session found it, or
        /// as an undo inside the session left it (the session starts again
        /// there); nil for a block the session made.
        var origin: CanvasItem?
        /// Only the session's own actions since it began.
        var pure = true
        /// Undo steps recorded above the session's start; an undo with none
        /// takes the start back, and the session starts again at its next
        /// recorded change (`restartPending` until then).
        var depth = 0
        var restartPending = false

        init(id: CanvasItem.ID, startPage: [CanvasItem]) {
            self.id = id
            self.startPage = startPage
            origin = startPage.first { $0.id == id }
        }

        /// `steps` changes recorded inside the session.
        mutating func recorded(_ steps: Int) {
            guard steps > 0 else { return }
            if restartPending {
                // The first of them is the new start.
                restartPending = false
                depth = steps - 1
            } else {
                depth += steps
            }
        }

        /// An undo; `block` is the session's block as it left it.
        mutating func undone(leaving block: CanvasItem?) {
            if restartPending || depth == 0 {
                restartPending = true
                origin = block
            } else {
                depth -= 1
            }
        }

        mutating func redone() {
            if restartPending {
                restartPending = false
                depth = 0
            } else {
                depth += 1
            }
        }
    }

    /// An undo (the header's, or Mira's Revert) inside the session.
    private func noteUndo(_ undo: () -> Void) {
        let editing = editor.editingTextItemID
        let had = editor.canUndo
        undo()
        guard had, let id = editing, editor.editingTextItemID == id, session?.id == id else { return }
        session?.undone(leaving: editor.item(id))
    }

    /// Previews kept before an undo or redo are steps of the session.
    private func keepPreviewsCounting() {
        let count = editor.changeCount
        keepPreviews()
        if editor.editingTextItemID != nil { session?.recorded(editor.changeCount - count) }
    }

    init(seed: UInt64) async {
        var rng = SeededRandom(seed: seed ^ 0xC0FFEE)
        var items: [CanvasItem] = []
        var top: CGFloat = 40
        for index in 0..<rng.int(2...5) {
            let width = CGFloat(rng.int(120...330))
            let x = CGFloat(rng.int(Int(width / 2)...Int(Self.pageWidth - width / 2)))
            let height: CGFloat
            let content: CanvasItem.Content
            switch rng.int(0...3) {
            case 0, 1:
                let words = Self.words(rng.int(0...24), from: index)
                content = .text(TextBlock(text: words.isEmpty ? "hi" : words, pointSize: [15, 17, 30][rng.int(0...2)]))
                height = 60
            case 2:
                content = .image(ImageRef(displayName: "photo \(index)"))
                height = CGFloat(rng.int(80...220))
            default:
                content = .sticker(GeneratedSticker(prompt: "s\(index)", symbolName: "sun.max"))
                height = 88
            }
            items.append(CanvasItem(content: content, position: CGPoint(x: x, y: top + height / 2),
                                    size: CGSize(width: width, height: height), zIndex: index))
            top += height + CGFloat(rng.int(-20...40))
        }
        editor = CanvasViewModel(memory: Memory(items: items))
        editor.canvasWidth = Self.pageWidth
        // The page as the editor opens it: measured once (no undo step).
        editor.fitTextHeights(Self.height)
        baseline = editor.items
    }

    // MARK: Measure

    /// A deterministic stand-in for TextMeasure: lines from the words, the
    /// face and the box width.
    nonisolated static func height(_ item: CanvasItem) -> CGFloat? {
        guard case .text(let block) = item.content else { return nil }
        let face = CGFloat(block.fontName.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7)
        let glyph = block.pointSize * (0.45 + face * 0.03)
        let perLine = max(1, Int((item.size.width - 24) / glyph))
        let lines = max(1, (block.text.count + perLine - 1) / perLine)
        return max(36, CGFloat(lines) * (block.pointSize * 1.3).rounded() + 16)
    }

    private static func words(_ count: Int, from start: Int) -> String {
        (0..<count).map { vocabulary[(start + $0) % vocabulary.count] }.joined(separator: " ")
    }

    // MARK: Generation

    func nextAction(_ rng: inout SeededRandom) -> Action {
        let count = max(1, editor.items.count)
        let any = { (rng: inout SeededRandom) in rng.int(0...count - 1) }
        let writing = editor.editingTextItemID != nil
        let options: [(Int, Int)] = [
            (0, writing ? 1 : 5), (1, 3), (2, 2), (3, 2), (4, 8), (5, 3),
            (6, writing ? 2 : 10), (7, writing ? 14 : 0), (8, writing ? 8 : 0), (9, writing ? 2 : 0),
            (10, writing && rewrite == nil ? 3 : 0), (11, rewrite != nil ? 6 : 0), (12, rewrite != nil ? 3 : 0),
            (13, writing ? 2 : 0), (14, colorSheet != nil ? 2 : 0), (15, colorSheet != nil ? 2 : 0),
            (16, writing ? 6 : 0), (17, writing ? 5 : 0), (18, writing ? 0 : 3), (19, writing ? 0 : 3),
            (20, 4), (21, writing ? 4 : 0), (22, rewrite != nil ? 3 : 0), (23, 2), (24, 3), (25, 1),
            (26, 2), (27, 7), (28, 3), (29, writing ? 1 : 2)
        ]
        switch rng.pick(options) {
        case 0: return .addText(x: rng.int(80...310), y: rng.int(40...700), width: rng.int(120...330))
        case 1: return .addPhoto(x: rng.int(80...310), y: rng.int(40...800), width: rng.int(90...300),
                                 height: rng.int(60...240))
        case 2: return .addSticker(x: rng.int(40...350), y: rng.int(40...800))
        case 3: return .delete(any(&rng))
        case 4: return .move(any(&rng), dx: rng.int(-120...120), dy: rng.int(-200...200))
        case 5: return .resize(any(&rng), dw: rng.int(-80...80), dh: rng.int(-60...60))
        case 6: return .startSession(any(&rng))
        case 7: return .type(words: rng.int(1...14))
        case 8: return .erase(chars: rng.int(1...60))
        case 9: return .pointSize(rng.int(0...3))
        case 10: return .openRewrite
        case 11: return .showRewrite(words: rng.int(0...40))
        case 12: return .showOriginal
        case 13: return .colorPreview(rng.int(0...3))
        case 14: return .colorApply
        case 15: return .colorDrop
        case 16: return .done
        case 17: return .cancel
        case 18: return .curatedSet(rng.int(0...7))
        case 19: return .toggleSets(rng.int(0...7), rng.int(0...7))
        case 20: return .toggleFit(any(&rng), delta: rng.int(-40...60))
        case 21: return .toggleTyping(words: rng.int(1...20))
        case 22: return .toggleRewrite(words: rng.int(0...40))
        case 23: return .miraTitle
        case 24: return .miraMove(any(&rng), top: rng.int(20...900))
        case 25: return .miraBackground
        case 26: return .miraRevert
        case 27: return .undo
        case 28: return .redo
        default: return .saveReload
        }
    }

    // MARK: Applying

    private func element(_ index: Int) -> CanvasItem? {
        let items = editor.items
        return items.isEmpty ? nil : items[((index % items.count) + items.count) % items.count]
    }

    private func textElement(_ index: Int) -> CanvasItem? {
        let texts = editor.items.filter { if case .text = $0.content { return true } else { return false } }
        return texts.isEmpty ? nil : texts[((index % texts.count) + texts.count) % texts.count]
    }

    private var editingBlock: (id: CanvasItem.ID, block: TextBlock)? {
        guard let id = editor.editingTextItemID, case .text(let block) = editor.item(id)?.content else { return nil }
        return (id, block)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func apply(_ action: Action) async {
        let changeBefore = editor.changeCount
        var editingBefore = editor.editingTextItemID
        var pageBefore = editor.items
        if !isSessionOwn(action) { session?.pure = false }
        switch action {
        case let .addText(x, y, width):
            guard editor.editingTextItemID == nil else { break }
            let id = editor.addText("", at: CGPoint(x: x, y: y), size: CGSize(width: width, height: 60))
            editor.startEditingText(id, recordingUndo: false)
        case let .addPhoto(x, y, width, height):
            editor.addImages([ImageRef(displayName: "added")], around: CGPoint(x: x, y: y),
                             size: CGSize(width: width, height: height))
        case let .addSticker(x, y):
            editor.addSticker(GeneratedSticker(prompt: "added", symbolName: "star"), at: CGPoint(x: x, y: y))
        case .delete(let index):
            guard let item = element(index), item.id != editor.editingTextItemID else { break }
            editor.delete(itemID: item.id)
        case let .move(index, dx, dy):
            // The block being written has no drag or handles (the board).
            guard let item = element(index), item.id != editor.editingTextItemID else { break }
            editor.beginChange()
            editor.move(itemID: item.id, to: CGPoint(x: item.position.x + CGFloat(dx), y: item.position.y + CGFloat(dy)))
            drift[item.id] = 0
        case let .resize(index, dw, dh):
            guard let item = element(index), item.id != editor.editingTextItemID else { break }
            // The corner handle: a resize around the opposite corner.
            editor.beginChange()
            editor.resize(itemID: item.id, to: CGSize(width: item.size.width + CGFloat(dw),
                                                      height: item.size.height + CGFloat(dh)))
            editor.move(itemID: item.id, to: CGPoint(x: item.position.x + CGFloat(dw) / 2,
                                                     y: item.position.y + CGFloat(dh) / 2))
            drift[item.id] = 0
        case .startSession(let index):
            guard let item = textElement(index), item.id != editor.editingTextItemID else { break }
            if editor.editingTextItemID != nil {
                // Another block's menu takes the keyboard down first: the
                // scene ends this writing (as Done) before the new one.
                keepPreviews()
                editor.endEditingText()
                sceneReactions(changeBefore: changeBefore, editingBefore: editingBefore, pageBefore: pageBefore)
                editingBefore = nil
                pageBefore = editor.items
            }
            editor.startEditingText(item.id)
        case .type(let words):
            // The color sheet takes the keyboard down.
            guard colorSheet == nil, let (id, block) = editingBlock else { break }
            let added = Self.words(words, from: block.text.count)
            editor.setText(itemID: id, to: block.text.isEmpty ? added : block.text + " " + added)
            autosizeEditing()
        case .erase(let chars):
            guard colorSheet == nil, let (id, block) = editingBlock else { break }
            editor.setText(itemID: id, to: String(block.text.dropLast(chars)))
            autosizeEditing()
        case .pointSize(let index):
            // The sheet and the AI row each take the tool row's place.
            guard colorSheet == nil, rewrite == nil, let (id, _) = editingBlock else { break }
            editor.setTextPointSize(itemID: id, to: [15, 17, 24, 30][index % 4])
            autosizeEditing()
        case .openRewrite:
            guard rewrite == nil, colorSheet == nil, let (id, _) = editingBlock else { break }
            rewrite = editor.item(id)
        case .showRewrite(let words):
            showRewrite(Self.words(words, from: 3))
        case .showOriginal:
            guard let original = rewrite, case .text(let block) = original.content else { break }
            showRewrite(block.text)
        case .colorPreview(let index):
            guard rewrite == nil, let (id, _) = editingBlock else { break }
            if colorSheet == nil { colorSheet = editor.item(id) }
            editor.setTextColorName(itemID: id, to: Self.colors[index % Self.colors.count], recordingUndo: false)
        case .colorApply:
            guard let original = colorSheet else { break }
            colorSheet = nil
            fit("color apply") { editor.commitPreview(of: original) }
        case .colorDrop:
            guard let original = colorSheet, case .text(let block) = original.content else { break }
            colorSheet = nil
            editor.setTextColorName(itemID: original.id, to: block.colorName, recordingUndo: false)
        case .done:
            guard editor.editingTextItemID != nil else { break }
            keepPreviews()
            editor.endEditingText()
        case .cancel:
            cancel()
        case .curatedSet(let index):
            guard editor.editingTextItemID == nil else { break }
            editor.applyCuratedSet(CuratedSet.all[index % CuratedSet.all.count])
        case let .toggleSets(first, second):
            guard editor.editingTextItemID == nil else { break }
            toggleSets(first, second)
        case let .toggleFit(index, delta):
            toggleFit(index, delta: delta)
        case .toggleTyping(let words):
            toggleTyping(words)
        case .toggleRewrite(let words):
            toggleRewrite(words)
        case .miraTitle:
            let before = editor.items
            mira.landTitle("A soft title for the day", receipt: MiraReceipt(changed: "Added a title.", kept: ""),
                           editor: editor)
            miraLanding = (before, editor.changeCount)
        case let .miraMove(index, top):
            guard let item = element(index) else { break }
            let before = editor.items
            if editor.applyPageEdits([ResolvedChange(id: item.id, y: Double(top))]) {
                miraLanding = (before, editor.changeCount)
            }
        case .miraBackground:
            let before = editor.items
            editor.setBackground(fileName: "dusk-\(editor.changeCount).png", describes: "a dusk sky")
            miraLanding = (before, editor.changeCount)
        case .miraRevert:
            revertMira()
        case .undo:
            // The header's undo while writing commits an open rewrite first,
            // then undoes it like any other step (the AI row stays open).
            let reopen = rewrite != nil
            keepPreviewsCounting()
            noteUndo { editor.undo() }
            if reopen, let (id, _) = editingBlock { rewrite = editor.item(id) }
            drift = [:]
        case .redo:
            keepPreviewsCounting()
            let had = editor.canRedo
            editor.redo()
            if had, editor.editingTextItemID != nil, editor.editingTextItemID == session?.id { session?.redone() }
            drift = [:]
        case .saveReload:
            saveReload()
        }
        switch action {
        case .undo, .miraRevert:
            historyDepth = max(0, historyDepth - 1)
        case .redo:
            historyDepth += 1
        case .saveReload:
            historyDepth = 0
        default:
            historyDepth += max(0, editor.changeCount - changeBefore)
            if colorSheet != nil, editor.changeCount != changeBefore { previewInHistory = true }
            if let id = editingBefore, editor.editingTextItemID == id, session?.id == id {
                session?.recorded(editor.changeCount - changeBefore)
            }
        }
        if historyDepth >= 48 { historyCapped = true }
        sceneReactions(changeBefore: changeBefore, editingBefore: editingBefore, pageBefore: pageBefore)
    }

    private func isSessionOwn(_ action: Action) -> Bool {
        switch action {
        // Undo and redo can reach past the session's start, and a fit
        // toggled on any block moves other blocks' pushes: not its own.
        case .type, .erase, .pointSize, .openRewrite, .showRewrite, .showOriginal, .colorPreview, .colorApply,
             .colorDrop, .done, .cancel, .toggleTyping, .toggleRewrite:
            return true
        default:
            return false
        }
    }

    /// What the scene does after any change: a session that ended keeps
    /// its previews and drops empty blocks; a recorded change re-measures
    /// every block and moves a waiting receipt on.
    private func sceneReactions(changeBefore: Int, editingBefore: CanvasItem.ID?, pageBefore: [CanvasItem]) {
        let editing = editor.editingTextItemID
        if editing != editingBefore {
            if editing == nil {
                keepPreviews()
                for item in editor.items where Self.isEmptyText(item) {
                    editor.discardAbandonedText(itemID: item.id)
                }
                session = nil
            } else if let editing {
                session = SessionRecord(id: editing, startPage: pageBefore)
            }
        }
        if editor.changeCount != changeBefore {
            mira.canvasDidChange(editor)
            remeasure()
        }
    }

    private static func isEmptyText(_ item: CanvasItem) -> Bool {
        guard case .text(let block) = item.content else { return false }
        return block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Done, and leaving the AI row or the color sheet, keep what is shown.
    private func keepPreviews() {
        if let original = rewrite {
            rewrite = nil
            fit("rewrite commit") { editor.commitPreview(of: original) }
        }
        if let original = colorSheet {
            colorSheet = nil
            fit("color commit") { editor.commitPreview(of: original) }
        }
    }

    private func showRewrite(_ text: String) {
        guard rewrite != nil, let (id, _) = editingBlock else { return }
        editor.setText(itemID: id, to: text)
        autosizeEditing()
    }

    // MARK: Fits

    private func autosizeEditing() {
        guard let (id, _) = editingBlock, let item = editor.item(id), let height = Self.height(item) else { return }
        fit("autosize") { editor.autosizeTextHeight(itemID: id, to: height) }
    }

    private func remeasure() {
        fit("re-measure") { editor.fitTextHeights(Self.height) }
    }

    /// Runs a fit, checking it creates no overlap and moves no user-moved
    /// element above where the user put it.
    private func fit(_ label: String, _ body: () -> Void) {
        let before = editor.items
        body()
        let after = editor.items
        // Any touch before counts, so a pair at the threshold does not flap.
        for pair in Geometry.overlaps(after).subtracting(Geometry.overlaps(before, by: 0)) {
            problems.append("\(label) created an overlap: \(describe(pair.first, in: after)) "
                            + "and \(describe(pair.second, in: after))")
        }
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in after {
            guard let was = old[item.id], let moved = drift[item.id] else { continue }
            let total = moved + Geometry.top(item) - Geometry.top(was)
            drift[item.id] = total
            if total < -0.5 {
                problems.append("\(label) moved a user-moved \(Self.kind(item)) up by \(-total) above where the user put it")
            }
        }
        drift = drift.filter { id, _ in after.contains { $0.id == id } }
    }

    // MARK: Composite toggles

    /// Runs a toggle pair round after round. On a settled page every element
    /// is exactly where it started, round one and round two. A page not yet
    /// settled (an overlap, or a pull held back by an element since moved)
    /// may settle -- an overlap flips what counts as below what -- but must
    /// reach a fixpoint within four rounds: no ratchet, however many rounds.
    private func expectToggle(_ label: String, _ round: () -> Void) {
        let start = editor.items
        let settling = Self.settling(start)
        round()
        if settling.isEmpty {
            expectSame(start, editor.items, label, settling: [])
            let first = editor.items
            round()
            expectSame(first, editor.items, label + ", second round", settling: [])
            return
        }
        var previous = editor.items
        for _ in 2...4 {
            round()
            if Self.samePlaces(previous, editor.items) { return }
            previous = editor.items
        }
        let before = editor.items
        round()
        expectSame(before, editor.items, label + ", still moving after four rounds", settling: [])
    }

    private static func samePlaces(_ lhs: [CanvasItem], _ rhs: [CanvasItem]) -> Bool {
        let now = Dictionary(rhs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return lhs.allSatisfy { was in
            now[was.id].map { Geometry.frame($0).distance(to: Geometry.frame(was)) <= 0.01 } ?? false
        }
    }

    /// The elements a fit may move to where the gaps put them: all of them
    /// on a page with an overlap (a take-back never runs one element into
    /// another) or a held-back pull, none on a settled page.
    static func settling(_ items: [CanvasItem]) -> Set<CanvasItem.ID> {
        let settled = Geometry.overlaps(items, by: 0).isEmpty && items.allSatisfy { ($0.fitOffset?.spared ?? 0) < 0.5 }
        return settled ? [] : Set(items.map(\.id))
    }

    private func expectSame(_ before: [CanvasItem], _ after: [CanvasItem], _ label: String,
                            settling: Set<CanvasItem.ID>) {
        let now = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for was in before {
            guard let item = now[was.id] else {
                problems.append("\(label): an element disappeared")
                continue
            }
            if settling.contains(item.id), item.size == was.size, item.position.x == was.position.x { continue }
            if Geometry.frame(item).distance(to: Geometry.frame(was)) > 0.01 {
                problems.append("\(label): a \(Self.kind(item)) moved from \(Geometry.frame(was)) to \(Geometry.frame(item))")
            }
        }
    }

    private func toggleSets(_ first: Int, _ second: Int) {
        let sets = CuratedSet.all
        func dress(_ index: Int) {
            let count = editor.changeCount
            editor.applyCuratedSet(sets[index % sets.count])
            if editor.changeCount != count { remeasure() }
        }
        dress(first)
        expectToggle("curated set \(first), \(second), \(first) again") {
            dress(second)
            dress(first)
        }
    }

    private func toggleFit(_ index: Int, delta: Int) {
        guard let item = textElement(index) else { return }
        let height = item.size.height
        // As after a recorded change (a style), so undo can take it back.
        editor.beginChange()
        expectToggle("fit \(delta) and back") {
            fit("fit grow") { editor.fitTextHeights { $0.id == item.id ? max(36, height + CGFloat(delta)) : nil } }
            fit("fit back") { editor.fitTextHeights { $0.id == item.id ? height : nil } }
        }
    }

    private func toggleTyping(_ words: Int) {
        guard colorSheet == nil, let (id, block) = editingBlock else { return }
        expectToggle("typing \(words) words and erasing them") {
            editor.setText(itemID: id, to: block.text + " " + Self.words(words, from: 5))
            autosizeEditing()
            editor.setText(itemID: id, to: block.text)
            autosizeEditing()
        }
    }

    /// Original, a version, Original again: the page as at the first.
    private func toggleRewrite(_ words: Int) {
        guard let original = rewrite, case .text(let block) = original.content else { return }
        showRewrite(block.text)
        expectToggle("a rewrite of \(words) words then Original") {
            showRewrite(Self.words(words, from: 7))
            showRewrite(block.text)
        }
    }

    // MARK: Cancel

    private func cancel() {
        guard let id = editor.editingTextItemID else { return }
        let record = session
        // The scene drops the open previews first.
        if let original = rewrite {
            rewrite = nil
            fit("rewrite discard") { editor.discardPreview(of: original) }
        }
        if let original = colorSheet, case .text(let block) = original.content {
            colorSheet = nil
            editor.setTextColorName(itemID: id, to: block.colorName, recordingUndo: false)
        }
        let before = editor.items
        let pushedBefore = editor.item(id)?.clearance?.pushed ?? 0
        let heightBefore = editor.item(id)?.size.height ?? 0
        fit("cancel") { editor.cancelEditingText() }
        guard let record, record.id == id else { return }
        let origin = record.origin
        let after = editor.items
        if let origin {
            if let now = editor.item(id), now.content != origin.content {
                problems.append("cancel left the block's words or style as \(now.content), not \(origin.content)")
            }
        } else if editor.item(id) != nil {
            problems.append("cancel kept the new block")
        }
        if record.pure {
            // Nothing but the session's own work: the page as it started.
            let start = Dictionary(record.startPage.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if Set(after.map(\.id)) != Set(start.keys) {
                problems.append("cancel changed which elements are on the page")
            }
            // On a page that was not settled when the session began an
            // element may end where the gaps put it (a take-back never runs
            // an element into another).
            let settling = Self.settling(record.startPage)
            for item in after {
                guard let was = start[item.id] else { continue }
                if settling.contains(item.id), item.size == was.size, item.position.x == was.position.x { continue }
                if Geometry.frame(item).distance(to: Geometry.frame(was)) > 0.01 {
                    problems.append("cancel left a \(Self.kind(item)) at \(Geometry.frame(item)), "
                                    + "not where the session found it, \(Geometry.frame(was))")
                }
            }
        } else {
            // Others keep what landed meanwhile; they move only by the
            // block's own net push in the session, and not otherwise.
            // The session's own pushes, or what the block growing back to
            // its starting height needs (an element moved into its room).
            let netPush = max(abs(pushedBefore - (origin?.clearance?.pushed ?? 0)),
                              (origin?.size.height ?? 0) - heightBefore)
            let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for item in after where item.id != id {
                guard let was = old[item.id] else { continue }
                if item.content != was.content {
                    problems.append("cancel changed another element's content")
                }
                // Up, never above where it was placed: a pull held back by an
                // element since moved away settles, with what is below it.
                let moved = Geometry.top(item) - Geometry.top(was)
                let bound = moved < 0 ? max(netPush, was.fitOffset?.down ?? 0) : netPush
                if abs(moved) > bound + 0.5 {
                    problems.append("cancel moved a \(Self.kind(item)) by \(moved), more than the block pushed (\(netPush))")
                }
            }
        }
    }

    // MARK: Mira

    private func revertMira() {
        let canRevert = mira.receiptCanRevert
        let before = editor.items
        let changes = editor.changeCount
        if canRevert {
            noteUndo { mira.revert(editor: editor) }
        } else {
            mira.revert(editor: editor)
        }
        if canRevert, let landing = miraLanding {
            if landing.changeCount != changes {
                problems.append("Revert undid with other steps recorded after Mira's change")
            }
            let restored = Dictionary(editor.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // An empty block left by a switch is not brought back (a husk).
            for item in landing.page where !Self.isEmptyText(item) && restored[item.id]?.content != item.content {
                problems.append("Revert did not bring back the page as Mira found it")
                break
            }
        } else if editor.items != before {
            problems.append("Revert with nothing to revert changed the page")
        }
        miraLanding = nil
        if canRevert { drift = [:] }
    }

    // MARK: Save and reload

    private func saveReload() {
        if editor.editingTextItemID != nil {
            keepPreviews()
            editor.endEditingText()
            for item in editor.items where Self.isEmptyText(item) {
                editor.discardAbandonedText(itemID: item.id)
            }
            session = nil
        }
        let filed = editor.composedMemory()
        do {
            let data = try JSONEncoder().encode(filed)
            let back = try JSONDecoder().decode(Memory.self, from: data)
            editor = CanvasViewModel(memory: back.materializedForEditing())
            editor.canvasWidth = Self.pageWidth
            remeasure()
            baseline = editor.items
            historyCapped = false
        } catch {
            problems.append("the page did not survive a save: \(error)")
        }
        drift = [:]
        miraLanding = nil
    }

    // MARK: Invariants

    func violations() async -> [String] {
        var found = problems
        problems = []
        let ids = editor.items.map(\.id)
        if Set(ids).count != ids.count { found.append("duplicate element ids") }
        if let editing = editor.editingTextItemID {
            if case .text = editor.item(editing)?.content {} else { found.append("editing an element that is not a text block on the page") }
        }
        if let selected = editor.selectedItemID, editor.item(selected) == nil {
            found.append("the selection points at an element not on the page")
        }
        if editor.editingTextItemID == nil, rewrite != nil || colorSheet != nil {
            found.append("a preview outlived its writing session")
        }
        for item in editor.items where item.size.width < 43.99 || item.size.height < 35.99 {
            found.append("a \(Self.kind(item)) below the minimum size: \(item.size)")
        }
        for item in editor.items where item.position.x < 0 || item.position.x > Self.pageWidth {
            found.append("a \(Self.kind(item)) off the page sideways at x \(item.position.x)")
        }
        if editor.composedMemory().items.contains(where: Self.isEmptyText) {
            found.append("a filing would keep an empty text block")
        }
        if editor.editingTextItemID == nil, editor.items.contains(where: Self.isEmptyText) {
            found.append("an empty text block outside any writing session")
        }
        do {
            let data = try JSONEncoder().encode(editor.memory)
            let back = try JSONDecoder().decode(Memory.self, from: data)
            if back != editor.memory { found.append("the page changed in a JSON round trip") }
        } catch {
            found.append("the page did not encode: \(error)")
        }
        return found
    }

    func finish() async -> [String] {
        // Undo all the way: the starting page (when history kept it all).
        if rewrite != nil || colorSheet != nil { keepPreviews() }
        var undone = 0
        while editor.canUndo, undone < 60 {
            editor.undo()
            undone += 1
            editor.fitTextHeights(Self.height)
        }
        guard undone < 50, !historyCapped else { return [] }
        var found: [String] = []
        let now = Dictionary(editor.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if Set(now.keys) != Set(baseline.map(\.id)) {
            found.append("undo to the start: elements \(editor.items.count), started with \(baseline.count)")
        }
        func plain(_ content: CanvasItem.Content) -> CanvasItem.Content {
            guard previewInHistory, case .text(var block) = content else { return content }
            block.colorName = ""
            return .text(block)
        }
        for item in baseline {
            guard let back = now[item.id] else { continue }
            if plain(back.content) != plain(item.content) {
                found.append("undo to the start: a \(Self.kind(item))'s content differs")
            }
            if Geometry.frame(back).distance(to: Geometry.frame(item)) > 0.01 {
                found.append("undo to the start: a \(Self.kind(item)) at \(Geometry.frame(back)), started at \(Geometry.frame(item))")
            }
        }
        return found
    }

    // MARK: Describing

    func trace() -> String {
        let lines = editor.items.map { item -> String in
            let frame = Geometry.frame(item)
            var line = "  \(Self.kind(item)) x \(frame.minX)...\(frame.maxX) y \(frame.minY)...\(frame.maxY)"
            if let offset = item.fitOffset { line += " fit down \(offset.down) spared \(offset.spared)" }
            if let clearance = item.clearance { line += " cleared \(clearance.height) pushed \(clearance.pushed)" }
            if item.id == editor.editingTextItemID { line += " [editing]" }
            return line
        }
        return lines.joined(separator: "\n")
    }

    private static func kind(_ item: CanvasItem) -> String {
        switch item.content {
        case .text(let block): return "text block \"\(block.text.prefix(16))\""
        case .image: return "photo"
        case .sticker: return "sticker"
        case .sound: return "sound"
        }
    }

    private func describe(_ id: CanvasItem.ID, in items: [CanvasItem]) -> String {
        guard let item = items.first(where: { $0.id == id }) else { return "?" }
        return "\(Self.kind(item)) \(Geometry.frame(item))"
    }
}

/// Unrotated frames, as TextFit sees them.
enum Geometry {
    static func top(_ item: CanvasItem) -> CGFloat { item.position.y - item.size.height / 2 }

    static func frame(_ item: CanvasItem) -> CGRect {
        CGRect(x: item.position.x - item.size.width / 2, y: top(item),
               width: item.size.width, height: item.size.height)
    }

    /// Pairs whose frames overlap by more than `minimum` points both ways.
    static func overlaps(_ items: [CanvasItem], by minimum: CGFloat = 1) -> Set<Pair> {
        var pairs: Set<Pair> = []
        for (index, item) in items.enumerated() {
            for other in items[(index + 1)...] {
                let shared = frame(item).intersection(frame(other))
                if !shared.isNull, shared.width > minimum, shared.height > minimum {
                    pairs.insert(Pair(item.id, other.id))
                }
            }
        }
        return pairs
    }

    struct Pair: Hashable {
        let first: UUID
        let second: UUID

        init(_ lhs: UUID, _ rhs: UUID) {
            (first, second) = lhs.uuidString < rhs.uuidString ? (lhs, rhs) : (rhs, lhs)
        }
    }
}

private extension CGRect {
    func distance(to other: CGRect) -> CGFloat {
        max(abs(minX - other.minX), abs(minY - other.minY), abs(width - other.width), abs(height - other.height))
    }
}

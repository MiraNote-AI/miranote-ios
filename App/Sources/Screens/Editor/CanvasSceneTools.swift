import Foundation
import MiraNoteKit
import SwiftUI

// Shared state shapes for CanvasScene's bottom cluster.

enum RecorderState {
    case idle
    /// The Voice tool is open but the mic is not live yet -- recording
    /// starts only when the user presses Record.
    case armed
    case recording(start: Date)
}

/// Photos picked while another import still loads, waiting their turn.
struct QueuedImport {
    let load: () async -> [Data]
    let then: ([CanvasItem.ID]) -> Void
}

/// Which dictation strip's mic is still coming up (it takes the audio
/// session, and the permission alert the first time): a cancel then has
/// to know whose it is.
enum StartingMic {
    case text, mira
}

/// A take Stop just put on the page (handoff screen 09): the result sheet
/// offers Revert / Keep while the add is still the page's last change.
struct AttachedSound: Equatable {
    let itemID: CanvasItem.ID
    /// `CanvasViewModel.changeCount` right after the add.
    let changeCount: Int
}

/// One photo editing session (handoff screens 27-28): the photo, how it
/// looked when editing began, and whether it has been edited since.
struct PhotoSession {
    let itemID: CanvasItem.ID
    let original: ImageRef
    var edited = false
    /// The photo as the session last saw it. A change made while the panel
    /// was closed (a Mira edit from the bar, a header Undo) is not the
    /// session's to compare or revert, so reopening then starts anew (#102).
    var lastSeen: ImageRef

    init(itemID: CanvasItem.ID, original: ImageRef) {
        self.itemID = itemID
        self.original = original
        self.lastSeen = original
    }

    /// Whether opening `id`, which now looks like `ref`, picks this session
    /// up again: the same photo, unchanged since the session last saw it.
    /// A caption or a description is not an edit.
    func continues(_ id: CanvasItem.ID, showing ref: ImageRef) -> Bool {
        id == itemID && ref.fileName == lastSeen.fileName
            && ref.filterName == lastSeen.filterName && ref.frameName == lastSeen.frameName
    }
}

/// The AI row's open session: the cached rewrites, and the block as it was
/// when the row opened (what the commit's one undo step goes back to).
struct RewriteState {
    var session: TextRewriteSession
    let original: CanvasItem
}

/// The custom color sheet, open for the block's text color (screen 14) or
/// its background (screen 20), and the block before the live preview.
struct ColorRequest {
    enum Target { case text, background }
    let target: Target
    let original: CanvasItem
    let initial: RGBColor

    /// What Apply puts on the block for the color `hex` the sheet shows;
    /// nil when it is the block's own color -- "ink" stays "ink" and no
    /// undo step is spent. A background sheet opened with none set shows
    /// #8B5962, and applies it.
    func applied(_ hex: String) -> String? {
        guard case .text(let block) = original.content else { return hex }
        let own = target == .text ? block.colorName : block.backgroundColorName
        return !own.isEmpty && hex == initial.hex ? nil : hex
    }
}

// MARK: - Text accessory

extension CanvasScene {
    /// Text tool, screen 10 then 11: the Text tool lights up for a beat,
    /// then a new block appears on the canvas and the keyboard rises --
    /// typing happens where the words will live.
    func armTextMode() {
        withAnimation(.easeOut(duration: 0.15)) { textModeArming = true }
        Task {
            try? await Task.sleep(for: .milliseconds(Self.textModeBeat))
            // Cancel (or Done) during the beat called it off.
            guard textModeArming else { return }
            textModeArming = false
            addTextBlock()
        }
    }

    /// Long enough to read the Text tool turning on; screen-capture runs
    /// stretch it (`-TEXT_MODE_BEAT <ms>`) to photograph the state.
    private static var textModeBeat: Int {
        let stretched = UserDefaults.standard.integer(forKey: "TEXT_MODE_BEAT")
        return stretched > 0 ? stretched : 250
    }

    /// The handoff's new block (screens 11-20): Josefin Medium 21, ink
    /// #293322, 230 wide (206 of words inside the 12 pt insets).
    private func addTextBlock() {
        let width: CGFloat = 230
        let height = TextMeasure.blockHeight(
            text: "", pointSize: TextFace.newBlockSize, fontName: TextFace.newBlockFont, width: width
        )
        // Below what is there; on a near-empty page, a third of the way
        // down the card, clear of the keyboard and the text chrome.
        let top = max(editor.contentBottom + 70 - height / 2, 110)
        let position = CGPoint(x: MiraNoteConfig.pageWidth / 2, y: min(top + height / 2, 4000))
        let id = editor.addText(
            "", at: position, pointSize: TextFace.newBlockSize,
            size: CGSize(width: width, height: height),
            fontName: TextFace.newBlockFont, colorName: TextFace.newBlockColor
        )
        // addText already recorded the undo point for this compound action.
        editor.startEditingText(id, recordingUndo: false)
        textFocus = id
    }

    /// The block being edited, for showing its current style.
    var editingBlock: TextBlock? {
        guard let id = editor.editingTextItemID,
              case .text(let block) = editor.item(id)?.content else { return nil }
        return block
    }

    /// The three-layer accessory above the keyboard (screens 11-20): the
    /// active tool's row, the tool bar, the dictation strip. The tool bar
    /// never moves; rows crossfade under the finger.
    @ViewBuilder var textAccessory: some View {
        VStack(spacing: 0) {
            if textTool.hasRow {
                textToolRow
                    .id(textTool)
                    .transition(.opacity)
                    .padding(.bottom, textTool.rowGap)
            }
            TextToolBar(active: textTool, alignment: editingBlock?.alignment ?? .leading, onSelect: selectTextTool)
                .padding(.horizontal, Metrics.chromeInset)
            DictationStrip(
                surface: .page,
                listening: dictating,
                detail: stripDetail ?? String(appCopy: "accurate voice-to-text"),
                onPress: { if dictationPress == nil { pressDictation() } },
                onRelease: releaseDictation,
                onCancel: cancelDictationIfNeeded
            )
            .padding(.horizontal, Metrics.chromeInset)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mira Dictation")
            .accessibilityValue(stripDetail ?? "")
            .accessibilityHint(dictating ? Text("Ends the dictation.") : Text("Hold to talk, or tap to start."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dictating ? stopDictation() : startDictation() }
            .accessibilityIdentifier("style.mic")
        }
        // 4 above the keyboard.
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.15), value: textTool)
    }

    /// The strip's line when it is not at rest: a new take listening while
    /// an earlier one is written down reads as listening.
    private var stripDetail: String? {
        if dictating { return String(appCopy: "Listening...") }
        return writingDown ? String(appCopy: "Writing it down...") : dictationHint
    }

    @ViewBuilder private var textToolRow: some View {
        let block = editingBlock
        switch textTool {
        case .font:
            FontChipRow(
                fontName: block?.fontName ?? "",
                pointSize: block?.pointSize ?? TextFace.newBlockSize,
                onFont: { name in
                    guard let id = editor.editingTextItemID else { return }
                    editor.setTextFont(itemID: id, to: name)
                    remeasureEditedText(id)
                },
                onSize: { choice in
                    guard let id = editor.editingTextItemID else { return }
                    editor.setTextPointSize(itemID: id, to: choice.pointSize)
                    remeasureEditedText(id)
                }
            )
        case .color:
            let current = block?.colorName ?? ""
            ColorSwatchRow(
                current: current,
                isCustom: current.hasPrefix("#") && current != TextFace.newBlockColor
                    && !Palette.textSwatches.contains { $0.hex == current },
                onSwatch: { hex in
                    if let id = editor.editingTextItemID { editor.setTextColorName(itemID: id, to: hex) }
                },
                onCustom: { openColorSheet(.text) }
            )
        case .ai:
            RewriteRow(
                selected: rewrite?.session.selected ?? .original,
                pending: rewrite?.session.pending,
                enabled: !(block?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                onSelect: pickRewrite
            )
            .padding(.horizontal, Metrics.chromeInset)
        case .background:
            let current = block?.backgroundColorName ?? ""
            TextBackgroundRow(
                current: current,
                isCustom: !current.isEmpty && !Palette.textBackgroundSwatches.contains { $0.hex == current },
                onPick: { hex in
                    if let id = editor.editingTextItemID { editor.setTextBackground(itemID: id, to: hex) }
                },
                onCustom: { openColorSheet(.background) }
            )
            .padding(.horizontal, Metrics.chromeInset)
        case .align:
            EmptyView()
        }
    }

    /// Exactly one tool is active. Align has no row: each tap makes it the
    /// active tool and steps the alignment (screens 16-17).
    func selectTextTool(_ tool: TextTool) {
        if tool != .ai { finishRewrite() }
        switch tool {
        case .align:
            if let id = editor.editingTextItemID, let block = editingBlock {
                editor.setTextAlignment(itemID: id, to: block.alignment.next)
            }
        case .ai:
            if textTool != .ai { startRewrite() }
        case .font, .color, .background:
            break
        }
        textTool = tool
    }

    // MARK: Ending a session

    /// The header's Done: the session's previews are kept. Dictated words
    /// on their way are waited for, so they land inside the session -- a
    /// take still listening (the tap toggle) stops and is waited for too.
    func endTextEditing() {
        if dictating, editor.editingTextItemID != nil { stopDictation() }
        if writingDown {
            waitForWordsThenEnd()
            return
        }
        finishRewrite()
        if let request = colorRequest {
            editor.commitPreview(of: request.original)
            colorRequest = nil
        }
        textModeArming = false
        editor.endEditingText()
        textFocus = nil
        resetTextTools()
    }

    /// The header's Cancel: the block goes back to how it was when the
    /// session began (a new block disappears). Open previews go first, so
    /// nothing live survives a session the Kit can no longer take back.
    func cancelTextEditing() {
        textModeArming = false
        // Words still being written down belonged to this session: dropped.
        dictationTarget = nil
        if let state = rewrite {
            editor.discardPreview(of: state.original)
            rewrite = nil
        }
        if let request = colorRequest {
            dropColorPreview(request)
            colorRequest = nil
        }
        editor.cancelEditingText()
        textFocus = nil
        resetTextTools()
    }

    /// The next session opens on the font row (screen 11).
    func resetTextTools() {
        textTool = .font
        rewrite = nil
        dictationHint = nil
    }

    /// The header's undo while writing. An open color preview is the newest
    /// change: undo drops it and nothing more. A rewrite preview is
    /// committed first, so undo takes it back like any other step.
    func undoFromHeader() {
        finishRewrite()
        if let request = colorRequest {
            let previewing = previewedColor(request) != nil
            dropColorPreview(request)
            colorRequest = nil
            refocusEditedText()
            if previewing { return }
        }
        editor.undo()
        if textTool == .ai, editor.editingTextItemID != nil { startRewrite() }
    }

    // MARK: AI rewrite in place (screen 15)

    private func startRewrite() {
        guard let id = editor.editingTextItemID, let item = editor.item(id),
              case .text(let block) = item.content else { return }
        rewrite = RewriteState(session: TextRewriteSession(original: block.text), original: item)
    }

    /// Leaving the row keeps the version on the canvas, as one undo step.
    func finishRewrite() {
        guard let state = rewrite else { return }
        rewrite = nil
        editor.commitPreview(of: state.original)
    }

    private func pickRewrite(_ choice: TextRewriteSession.Choice) {
        guard var state = rewrite, let id = editor.editingTextItemID else { return }
        dictationHint = nil
        if let text = state.session.select(choice) {
            rewrite = state
            showRewrite(text, in: id)
            return
        }
        rewrite = state
        guard let mode = choice.mode else { return }
        let source = state.session.original
        Task {
            do {
                let result = try await mira.rewriteText(source, mode: mode)
                guard var now = rewrite, now.original.id == id else { return }
                let shown = now.session.resolve(choice, of: source, with: result)
                rewrite = now
                if let shown { showRewrite(shown, in: id) }
            } catch {
                guard var now = rewrite, now.original.id == id else { return }
                now.session.fail(choice, of: source)
                rewrite = now
                dictationHint = String(appCopy: "Couldn't rewrite -- try again?")
            }
        }
    }

    private func showRewrite(_ text: String, in id: CanvasItem.ID) {
        editor.setText(itemID: id, to: text)
        remeasureEditedText(id)
    }

    /// Typing while the AI row is open makes the typed words the Original.
    func noteTyped(_ text: String?) {
        guard let text, var state = rewrite else { return }
        state.session.adopt(typed: text)
        rewrite = state
    }

    /// Size and face changes re-measure the block so the box fits the type.
    func remeasureEditedText(_ id: CanvasItem.ID) {
        guard let item = editor.item(id), case .text(let block) = item.content else { return }
        editor.autosizeTextHeight(itemID: id, to: TextMeasure.blockHeight(
            text: block.text,
            pointSize: block.pointSize,
            fontName: block.fontName,
            width: item.size.width
        ))
    }
}

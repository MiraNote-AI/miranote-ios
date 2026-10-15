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
    case review(data: Data, duration: TimeInterval)
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
            DictationStrip(listening: dictating, hint: dictationHint)
                .padding(.horizontal, Metrics.chromeInset)
                .padding(.top, 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if dictationPress == nil { pressDictation() } }
                        .onEnded { _ in releaseDictation() }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mira Dictation")
                .accessibilityValue(dictating ? "Listening..." : (dictationHint ?? ""))
                .accessibilityHint(dictating ? "Ends the dictation." : "Hold to talk, or tap to start.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { dictating ? stopDictation() : startDictation() }
                .accessibilityIdentifier("style.mic")
        }
        // 4 above the keyboard.
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.15), value: textTool)
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

    /// The header's Done: the session's previews are kept.
    func endTextEditing() {
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

    /// The header's Cancel: the page goes back to how it was when the
    /// session began (a new block disappears).
    func cancelTextEditing() {
        textModeArming = false
        rewrite = nil
        colorRequest = nil
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

    /// The header's undo while writing: an open preview is committed first,
    /// so undo takes it back like any other step.
    func undoFromHeader() {
        finishRewrite()
        if let request = colorRequest {
            editor.discardPreview(of: request.original)
            colorRequest = nil
            refocusEditedText()
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
                dictationHint = "Couldn't rewrite -- try again?"
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

    // MARK: Custom color (screens 14 and 20)

    /// Opens the sheet over the scrim: the keyboard goes down, editing (and
    /// with it the scrim and the live preview) stays.
    func openColorSheet(_ target: ColorRequest.Target) {
        guard let id = editor.editingTextItemID, let item = editor.item(id),
              case .text(let block) = item.content else { return }
        let name: String
        switch target {
        case .text: name = block.colorName
        case .background: name = block.backgroundColorName.isEmpty ? "#8B5962" : block.backgroundColorName
        }
        colorRequest = ColorRequest(target: target, original: item, initial: RGBColor(Palette.color(named: name)))
        textFocus = nil
    }

    @ViewBuilder var colorSheet: some View {
        if let request = colorRequest {
            CustomColorSheet(
                title: request.target == .text ? "Custom text color" : "Custom text background",
                subtitle: request.target == .text
                    ? "Choose a shade, or sample it from your memory."
                    : "Set the color behind your selected text.",
                initial: request.initial,
                onLiveChange: { color in
                    guard let id = editor.editingTextItemID else { return }
                    switch request.target {
                    case .text: editor.setTextColorName(itemID: id, to: color.hex, recordingUndo: false)
                    case .background: editor.setTextBackground(itemID: id, to: color.hex, recordingUndo: false)
                    }
                },
                onApply: { _ in closeColorSheet(keeping: true) },
                onCancel: { closeColorSheet(keeping: false) },
                snapshot: pageSnapshot
            )
            .padding(.horizontal, Metrics.chromeInset)
            .transition(.offset(y: 20).combined(with: .opacity))
        }
    }

    /// Apply keeps the preview as one undo step; cancel (swipe down, a tap
    /// outside) drops it. Either way the keyboard comes back on the row.
    func closeColorSheet(keeping: Bool) {
        guard let request = colorRequest else { return }
        if keeping {
            editor.commitPreview(of: request.original)
        } else {
            editor.discardPreview(of: request.original)
        }
        withAnimation(.easeOut(duration: 0.2)) { colorRequest = nil }
        refocusEditedText()
    }

    /// The keyboard comes back once the sheet has gone (focusing in the
    /// same update as the sheet's removal does not take).
    func refocusEditedText() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if let id = editor.editingTextItemID { textFocus = id }
        }
    }

    /// The page as a picture, for the eyedropper.
    private func pageSnapshot() -> UIImage? {
        let renderer = ImageRenderer(content: StaticPageView(
            memory: editor.memory, designWidth: MiraNoteConfig.pageWidth, showsSound: false
        ))
        renderer.scale = 2
        return renderer.uiImage
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

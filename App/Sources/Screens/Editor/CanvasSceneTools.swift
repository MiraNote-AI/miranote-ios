import Foundation
import MiraNoteKit
import SwiftUI

// MARK: - Text accessory

extension CanvasScene {
    /// Text tool, screen 11: a new block appears on the canvas and the
    /// keyboard rises at once -- typing happens where the words will live.
    /// The block comes on the next main-actor turn, never in the tap's own:
    /// its field must be on screen before it can take focus.
    func armTextMode() {
        let beat = Self.textModeBeat
        if beat > 0 {
            withAnimation(.easeOut(duration: 0.15)) { textModeArming = true }
        } else {
            textModeArming = true
        }
        Task {
            if beat > 0 { try? await Task.sleep(for: .milliseconds(beat)) }
            // Back (or another tool) before it landed called it off.
            guard textModeArming else { return }
            textModeArming = false
            addTextBlock()
        }
    }

    /// No beat by default (#162: the wait read as a stall). Screen-capture
    /// runs and the beat tests stretch one in (`-TEXT_MODE_BEAT <ms>`) to
    /// photograph screen 10, the Text tool lit before the block appears.
    private static var textModeBeat: Int {
        max(0, UserDefaults.standard.integer(forKey: "TEXT_MODE_BEAT"))
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

    /// The accessory above the keyboard (screens 11-20, #205), bottom to
    /// top: the Mira chat box with its mic (T1, T2), Back and the tool bar,
    /// the active tool's row, and a caption line when the mic has news.
    /// The tool bar never moves; rows crossfade under the finger. One
    /// layer, so all of it rides up on the keyboard together (#162).
    @ViewBuilder var textAccessory: some View {
        VStack(spacing: 0) {
            if textTool.hasRow {
                textToolRow
                    .id(textTool)
                    .transition(.opacity)
                    .padding(.bottom, textTool.rowGap)
            }
            HStack(spacing: 8) {
                TextBackKey(onBack: endTextEditing)
                TextToolBar(active: textTool, alignment: editingBlock?.alignment ?? .leading,
                            onSelect: selectTextTool)
            }
            .padding(.horizontal, Metrics.chromeInset)
            WritingChatBox(
                listening: dictating,
                recorder: dictating ? recorder : nil,
                status: micStatus ?? "",
                onPress: { if dictationPress == nil { pressDictation() } },
                onRelease: releaseDictation,
                // The system took the touch: the take ends as if let go (#218).
                onCancel: stopDictationForBackground,
                onToggle: { dictating ? stopDictation() : startDictation() }
            )
            .padding(.horizontal, Metrics.chromeInset)
            .padding(.top, 8)
        }
        // Over the rows, not among them: the block being written is kept
        // clear of the rows' top, which a caption coming and going with
        // every take would move -- and the page with it.
        .overlay(alignment: .top) {
            if let caption = dictationCaption {
                Text(caption)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, Metrics.chromeInset)
                    .padding(.bottom, 6)
                    // Rises from the rows' top edge, taking no room.
                    .frame(height: 0, alignment: .bottom)
                    .transition(.opacity)
            }
        }
        // 4 above the keyboard.
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.15), value: textTool)
        .animation(.easeOut(duration: 0.15), value: dictationCaption)
        // VoiceOver's two-finger scrub ends the writing, as Back does.
        .accessibilityAction(.escape) { endTextEditing() }
        .onAppear { TextOpenTiming.markAccessoryShown() }
    }

    /// The mic's state as VoiceOver reads it: a new take listening while
    /// an earlier one is written down reads as listening.
    private var micStatus: String? {
        if dictating { return String(appCopy: "Listening...") }
        return dictationCaption
    }

    /// The caption over the rows: the words on their way, or why nothing
    /// landed or a rewrite failed (the free limit among them, #213). The
    /// chat box itself says "Listening...".
    private var dictationCaption: String? {
        writingDown ? String(appCopy: "Writing it down...") : dictationHint
    }

    @ViewBuilder private var textToolRow: some View {
        let block = editingBlock
        switch textTool {
        case .font:
            FontChipRow(
                fontName: block?.fontName ?? "",
                pointSize: block?.pointSize ?? TextFace.newBlockSize,
                riding: textToolsRiding,
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

    /// The text row's Back (a page tap, Esc): the session's previews are
    /// kept. Dictated words on their way are waited for (at most
    /// `doneWaitCap`), so they land inside the session -- a take still
    /// listening (the tap toggle) stops and is waited for too.
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

    /// Words written in paragraphs (blank lines between them) become one
    /// block per paragraph, stacked under the block (#184): one undo step
    /// gives the single block back.
    func splitWrittenParagraphs(_ id: CanvasItem.ID) {
        editor.splitParagraphs(of: id) { block, width in
            TextMeasure.blockHeight(text: block.text, pointSize: block.pointSize,
                                    fontName: block.fontName, width: width)
        }
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
                dictationHint = AIConsentError.message(for: error)
                    ?? String(appCopy: "Couldn't rewrite -- try again?")
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

import MiraNoteKit
import SwiftUI

/// The base editor: the infinite canvas plus the five-tool bar. Background,
/// Voice and Text act directly on the canvas -- Background opens its panel
/// in place, Voice swaps the bottom bar for a recorder, Text drops an
/// editable block; Image and Sticker leave for their panels. Header is
/// Home (Canvas while a tool is open in place) / undo / Save; Save still
/// files the page and leaves.
struct CanvasScene: View {
    @Bindable var editor: CanvasViewModel
    @Bindable var mira: MiraCanvasCoordinator
    var imageStudio: ImageStudioService = MockImageStudioService()
    var actions = EditorActions()
    /// A tool requested from another scene (consumed on appear/change).
    @Binding var pendingTool: EditorMode?
    /// A generated picture or sticker handed back by the Image or Sticker
    /// panel, waiting for the tap
    /// that says where it goes.
    @Binding var pendingPlacement: PendingPlacement?
    var recorderFactory: @MainActor () -> AudioRecording = { AudioRecorder() }
    var transcription: VoiceTranscriptionService = MockVoiceTranscriptionService()

    @State var recorderState: RecorderState = .idle
    @State var recorder: AudioRecording?
    @State var recorderNotice: String?
    @State var reviewNote = ""
    /// The text tool whose row is open (screen 11: Aa when writing starts).
    @State var textTool: TextTool = .font
    @State var rewrite: RewriteState?
    @State var colorRequest: ColorRequest?
    /// The beat between tapping Text and the block appearing (screen 10):
    /// the Text tool shows active and the composer reads as text entry.
    @State var textModeArming = false
    /// The dictation strip's press in progress.
    @State var dictationPress: (start: Date, wasLive: Bool)?
    @State private var miraPrompt = ""
    @State private var gestureHint: String?
    @State private var editingImageItem: CanvasItem.ID?
    /// The edited photo's original, while the panel's compare is held.
    @State private var comparingImage: ImageRef?
    /// The photo editing session: which photo, how it looked when editing
    /// began, and whether it has been edited since. It outlives the panel
    /// (an AI edit closes it, a caption edit rebuilds it) and ends when
    /// another photo is opened.
    @State private var photoSession: PhotoSession?
    @State private var editingStickerItem: CanvasItem.ID?
    /// The element an edit panel just closed on, scrolled into view.
    @State private var revealItem: CanvasItem.ID?
    @State private var backgroundPanelOpen = false
    @State private var showsToolsOnboarding = false
    @State private var dropToDelete: DropToDelete?
    @State var dictating = false
    /// The dictation strip's subtitle when the mic is not live: why nothing
    /// landed, or why a rewrite failed.
    @State var dictationHint: String?
    @FocusState var textFocus: CanvasItem.ID?
    @FocusState private var miraFocus: Bool

    private let soundStore = SoundFileStore()
    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    /// Words are being written (or the Text tool is on its way in): the
    /// header reads Cancel / undo / Done, and Done ends the writing.
    private var writing: Bool { editor.editingTextItemID != nil || textModeArming }

    var body: some View {
        ZStack(alignment: .bottom) {
            scaffold
                // While words are written the page keeps its size and the
                // keyboard rides over the dock, as drawn (screens 11-20).
                .ignoresSafeArea(.keyboard, edges: editor.editingTextItemID != nil ? .bottom : [])
            // The text chrome floats over the page, on the keyboard.
            if editor.editingTextItemID != nil {
                if colorRequest != nil {
                    // 14 above the composer's slot (screens 14 and 20).
                    colorSheet.padding(.bottom, 54 + 14 + 2)
                } else {
                    textAccessory
                }
            }
        }
    }

    /// The canvas scene proper: header, page, dock, and the scene's
    /// lifecycle (the body adds the floating text chrome).
    private var scaffold: some View {
        EditorScaffold(
            leading: writing ? "Cancel" : (toolOpen ? "Canvas" : "Home"),
            trailing: writing ? "Done" : "Save",
            onLeading: writing ? cancelTextEditing : (toolOpen ? closeTool : actions.leading),
            onTrailing: writing ? endTextEditing : actions.done,
            onUndo: writing ? undoFromHeader : editor.undo,
            undoEnabled: editor.canUndo,
            leadingMuted: !writing,
            leadingID: writing ? "text.cancel" : nil,
            trailingID: writing ? "keyboard.done" : nil,
            dimmed: editor.editingTextItemID != nil
        ) {
            CanvasBoardView(
                editor: editor,
                soundStore: soundStore,
                textFocus: $textFocus,
                workingItemIDs: mira.workingItemIDs,
                onEditImage: { id in
                    // The panel takes the bottom cluster: never unmount a
                    // live Mira turn's Stop, and stop the mic first.
                    guard !mira.isWorking else { return }
                    cancelRecording()
                    cancelDictationIfNeeded()
                    backgroundPanelOpen = false
                    if case .image(let ref) = editor.item(id)?.content,
                       photoSession?.continues(id, showing: ref) != true {
                        photoSession = PhotoSession(itemID: id, original: ref)
                    }
                    editingImageItem = id
                },
                onEditSticker: { id in
                    guard !mira.isWorking else { return }
                    cancelRecording()
                    cancelDictationIfNeeded()
                    backgroundPanelOpen = false
                    editingStickerItem = id
                },
                onPaperTap: {
                    // An armed recorder holds nothing yet, so a paper tap
                    // folds it like it folds the text tools. Recording and
                    // review keep their bar: a stray tap must not lose audio.
                    if case .armed = recorderState { recorderState = .idle }
                    // The Background card is a tool too: the paper folds it.
                    backgroundPanelOpen = false
                },
                onFavorite: { item in
                    switch item.content {
                    case .sticker(let sticker):
                        favoritesStore.add(sticker)
                    case .image(let ref):
                        favoritesStore.add(GeneratedSticker(
                            prompt: ref.displayName,
                            symbolName: "photo",
                            fileName: ref.fileName,
                            kind: .image
                        ))
                    case .text, .sound:
                        break
                    }
                },
                onPlaceTap: pendingPlacement == nil ? nil : { placePending(at: $0) },
                revealItem: $revealItem,
                dropToDelete: $dropToDelete,
                comparing: editingImageItem.flatMap { id in comparingImage.map { (id, $0) } }
            )
            .overlay {
                // With the color sheet up, a tap on the page cancels it
                // instead of ending the writing.
                if colorRequest != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { closeColorSheet(keeping: false) }
                }
            }
        } bottom: {
            // One container, so the sign covers the dock as a whole: an
            // overlay on the bare builder would repeat on every child.
            VStack(spacing: 16) { bottomCluster }
                .overlay {
                    if let dropToDelete {
                        DeleteDropZone(armed: dropToDelete == .armed)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: dropToDelete)
        }
        .overlay {
            if showsToolsOnboarding {
                ToolsOnboarding(
                    onSkip: { finishToolsOnboarding(openBackground: false) },
                    onChooseBackground: { finishToolsOnboarding(openBackground: true) }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            // The tools introduction meets the first blank page only -- and
            // not when a tool or a placement is already on its way in.
            if editor.items.isEmpty, pendingTool == nil, pendingPlacement == nil,
               HintCenter.shouldShow(ToolsOnboarding.hintID) {
                showsToolsOnboarding = true
            }
            remeasureTextBlocks()
            mira.prepareTurn = { await lookAtUnseenPhotos() }
            mira.renderPage = {
                CanvasSnapshot.jpeg(
                    memory: editor.composedMemory(),
                    canvasWidth: MiraNoteConfig.pageWidth
                )
            }
            Task { await lookAtUnseenPhotos() }
            consumePendingTool()
        }
        .onDisappear { cancelRecording() }
        .onChange(of: pendingTool) { consumePendingTool() }
        .onChange(of: editor.selectedItemID) { _, selected in
            // Layer-1 onboarding: the gesture hint appears on the first
            // selection ever, then graduates for good.
            guard selected != nil, HintCenter.shouldShow("gesture-basics") else { return }
            HintCenter.graduate("gesture-basics")
            gestureHint = "Drag to move. Two fingers tilt. Long-press for more."
            Task {
                try? await Task.sleep(for: .seconds(5))
                gestureHint = nil
            }
        }
        .onChange(of: editor.changeCount) {
            // A user edit while a receipt shows makes Revert dishonest: the
            // receipt steps aside. Here, not in MiraCard, which a panel or the
            // recorder can unmount -- the receipt then came back stale.
            mira.canvasDidChange(editor)
            // The edited photo can be deleted or undone away by canvas
            // interactions above the panel; close the panel when its item
            // is no longer an image.
            if let id = editingImageItem {
                if case .image = editor.item(id)?.content {} else {
                    editingImageItem = nil
                }
            }
            if let id = editingStickerItem {
                if case .sticker = editor.item(id)?.content {} else {
                    editingStickerItem = nil
                }
            }
            // Committed changes that rewrite text from OUTSIDE typing --
            // Mira transforms, undo -- must also re-fit their blocks, or a
            // longer polish truncates. No-op for untouched blocks.
            remeasureTextBlocks()
        }
        .onChange(of: editor.editingTextItemID) { _, editing in
            if editing == nil {
                // Ended from anywhere (a paper tap, an undo past the block):
                // an open preview is kept, like Done keeps it.
                finishRewrite()
                if let request = colorRequest {
                    editor.commitPreview(of: request.original)
                    colorRequest = nil
                }
                resetTextTools()
                cleanUpEmptyText()
                cancelDictationIfNeeded()
            } else {
                // Writing takes the bottom cluster; the Background card must
                // not come back over Mira's strip once it ends.
                backgroundPanelOpen = false
            }
        }
        .onChange(of: editingImageItem) { left, _ in
            // The panel let go of a photo: its session picks up from here,
            // unless something else changes the photo first (#102).
            if let left { notePhotoSeen(left) }
        }
        .onChange(of: dropToDelete) { _, phase in
            // Moving an element lowers any keyboard -- canvas text already
            // ends editing; the Mira prompt must too, or a drop over the
            // keyboard would delete with no sign over it.
            if phase != nil { miraFocus = false }
        }
        .onChange(of: mira.isWorking) { _, working in
            // A running turn owns the strip (Stop, then the receipt).
            if working { backgroundPanelOpen = false }
        }
        .onChange(of: textFocus) { _, focus in
            // Interactive keyboard dismissal clears focus without going
            // through the Done button; keep the editing state in sync. The
            // color sheet lowers the keyboard on purpose and keeps writing.
            if focus == nil, editor.editingTextItemID != nil, colorRequest == nil {
                endTextEditing()
            }
        }
        .onChange(of: editingBlock?.text) { _, text in noteTyped(text) }
    }

    // MARK: Bottom cluster (instrument panel + context bar)

    @ViewBuilder private var bottomCluster: some View {
        // While words are being written the accordion takes the bottom
        // slot: above the software keyboard when there is one, at the
        // screen bottom with a hardware keyboard -- visible either way
        // (it used to ride the keyboard toolbar, which a connected
        // hardware keyboard simply never shows).
        if editor.editingTextItemID != nil {
            // The dock keeps its room, so the page keeps its size; the
            // keyboard and the text chrome ride over it (CanvasScene.body).
            Color.clear.frame(height: 40)
            if colorRequest != nil {
                // Screens 14 and 20: the keyboard is down and the composer
                // is back under the sheet; a tap there is a tap outside it.
                MiraBar(
                    coordinator: mira,
                    editor: editor,
                    prompt: $miraPrompt,
                    promptFocus: $miraFocus,
                    placeholder: "Type or polish your memory"
                )
                .allowsHitTesting(false)
                .contentShape(Rectangle())
                .onTapGesture { closeColorSheet(keeping: false) }
            } else {
                Color.clear.frame(height: 54)
            }
        } else if textModeArming {
            InputModeBar(active: .text, onSelect: handleTool)
            MiraBar(
                coordinator: mira,
                editor: editor,
                prompt: $miraPrompt,
                promptFocus: $miraFocus,
                placeholder: "Type or polish your memory"
            )
        } else {
            if pendingPlacement != nil {
                HStack(spacing: 8) {
                    Text("Tap where it should go.")
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityIdentifier("canvas.place.hint")
                    Spacer(minLength: 0)
                    Button("Cancel") { pendingPlacement = nil }
                        .font(.miraCaption)
                        .accessibilityIdentifier("canvas.place.cancel")
                }
                .padding(.horizontal, Metrics.chromeInset)
                .transition(.opacity)
            } else if let gestureHint {
                Text(gestureHint)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.chromeInset)
                    .transition(.opacity)
            }
            if let editingImageItem, let session = photoSession, session.itemID == editingImageItem {
                PhotoEditPanel(
                    editor: editor,
                    itemID: editingImageItem,
                    studio: imageStudio,
                    onClose: {
                        // A slow AI edit for photo A finishing while B is
                        // open must not close B's panel.
                        guard self.editingImageItem == editingImageItem else { return }
                        revealItem = editingImageItem
                        self.editingImageItem = nil
                    },
                    comparing: $comparingImage,
                    original: session.original,
                    edited: session.edited,
                    // Only this photo's session: a slow AI edit for A that
                    // lands after B was opened must not mark B as edited.
                    // One that lands after A's panel closed is still A's.
                    onEdited: {
                        guard photoSession?.itemID == editingImageItem else { return }
                        photoSession?.edited = true
                        notePhotoSeen(editingImageItem)
                    }
                )
                // A new photo gets fresh panel state (section, notices).
                .id(editingImageItem)
                InputModeBar(active: .image, onSelect: handleTool)
            } else if let editingStickerItem {
                StickerEditPanel(
                    editor: editor,
                    itemID: editingStickerItem,
                    studio: imageStudio,
                    onClose: {
                        revealItem = editingStickerItem
                        self.editingStickerItem = nil
                    }
                )
            } else if backgroundPanelOpen {
                BackgroundPanel(
                    editor: editor,
                    // Never cancel a running turn by starting another.
                    onAsk: { words in
                        guard !mira.isWorking else { return }
                        mira.ask(words, editor: editor)
                    },
                    onClose: { backgroundPanelOpen = false }
                )
                InputModeBar(active: .background, onSelect: handleTool)
            } else {
                recorderCluster
            }
        }
    }

    @ViewBuilder private var recorderCluster: some View {
        switch recorderState {
        case .idle:
            if let recorderNotice {
                Text(recorderNotice)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.chromeInset)
            }
            InputModeBar(active: nil, onSelect: handleTool)
            // The card and the bar are one conversational dock.
            VStack(spacing: 6) {
                MiraCard(
                    coordinator: mira,
                    editor: editor,
                    onAsk: { mira.ask($0, editor: editor) },
                    onRephrase: { miraFocus = true },
                    onRetry: {
                        miraPrompt = ""
                        mira.retry(editor: editor)
                    }
                )
                MiraBar(
                    coordinator: mira,
                    editor: editor,
                    prompt: $miraPrompt,
                    promptFocus: $miraFocus,
                    placeholder: editor.selectedItemID != nil ? "Ask Mira to refine..." : "Ask Mira anything"
                )
            }
        case .armed:
            InputModeBar(active: .voice, onSelect: handleTool)
            armedBar
        case .recording(let start):
            InputModeBar(active: .voice, onSelect: handleTool)
            recordingBar(since: start)
        case .review(_, let duration):
            InputModeBar(active: .voice, onSelect: handleTool)
            reviewBar(duration: duration)
        }
    }

    private func handleTool(_ mode: EditorMode) {
        // Any tool tap closes the edit panels first -- one owner of
        // the bottom cluster at a time. Background toggles its own panel.
        editingImageItem = nil
        editingStickerItem = nil
        let backgroundWasOpen = backgroundPanelOpen
        backgroundPanelOpen = false
        switch mode {
        case .background:
            // Same guards as the recorder: the panel would unmount a live
            // Mira turn's Stop, and a take being recorded or reviewed is not
            // thrown away by the tool beside Voice (an armed one folds).
            guard !mira.isWorking else { return }
            switch recorderState {
            case .recording, .review: return
            case .idle, .armed: break
            }
            cancelRecording()
            backgroundPanelOpen = !backgroundWasOpen
        case .text:
            guard !textModeArming else { return }
            armTextMode()
        case .voice:
            // The tool arms the recorder; only the Record button goes live.
            // One audio owner at a time: not while dictating, and recording
            // would unmount the Mira strip mid-turn.
            switch recorderState {
            case .idle where !dictating && !mira.isWorking:
                recorderState = .armed
            case .armed:
                recorderState = .idle
            default:
                break
            }
        case .image:
            cancelRecording()
            actions.selectMode(.image)
        case .sticker:
            cancelRecording()
            actions.selectMode(.sticker)
        }
    }

    /// A tool open in place over the canvas (Background, photo or sticker
    /// editing). The handoff's leading pill then reads "Canvas" and folds
    /// the tool away (screen 05); on the bare canvas it is the way Home.
    private var toolOpen: Bool {
        backgroundPanelOpen || editingImageItem != nil || editingStickerItem != nil
    }

    private func closeTool() {
        backgroundPanelOpen = false
        if let id = editingImageItem {
            revealItem = id
            editingImageItem = nil
        }
        if let id = editingStickerItem {
            revealItem = id
            editingStickerItem = nil
        }
    }

    private func finishToolsOnboarding(openBackground: Bool) {
        HintCenter.graduate(ToolsOnboarding.hintID)
        withAnimation(.easeOut(duration: 0.2)) { showsToolsOnboarding = false }
        // Open, never toggle shut: the tool's tap toggles.
        if openBackground, !backgroundPanelOpen { handleTool(.background) }
    }

    /// The photo session's photo as it looks now (PhotoSession.lastSeen).
    private func notePhotoSeen(_ id: CanvasItem.ID) {
        guard photoSession?.itemID == id, case .image(let ref) = editor.item(id)?.content else { return }
        photoSession?.lastSeen = ref
    }

    /// Photos that predate the vision feature -- or whose import-time
    /// describe has not landed yet -- get looked at here. Runs on page
    /// open AND before every Mira turn (bounded), so an ask never races
    /// the look.
    private func lookAtUnseenPhotos() async {
        let unseen = editor.items.compactMap { item -> (CanvasItem.ID, Data)? in
            guard case .image(let ref) = item.content,
                  ref.summary.isEmpty, !ref.fileName.isEmpty,
                  let data = imageStore.data(forFileName: ref.fileName) else { return nil }
            return (item.id, data)
        }
        guard !unseen.isEmpty else { return }
        let editor = self.editor
        let studio = self.imageStudio
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for (id, data) in unseen {
                    guard let summary = try? await studio.describe(image: data) else { continue }
                    await MainActor.run { editor.setImageSummary(itemID: id, to: summary) }
                }
            }
            group.addTask {
                // Vision takes seconds; never hold an ask hostage longer.
                try? await Task.sleep(for: .seconds(8))
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Opening a page re-measures every text block against its real font
    /// metrics -- drafted and legacy pages arrive with estimated heights.
    private func remeasureTextBlocks() {
        for item in editor.items {
            guard case .text(let block) = item.content else { continue }
            editor.autosizeTextHeight(itemID: item.id, to: TextMeasure.blockHeight(
                text: block.text,
                pointSize: block.pointSize,
                fontName: block.fontName,
                width: item.size.width
            ))
        }
    }

    /// Ending an editing session on a blank block removes it -- no empty
    /// husks left on the page (and no undo step burned on the cleanup).
    private func cleanUpEmptyText() {
        for item in editor.items {
            if case .text(let block) = item.content,
               block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                editor.discardAbandonedText(itemID: item.id)
            }
        }
    }
}

// MARK: - Sound recording, accessory, pending tools

extension CanvasScene {
    // MARK: Sound recording

    func startRecording() {
        guard recorder == nil else { return }
        recorderNotice = nil
        let newRecorder = recorderFactory()
        recorder = newRecorder
        Task {
            do {
                try await newRecorder.start()
                recorderState = .recording(start: .now)
            } catch {
                recorder = nil
                recorderState = .idle
                recorderNotice = error.localizedDescription
            }
        }
    }

    /// Stops and discards an in-flight recording (leaving the canvas, or
    /// switching tools mid-recording). Keeps the audio session tidy.
    func cancelRecording() {
        guard recorder != nil || !isIdle else { return }
        let abandoned = recorder
        recorder = nil
        recorderState = .idle
        Task { _ = try? await abandoned?.stop() }
    }

    private var isIdle: Bool {
        if case .idle = recorderState { return true }
        return false
    }

    func stopRecording() {
        guard let recorder, case .recording(let start) = recorderState else { return }
        Task {
            let data = (try? await recorder.stop()) ?? Data()
            // Discarded while the recorder wound down (or a new take began):
            // this take must not come back as a review.
            guard case .recording(let current) = recorderState, current == start else { return }
            self.recorder = nil
            guard !data.isEmpty else {
                recorderState = .idle
                return
            }
            let measured = AudioInfo.duration(of: data)
            let elapsed = Date.now.timeIntervalSince(start)
            recorderState = .review(data: data, duration: measured > 0 ? measured : max(1, elapsed))
        }
    }

    func keepRecording() {
        guard case .review(let data, let duration) = recorderState else { return }
        var clip = SoundClip(duration: duration, note: reviewNote)
        if let fileName = try? soundStore.save(data, id: clip.id) {
            clip.fileName = fileName
        }
        let position = CGPoint(x: 130, y: min(editor.contentBottom + 60, 4000))
        editor.addSound(clip, at: position)
        reviewNote = ""
        recorderState = .idle
    }

    // MARK: Pending tool from other scenes

    private func consumePendingTool() {
        guard let tool = pendingTool else { return }
        pendingTool = nil
        handleTool(tool)
    }

    /// The canvas half of "generate, then say where it goes". The picture lands
    /// centred on the tap and arrives selected, so it is already under the
    /// thumb for a nudge instead of parked at the bottom of the page.
    private func placePending(at point: CGPoint) -> CanvasItem.ID? {
        guard let pending = pendingPlacement else { return nil }
        pendingPlacement = nil
        let id: CanvasItem.ID?
        if pending.isSticker {
            id = editor.addSticker(
                GeneratedSticker(
                    prompt: pending.prompt, symbolName: "sparkles", fileName: pending.fileName
                ),
                at: point
            )
        } else {
            id = editor.addImages(
                [ImageRef(displayName: pending.prompt, fileName: pending.fileName)],
                around: point
            ).first
        }
        if let id { editor.select(id) }
        return id
    }

    static func timestamp(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

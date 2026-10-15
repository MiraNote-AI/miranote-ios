import MiraNoteKit
import PhotosUI
import SwiftUI

/// The base editor: the infinite canvas plus the five-tool bar. Background,
/// Voice, Text and Image act directly on the canvas -- Background lays its
/// glass sheet over the card (screen 05), Image opens its sheets in place
/// and lifts a photo into its editor (23-29), Voice swaps the bottom bar for
/// a recorder, Text drops an editable block; Sticker leaves for its panel.
/// The composer opens the Mira canvas chat (06); a landed change waits on
/// the result sheet (07); a dragged element floats above the dock over the
/// composer's delete zone (22). Header is Home (Canvas while a tool is open
/// in place) / undo / Save; Save still files the page and leaves. Writing
/// reads Cancel / Done, picking photos Cancel / Add, a lifted photo
/// Cancel / Done.
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
    /// The take Stop just put on the page, while its result sheet shows.
    @State var attachedSound: AttachedSound?
    /// The text tool whose row is open (screen 11: Aa when writing starts).
    @State var textTool: TextTool = .font
    @State var rewrite: RewriteState?
    @State var colorRequest: ColorRequest?
    /// The beat between tapping Text and the block appearing (screen 10):
    /// the Text tool shows active and the composer reads as text entry.
    @State var textModeArming = false
    /// The dictation strip's press in progress.
    @State var dictationPress: (start: Date, wasLive: Bool)?
    @State var miraPrompt = ""
    /// The Mira canvas chat (screen 06) is up over the canvas.
    @State var miraChatOpen = false
    @State var miraDictation: DictationStripState = .idle
    /// The finger is still on the dictation strip.
    @State var miraHoldActive = false
    /// The Background tool's composer words ("Apply to this page").
    @State private var applyWords = ""
    @FocusState private var applyFocus: Bool
    @State private var gestureHint: String?
    @State private var editingImageItem: CanvasItem.ID?
    /// The lifted photo's editor state (tile, words, compare), while
    /// `editingImageItem` is set.
    @State private var photoEdit: PhotoEditController?
    /// The Image tool, open in place over the live canvas; nil when closed.
    @State private var imagePhase: ImagePhase?
    @State private var recentPhotos = RecentPhotos()
    @State private var libraryPicks: [LibraryPhoto] = []
    @State private var importingPicks = false
    /// The photos this Image visit placed: its Cancel takes them back.
    @State private var placedThisVisit: [CanvasItem.ID] = []
    @State private var imageNotice: String?
    @State private var showsCamera = false
    /// The photo editing session: which photo, how it looked when editing
    /// began, and whether it has been edited since. It outlives the panel
    /// (an AI edit closes it, a caption edit rebuilds it) and ends when
    /// another photo is opened.
    @State private var photoSession: PhotoSession?
    @State private var editingStickerItem: CanvasItem.ID?
    /// The element an edit panel just closed on, scrolled into view.
    @State private var revealItem: CanvasItem.ID?
    @State var backgroundPanelOpen = false
    /// The Background tool's custom page color sheet, while it is up.
    @State var pageColorEdit: PageColorEdit?
    @State private var showsToolsOnboarding = false
    @State private var dropToDelete: DropToDelete?
    @State private var lifted: LiftedElement?
    #if DEBUG
    /// -UITEST only: the drop-zone phases one drag went through. XCUITest
    /// cannot look mid-drag, so the trail is left for it to read.
    @State var dropZoneTrail: [String] = []
    #endif
    @State var dictating = false
    /// The dictation strip's subtitle when the mic is not live: why nothing
    /// landed, or why a rewrite failed.
    @State var dictationHint: String?
    @FocusState var textFocus: CanvasItem.ID?
    @FocusState var miraFocus: Bool

    private let soundStore = SoundFileStore()
    private let imageStore = ImageFileStore()
    private let favoritesStore = StickerFavoritesStore.forCurrentProcess()

    /// Words are being written (or the Text tool is on its way in): the
    /// header reads Cancel / undo / Done, and Done ends the writing.
    private var writing: Bool { editor.editingTextItemID != nil || textModeArming }

    var body: some View {
        Group {
            if showsToolsOnboarding {
                toolsOnboarding
            } else {
                canvas
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
    }

    /// Handoff screen 03: Back (to the blank canvas) / undo / Next (on to
    /// Background), the card in the canvas slot, no tool bar -- its 40 pt
    /// stays empty so the card keeps the canvas card's frame -- and the
    /// "Choose your background" bar in the composer's place.
    private var toolsOnboarding: some View {
        EditorScaffold(
            leading: "Back",
            trailing: "Next",
            onLeading: { finishToolsOnboarding(then: nil) },
            onTrailing: { finishToolsOnboarding(then: .background) },
            onUndo: {},
            undoEnabled: false
        ) {
            ToolsOnboarding(onPick: { finishToolsOnboarding(then: $0) })
        } bottom: {
            Color.clear.frame(height: 40)
            ToolsOnboardingBar(onGo: { finishToolsOnboarding(then: .background) })
        }
        // The two-finger scrub is Back, as on any pushed screen.
        .accessibilityAction(.escape) { finishToolsOnboarding(then: nil) }
        .transition(.opacity)
    }

    /// The canvas with the text chrome floating over it.
    private var canvas: some View {
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
            if pageColorEdit != nil {
                // A tap anywhere outside the sheet cancels it.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closePageColorSheet(keeping: false) }
                pageColorSheet.padding(.bottom, 54 + 14 + 2)
            }
        }
        .onChange(of: backgroundPanelOpen) { _, open in
            if !open { closePageColorSheet(keeping: false) }
        }
    }

    /// The canvas scene proper: header, page, dock, and the scene's
    /// lifecycle (the canvas adds the floating text chrome).
    private var scaffold: some View {
        let header = self.header
        return EditorScaffold(
            leading: header.leading,
            trailing: header.trailing,
            onLeading: header.onLeading,
            onTrailing: header.onTrailing,
            onUndo: writing ? undoFromHeader : editor.undo,
            undoEnabled: editor.canUndo,
            leadingMuted: !writing,
            leadingID: writing ? "text.cancel" : nil,
            trailingID: writing ? "keyboard.done" : nil,
            // Screen 07: Save turns forest while a Mira change waits.
            trailingFill: receipt == nil || writing ? Palette.ink : Palette.forest,
            dimmed: editor.editingTextItemID != nil,
            scrimmed: editingImageItem != nil,
            onScrimTap: closePhotoEditor
        ) {
            board
                .overlay(alignment: .top) {
                    if backgroundPanelOpen {
                        backgroundSheet
                    }
                }
                .overlay(alignment: .bottom) {
                    if let receipt {
                        // Screen 07: what Mira changed and what she kept.
                        ResultSheet(
                            title: receipt.changed,
                            detail: receipt.kept,
                            titleID: "mira.receipt",
                            detailID: "mira.kept",
                            canRevert: mira.receiptCanRevert,
                            revertID: "mira.revert",
                            keepID: "mira.keep",
                            onRevert: { mira.revert(editor: editor) },
                            onKeep: { mira.dismiss() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: receipt)
                .overlay {
                    // With the color sheet up, a tap on the page cancels it
                    // instead of ending the writing.
                    if colorRequest != nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { closeColorSheet(keeping: false) }
                    }
                }
        } sheet: {
            toolSheet
        } bottom: {
            // One container: the zone sits on its last 54 pt -- the
            // composer's slot on the idle canvas (screen 22).
            VStack(spacing: 16) { bottomCluster }
                .overlay(alignment: .bottom) {
                    if dropToDelete != nil {
                        DeleteDropZone()
                            .transition(.opacity)
                    }
                }
                // Screen 09: the result sheet floats over the canvas card's
                // foot, its bottom 20 above the tool bar.
                .overlay(alignment: .top) {
                    if attachedSound != nil, dropToDelete == nil {
                        soundAttachedSheet
                            .offset(y: -(ResultSheet.height + Metrics.canvasToToolBar))
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: dropToDelete)
                .animation(.easeOut(duration: 0.2), value: attachedSound)
        }
        .overlay {
            if let lifted, dropToDelete != nil {
                LiftedElementLayer(lifted: lifted, armed: dropToDelete == .armed, textFocus: $textFocus)
            }
        }
        .overlay {
            if miraChatOpen {
                miraChat
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: miraChatOpen)
        #if DEBUG
        .background(dropZoneTrailProbe)
        #endif
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
            // Same for the attached take: Revert would undo something else.
            if let attachedSound, attachedSound.changeCount != editor.changeCount {
                self.attachedSound = nil
            }
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
        .onChange(of: editingImageItem) { left, now in
            // The panel let go of a photo: its session picks up from here,
            // unless something else changes the photo first (#102).
            if let left { notePhotoSeen(left) }
            if now == nil { photoEdit = nil }
        }
        .sheet(isPresented: $showsCamera) {
            CameraCapture { image in
                guard let data = image.downscaled(), let id = placer.place(data, name: "Camera photo") else {
                    imageNotice = "That photo couldn't be saved. Try again?"
                    return
                }
                placedThisVisit.append(id)
                imagePhase = .placed
            }
            .ignoresSafeArea()
        }
        .onChange(of: dropToDelete) { _, phase in
            // Moving an element lowers any keyboard -- canvas text already
            // ends editing; the composers must too, or a drop over the
            // keyboard would delete with no sign over it.
            if phase != nil {
                miraFocus = false
                applyFocus = false
            }
            #if DEBUG
            dropZoneTrail.append(phase.map { $0 == .armed ? "armed" : "dragging" } ?? "none")
            #endif
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

    private var board: some View {
        CanvasBoardView(
            editor: editor,
            soundStore: soundStore,
            textFocus: $textFocus,
            workingItemIDs: mira.workingItemIDs,
            onEditImage: openPhotoEditor,
            onEditSticker: { id in
                guard !mira.isWorking else { return }
                cancelRecording()
                cancelDictationIfNeeded()
                backgroundPanelOpen = false
                editingStickerItem = id
            },
            onPaperTap: {
                // An armed recorder holds nothing yet, so a paper tap
                // folds it like it folds the text tools. Recording keeps
                // its bar: a stray tap must not lose audio.
                if case .armed = recorderState { recorderState = .idle }
                // The Background card is a tool too: the paper folds it,
                // and the Image tool before anything is picked.
                backgroundPanelOpen = false
                if imagePhase == .choose { endImageVisit() }
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
            lifted: $lifted,
            pendingSoundMarker: pendingSoundMarker
        )
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
                    placeholder: "Type or polish your memory",
                    onOpenChat: {}
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
                placeholder: "Type or polish your memory",
                onOpenChat: openMiraChat
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
            if editingImageItem != nil, let photoEdit {
                InputModeBar(active: .image, onSelect: handleTool)
                PhotoEditComposer(controller: photoEdit)
            } else if let imagePhase {
                InputModeBar(active: .image, onSelect: handleTool)
                imageComposer(imagePhase)
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
                // The tool's sheet lies over the canvas; the composer below
                // asks Mira to paint a backdrop from words (screen 05).
                InputModeBar(active: .background, onSelect: handleTool)
                BackgroundApplyBar(
                    words: $applyWords,
                    focus: $applyFocus,
                    canApply: !mira.isWorking,
                    onApply: { mira.askBackground($0, editor: editor) }
                )
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
            // Voice stays lit while its take's result sheet shows (09).
            InputModeBar(active: attachedSound == nil ? nil : .voice, onSelect: handleTool)
            // The card and the bar are one conversational dock.
            VStack(spacing: 6) {
                MiraCard(
                    coordinator: mira,
                    editor: editor,
                    onAsk: { mira.ask($0, editor: editor) },
                    onRephrase: openMiraChat,
                    onRetry: {
                        miraPrompt = ""
                        mira.retry(editor: editor)
                    }
                )
                MiraBar(
                    coordinator: mira,
                    editor: editor,
                    prompt: $miraPrompt,
                    placeholder: composerPlaceholder,
                    onOpenChat: openMiraChat
                )
            }
        case .armed:
            InputModeBar(active: .voice, onSelect: handleTool)
            armedBar
        case .recording(let start):
            InputModeBar(active: .voice, onSelect: handleTool)
            if let recorder {
                recordingBar(since: start, recorder: recorder)
            }
        }
    }

    /// The composer's context copy: beside a new take (screen 09), with an
    /// element selected (21) or while a Mira result waits (07).
    private var composerPlaceholder: String {
        if attachedSound != nil { return "Ask Mira to adjust sound..." }
        return receipt == nil && editor.selectedItemID == nil ? "Ask Mira anything" : "Ask Mira to refine..."
    }

    /// While a take records, where it will land (screen 08).
    private var pendingSoundMarker: CGPoint? {
        guard case .recording = recorderState else { return nil }
        // The marker's ring sits at the leading edge of addSound's 200 pt box.
        let landing = soundLanding
        return CGPoint(x: landing.x - 100 + CanvasElementView.soundRing / 2, y: landing.y)
    }

    /// Where Stop puts a take: on a blank page where screen 09 draws its
    /// marker, otherwise just below the lowest element.
    private var soundLanding: CGPoint {
        CGPoint(x: 209, y: min(max(190, editor.contentBottom + 60), 4000))
    }

    private func handleTool(_ mode: EditorMode) {
        // Any tool tap closes the edit panels first -- one owner of
        // the bottom cluster at a time. Background toggles its own panel.
        editingImageItem = nil
        editingStickerItem = nil
        // Moving on keeps an attached take (its sheet's Keep).
        attachedSound = nil
        let backgroundWasOpen = backgroundPanelOpen
        backgroundPanelOpen = false
        // Another tool keeps the photos this Image visit placed (as Add);
        // the Image tool itself toggles shut only from its first sheet.
        let imageWasOpen = imagePhase
        if mode != .image { endImageVisit() }
        switch mode {
        case .background:
            // Same guards as the recorder: the panel would unmount a live
            // Mira turn's Stop, and a take being recorded is not thrown
            // away by the tool beside Voice (an armed one folds).
            guard !mira.isWorking else { return }
            if case .recording = recorderState { return }
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
            switch imageWasOpen {
            case nil: openImageTool()
            case .choose: endImageVisit()
            // Picking or placed: the tap brings back the first sheet.
            case .library, .placed: imagePhase = .choose
            }
        case .sticker:
            cancelRecording()
            actions.selectMode(.sticker)
        }
    }

    /// A tool open in place over the canvas (Background, photo or sticker
    /// editing). The handoff's leading pill then reads "Canvas" and folds
    /// the tool away (screen 05); on the bare canvas it is the way Home.
    private var toolOpen: Bool {
        backgroundPanelOpen || editingImageItem != nil || editingStickerItem != nil || imagePhase != nil
    }

    private func closeTool() {
        backgroundPanelOpen = false
        endImageVisit()
        if let id = editingImageItem {
            revealItem = id
            editingImageItem = nil
        }
        if let id = editingStickerItem {
            revealItem = id
            editingStickerItem = nil
        }
    }

    // MARK: Header

    private struct Header {
        let leading: String
        let trailing: String
        let onLeading: () -> Void
        let onTrailing: () -> Void
    }

    /// The handoff's labels per state: writing reads Cancel / Done (screens
    /// 10-20), a lifted photo Cancel / Done (27), picking and placed photos
    /// Cancel / Add (24-29), any other open tool Canvas / Save (05, 23), the
    /// bare canvas Home / Save.
    private var header: Header {
        if writing {
            return Header(leading: "Cancel", trailing: "Done",
                          onLeading: cancelTextEditing, onTrailing: endTextEditing)
        }
        if editingImageItem != nil {
            return Header(leading: "Cancel", trailing: "Done",
                          onLeading: cancelPhotoEdit, onTrailing: closePhotoEditor)
        }
        switch imagePhase {
        case .library:
            return Header(leading: "Cancel", trailing: "Add", onLeading: {
                libraryPicks = []
                imagePhase = placedThisVisit.isEmpty ? .choose : .placed
            }, onTrailing: addPicks)
        case .placed:
            return Header(leading: "Cancel", trailing: "Add",
                          onLeading: cancelImageVisit, onTrailing: endImageVisit)
        case .choose, nil:
            return Header(leading: toolOpen ? "Canvas" : "Home", trailing: "Save",
                          onLeading: toolOpen ? closeTool : actions.leading, onTrailing: actions.done)
        }
    }

    // MARK: Image tool (handoff screens 23-26, 29)

    private var placer: PhotoPlacer { PhotoPlacer(editor: editor, studio: imageStudio) }

    private func openImageTool() {
        imageNotice = nil
        libraryPicks = []
        placedThisVisit = []
        imagePhase = .choose
    }

    /// Closes the Image tool keeping what it placed (Add, another tool).
    private func endImageVisit() {
        imagePhase = nil
        libraryPicks = []
        placedThisVisit = []
        imageNotice = nil
    }

    /// Cancel after placing: this visit's photos come off as one step.
    private func cancelImageVisit() {
        editor.remove(itemIDs: placedThisVisit)
        endImageVisit()
    }

    @ViewBuilder private var toolSheet: some View {
        if editingImageItem != nil, let photoEdit, let session = photoSession,
           session.itemID == photoEdit.itemID {
            PhotoEditOverlay(
                controller: photoEdit,
                original: session.original,
                edited: session.edited,
                onUndo: editor.undo
            )
        } else if editor.editingTextItemID == nil {
            switch imagePhase {
            case .choose:
                ChoosePhotosSheet(
                    notice: imageNotice,
                    onLibrary: { imagePhase = .library },
                    onCamera: {
                        if CameraCapture.isAvailable {
                            showsCamera = true
                        } else {
                            imageNotice = "The camera isn't available here."
                        }
                    },
                    onSticker: { handleTool(.sticker) },
                    onSamples: placeSamples
                )
                .transition(.opacity)
            case .library:
                RecentsSheet(
                    library: recentPhotos,
                    selection: $libraryPicks,
                    onEditing: editPick,
                    onSystemPicks: { items in
                        importPicks(load: { await placer.place(items) }) { _ in imagePhase = .placed }
                    }
                )
                .transition(.opacity)
            case .placed, nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func imageComposer(_ phase: ImagePhase) -> some View {
        switch phase {
        case .choose:
            ToolComposer(
                placeholder: "Open Photo Library",
                action: "Go",
                fieldID: "image.composer",
                actionID: "image.composer.go",
                onAction: { imagePhase = .library }
            )
        case .library, .placed:
            ToolComposer(
                placeholder: "Add selected photos to canvas",
                action: "Add",
                actionEnabled: phase == .placed || (!libraryPicks.isEmpty && !importingPicks),
                fieldID: "image.composer",
                actionID: "image.composer.add",
                onAction: {
                    // Placed: Add opens the grid for more.
                    if phase == .placed { imagePhase = .library } else { addPicks() }
                }
            )
        }
    }

    private func addPicks() {
        guard !libraryPicks.isEmpty else { return }
        importPicks(load: libraryLoad) { _ in imagePhase = .placed }
    }

    /// Screen 26: one pick, "Editing" -- it lands, and lifts straight into
    /// the photo editor; Done returns to the placed state (29).
    private func editPick() {
        importPicks(load: libraryLoad) { ids in
            imagePhase = .placed
            guard let id = ids.first else { return }
            editor.select(id)
            openPhotoEditor(id)
        }
    }

    /// Places the grid's picks; nothing when none are picked.
    private var libraryLoad: () async -> [CanvasItem.ID] {
        let picks = libraryPicks
        let library = recentPhotos
        let placer = self.placer
        return { placer.place(await library.data(for: picks)) }
    }

    private func importPicks(
        load: @escaping () async -> [CanvasItem.ID],
        then: @escaping ([CanvasItem.ID]) -> Void
    ) {
        guard !importingPicks else { return }
        importingPicks = true
        Task {
            let ids = await load()
            importingPicks = false
            libraryPicks = []
            guard !ids.isEmpty else {
                imageNotice = "Those photos couldn't be imported. Try different ones?"
                imagePhase = .choose
                return
            }
            placedThisVisit += ids
            then(ids)
        }
    }

    private func placeSamples() {
        #if DEBUG
        placedThisVisit += placer.placeSamples()
        imagePhase = .placed
        #endif
    }

    // MARK: Photo editor (handoff screens 27-28)

    /// Lifts a photo into the editor. Never while a Mira turn runs (the
    /// editor takes the bottom cluster and would unmount its Stop); the
    /// mic stops first.
    private func openPhotoEditor(_ id: CanvasItem.ID) {
        guard !mira.isWorking, case .image(let ref) = editor.item(id)?.content else { return }
        cancelRecording()
        cancelDictationIfNeeded()
        backgroundPanelOpen = false
        if photoSession?.continues(id, showing: ref) != true {
            photoSession = PhotoSession(itemID: id, original: ref)
        }
        photoEdit = PhotoEditController(
            itemID: id,
            editor: editor,
            studio: imageStudio,
            // Only this photo's session: a slow AI edit for A that lands
            // after B was opened must not mark B as edited. One that lands
            // after A's editor closed is still A's.
            onEdited: {
                guard photoSession?.itemID == id else { return }
                photoSession?.edited = true
                notePhotoSeen(id)
            },
            onClose: {
                // A slow edit for photo A finishing while B is open must
                // not close B's editor.
                guard editingImageItem == id else { return }
                closePhotoEditor()
            }
        )
        editingImageItem = id
    }

    private func closePhotoEditor() {
        guard let id = editingImageItem else { return }
        revealItem = id
        editingImageItem = nil
    }

    /// Cancel puts the photo back the way it was when editing began -- one
    /// undoable step, none if unchanged -- and closes.
    private func cancelPhotoEdit() {
        if let id = editingImageItem, let session = photoSession, session.itemID == id {
            editor.restoreImage(itemID: id, to: session.original)
        }
        closePhotoEditor()
    }

    /// Graduates the introduction and lands on the canvas -- with `tool`
    /// opened when one was picked (Next and Go pick Background).
    private func finishToolsOnboarding(then tool: EditorMode?) {
        HintCenter.graduate(ToolsOnboarding.hintID)
        withAnimation(.easeOut(duration: 0.2)) { showsToolsOnboarding = false }
        guard let tool, !(tool == .background && backgroundPanelOpen) else { return }
        // Next turn, once the canvas is mounted: a new text block's focus
        // needs its field on screen. (Open, never toggle shut: the
        // Background tool's tap toggles.)
        Task { @MainActor in handleTool(tool) }
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
            // this take must not land after all.
            guard case .recording(let current) = recorderState, current == start else { return }
            self.recorder = nil
            recorderState = .idle
            guard !data.isEmpty else { return }
            let measured = AudioInfo.duration(of: data)
            let elapsed = Date.now.timeIntervalSince(start)
            attach(data, duration: measured > 0 ? measured : max(1, elapsed))
        }
    }

    /// Handoff screen 09, attach first: the take goes on the page as one
    /// undo step, where its marker pulsed, and the result sheet offers
    /// Revert / Keep.
    private func attach(_ data: Data, duration: TimeInterval) {
        var clip = SoundClip(duration: duration)
        if let fileName = try? soundStore.save(data, id: clip.id) {
            clip.fileName = fileName
        }
        let id = editor.addSound(clip, at: soundLanding)
        attachedSound = AttachedSound(itemID: id, changeCount: editor.changeCount)
    }

    /// Takes the attached take off the page again -- the add is still the
    /// last change, or the sheet would have stepped aside -- so Voice can
    /// record it over.
    func revertAttachedSound() {
        guard let attachedSound, attachedSound.changeCount == editor.changeCount else { return }
        self.attachedSound = nil
        editor.undo()
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

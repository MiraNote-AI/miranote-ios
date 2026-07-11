import MiraNoteKit
import SwiftUI

/// The base editor (v2.1): the infinite canvas plus the three-mode
/// instrument panel. Text and Sound act directly on the canvas -- Text drops
/// an editable block, Sound swaps the bottom bar for a recorder; only Image
/// leaves for its panel. Header is back / undo / Done.
struct CanvasScene: View {
    @Bindable var editor: CanvasViewModel
    @Bindable var mira: MiraCanvasCoordinator
    var imageStudio: ImageStudioService = MockImageStudioService()
    var actions = EditorActions()
    /// A tool requested from another scene (consumed on appear/change).
    @Binding var pendingTool: EditorMode?
    var recorderFactory: @MainActor () -> AudioRecording = { AudioRecorder() }
    var transcription: VoiceTranscriptionService = MockVoiceTranscriptionService()

    @State var recorderState: RecorderState = .idle
    @State var recorder: AudioRecording?
    @State var recorderNotice: String?
    @State var reviewNote = ""
    @State var accessoryRow: AccessoryRow = .tools
    @State private var miraPrompt = ""
    @State private var gestureHint: String?
    @State private var editingImageItem: CanvasItem.ID?
    @State private var editingStickerItem: CanvasItem.ID?
    @State var dictating = false
    /// Inline feedback in the text accessory: "Listening..." while the
    /// mic is live, or why nothing landed after it stopped.
    @State var dictationHint: String?
    @FocusState var textFocus: CanvasItem.ID?
    @FocusState private var miraFocus: Bool

    private let soundStore = SoundFileStore()
    private let imageStore = ImageFileStore()

    var body: some View {
        EditorScaffold(
            leading: "Home",
            leadingSymbol: "chevron.left",
            onLeading: actions.leading,
            onTrailing: actions.done,
            onUndo: editor.undo,
            undoEnabled: editor.canUndo
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
                    editingImageItem = id
                },
                onEditSticker: { id in
                    guard !mira.isWorking else { return }
                    cancelRecording()
                    cancelDictationIfNeeded()
                    editingStickerItem = id
                }
            )
        } bottom: {
            bottomCluster
        }
        .onAppear {
            remeasureTextBlocks()
            mira.prepareTurn = { await lookAtUnseenPhotos() }
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
                cleanUpEmptyText()
                cancelDictationIfNeeded()
            }
        }
        .onChange(of: textFocus) { _, focus in
            // Interactive keyboard dismissal clears focus without going
            // through the Done button; keep the editing state in sync.
            if focus == nil, editor.editingTextItemID != nil {
                editor.endEditingText()
                accessoryRow = .tools
            }
        }
    }

    // MARK: Bottom cluster (instrument panel + context bar)

    @ViewBuilder private var bottomCluster: some View {
        // While words are being written the accordion takes the bottom
        // slot: above the software keyboard when there is one, at the
        // screen bottom with a hardware keyboard -- visible either way
        // (it used to ride the keyboard toolbar, which a connected
        // hardware keyboard simply never shows).
        if editor.editingTextItemID != nil {
            HStack(spacing: 18) {
                textAccessory
            }
            .font(.miraLabel)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Palette.onInk)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
            )
            .padding(.horizontal, Metrics.screenPadding)
        } else {
            if let gestureHint {
                Text(gestureHint)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.screenPadding)
                    .transition(.opacity)
            }
            if let editingImageItem {
                PhotoEditPanel(
                    editor: editor,
                    itemID: editingImageItem,
                    studio: imageStudio,
                    onClose: { self.editingImageItem = nil }
                )
                InputModeBar(active: .image, onSelect: handleTool)
            } else if let editingStickerItem {
                StickerEditPanel(
                    editor: editor,
                    itemID: editingStickerItem,
                    studio: imageStudio,
                    onClose: { self.editingStickerItem = nil }
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
                    .padding(.horizontal, Metrics.screenPadding)
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
                    promptFocus: $miraFocus
                )
            }
        case .armed:
            InputModeBar(active: .sound, onSelect: handleTool)
            armedBar
        case .recording(let start):
            InputModeBar(active: .sound, onSelect: handleTool)
            recordingBar(since: start)
        case .review(_, let duration):
            InputModeBar(active: .sound, onSelect: handleTool)
            reviewBar(duration: duration)
        }
    }

    private func handleTool(_ mode: EditorMode) {
        // Any tool tap closes the edit panels first -- one owner of
        // the bottom cluster at a time.
        editingImageItem = nil
        editingStickerItem = nil
        switch mode {
        case .text:
            addTextBlock()
        case .sound:
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
        }
    }

    /// Text tool: a new block appears on the canvas and the keyboard rises --
    /// typing happens where the words will live.
    private func addTextBlock() {
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 70, 4000))
        let id = editor.addText("", at: position, pointSize: 17, size: CGSize(width: 320, height: 48))
        // addText already recorded the undo point for this compound action.
        editor.startEditingText(id, recordingUndo: false)
        textFocus = id
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
    private func cancelRecording() {
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
        guard let recorder else { return }
        Task {
            let data = (try? await recorder.stop()) ?? Data()
            self.recorder = nil
            guard !data.isEmpty else {
                recorderState = .idle
                return
            }
            let measured = AudioInfo.duration(of: data)
            let elapsed: TimeInterval
            if case .recording(let start) = recorderState {
                elapsed = Date.now.timeIntervalSince(start)
            } else {
                elapsed = 0
            }
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

    static func timestamp(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

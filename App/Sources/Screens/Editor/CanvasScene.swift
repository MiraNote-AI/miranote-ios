import MiraNoteKit
import SwiftUI

/// The base editor (v2.1): the infinite canvas plus the three-mode
/// instrument panel. Text and Sound act directly on the canvas -- Text drops
/// an editable block, Sound swaps the bottom bar for a recorder; only Image
/// leaves for its panel. Header is back / undo / Done.
struct CanvasScene: View {
    @Bindable var editor: CanvasViewModel
    @Bindable var mira: MiraCanvasCoordinator
    var actions = EditorActions()
    /// A tool requested from another scene (consumed on appear/change).
    @Binding var pendingTool: EditorMode?
    var recorderFactory: @MainActor () -> AudioRecording = { AudioRecorder() }
    var transcription: VoiceTranscriptionService = MockVoiceTranscriptionService()

    @State private var recorderState: RecorderState = .idle
    @State var recorder: AudioRecording?
    @State var recorderNotice: String?
    @State private var reviewNote = ""
    @State var accessoryRow: AccessoryRow = .tools
    @State private var miraPrompt = ""
    @State var dictating = false
    @FocusState var textFocus: CanvasItem.ID?
    @FocusState private var miraFocus: Bool

    private let soundStore = SoundFileStore()

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
                workingItemIDs: mira.workingItemIDs
            )
        } bottom: {
            bottomCluster
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if editor.editingTextItemID != nil {
                    textAccessory
                }
            }
        }
        .onAppear { consumePendingTool() }
        .onDisappear { cancelRecording() }
        .onChange(of: pendingTool) { consumePendingTool() }
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
        switch recorderState {
        case .idle:
            if let recorderNotice {
                Text(recorderNotice)
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Metrics.screenPadding)
            }
            InputModeBar(active: nil, onSelect: handleTool)
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
        case .recording(let start):
            InputModeBar(active: .sound, onSelect: handleTool)
            recordingBar(since: start)
        case .review(_, let duration):
            InputModeBar(active: .sound, onSelect: handleTool)
            reviewBar(duration: duration)
        }
    }

    private func handleTool(_ mode: EditorMode) {
        switch mode {
        case .text:
            addTextBlock()
        case .sound:
            // One audio owner at a time: not while dictating, and starting
            // a recording would unmount the Mira strip mid-turn.
            if case .idle = recorderState, !dictating, !mira.isWorking { startRecording() }
        case .image:
            cancelRecording()
            actions.selectMode(.image)
        }
    }

    /// Text tool: a new block appears on the canvas and the keyboard rises --
    /// typing happens where the words will live.
    private func addTextBlock() {
        let position = CGPoint(x: 180, y: min(editor.contentBottom + 70, 4000))
        let id = editor.addText("", at: position, pointSize: 17, size: CGSize(width: 260, height: 64))
        // addText already recorded the undo point for this compound action.
        editor.startEditingText(id, recordingUndo: false)
        textFocus = id
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

    private func startRecording() {
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

    private func stopRecording() {
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

    private func keepRecording() {
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

    private func recordingBar(since start: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.onInk)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.ink))
            WaveformView(barCount: 26, tint: Palette.ink, maxHeight: 22)
            Spacer()
            TimelineView(.periodic(from: start, by: 1)) { context in
                Text(CanvasScene.timestamp(context.date.timeIntervalSince(start)))
                    .font(.miraLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
            Button(action: stopRecording) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.onInk)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recorder.stop")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
    }

    /// After stopping: listen result, optionally note it, then Re-record or
    /// Keep (v2.1 replaces Revert/Keep for the user's own recording).
    private func reviewBar(duration: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.forest)
            Text(CanvasScene.timestamp(duration))
                .font(.miraLabel)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()

            TextField("Add a note...", text: $reviewNote)
                .font(.miraCaption)
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("recorder.note")

            Button("Re-record") {
                recorderState = .idle
                startRecording()
            }
            .font(.miraLabel)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityIdentifier("recorder.rerecord")

            Button(action: keepRecording) {
                Text("Keep")
                    .font(.miraLabel)
                    .foregroundStyle(Palette.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recorder.keep")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Palette.onInk)
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: Metrics.hairline))
        )
        .padding(.horizontal, Metrics.screenPadding)
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

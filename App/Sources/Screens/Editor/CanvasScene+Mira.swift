import MiraNoteKit
import SwiftUI

// MARK: - Background sheet, Mira chat (06), result sheet (07), dictation

extension CanvasScene {
    /// The change waiting for Keep or Revert (screen 07), if any.
    var receipt: MiraReceipt? {
        if case .receipt(let receipt) = mira.phase { return receipt }
        return nil
    }

    /// Screen 05: the tool's glass sheet over the canvas card, 7 pt taller
    /// than the card (it ends 13 above the tool bar).
    var backgroundSheet: some View {
        BackgroundToolSheet(
            editor: editor,
            // Never cancel a running turn by starting another.
            onAsk: { words in
                guard !mira.isWorking else { return }
                mira.ask(words, editor: editor)
            },
            onClose: { backgroundPanelOpen = false },
            onCustomColor: openPageColorSheet
        )
        .frame(width: MiraNoteConfig.pageWidth)
        .padding(.bottom, -7)
        .transition(.opacity)
    }

    // MARK: Custom page color (screen 05 through the sheet of 14 and 20)

    /// Custom and Pick open the shared custom color sheet on the page's
    /// color (the sheet's default when the page has none); Pick goes
    /// straight to the eyedropper.
    func openPageColorSheet(_ request: PageColorRequest) {
        let name = editor.memory.backgroundFileName.isEmpty ? editor.memory.pageColorName : ""
        pageColorEdit = PageColorEdit(
            request: request,
            original: editor.pageLook,
            initial: RGBColor(Palette.color(named: name.isEmpty ? "#F6F4E8" : name))
        )
    }

    /// Over the dock, 14 above the composer's slot as on 14 and 20; it rides
    /// the keyboard while HEX is typed. Every change previews on the page.
    @ViewBuilder var pageColorSheet: some View {
        if let edit = pageColorEdit {
            CustomColorSheet(
                title: "Custom page color",
                subtitle: "Choose a shade, or sample it from your memory.",
                initial: edit.initial,
                idPrefix: "background.colorSheet",
                onLiveChange: { editor.setPageColor($0.hex, recordingUndo: false) },
                onApply: { color in
                    // The color shown is the one applied, previewed or not.
                    editor.setPageColor(color.hex, recordingUndo: false)
                    closePageColorSheet(keeping: true)
                },
                onCancel: { closePageColorSheet(keeping: false) },
                snapshot: editor.pageSnapshot,
                picksOnAppear: edit.request == .pick
            )
            .padding(.horizontal, Metrics.chromeInset)
            .transition(.offset(y: 20).combined(with: .opacity))
        }
    }

    /// Apply keeps the previewed color as one undo step; cancel (a swipe
    /// down, a tap outside) puts the page back as it was.
    func closePageColorSheet(keeping: Bool) {
        guard let edit = pageColorEdit else { return }
        if keeping {
            editor.commitPagePreview(from: edit.original)
        } else {
            editor.discardPagePreview(from: edit.original)
        }
        withAnimation(.easeOut(duration: 0.2)) { pageColorEdit = nil }
    }

    var miraChat: some View {
        MiraChatOverlay(
            prompt: $miraPrompt,
            focus: $miraFocus,
            dictation: miraDictation,
            onUndo: editor.undo,
            undoEnabled: editor.canUndo,
            onSend: sendMiraPrompt,
            onQuickAction: { action in
                closeMiraChat()
                mira.askQuickAction(action, editor: editor)
            },
            onClose: closeMiraChat,
            onHoldStart: pressMiraDictation,
            onHoldEnd: releaseMiraDictation,
            onHoldCancel: cancelMiraDictation,
            onToggle: { miraListening ? finishMiraDictation() : startMiraDictation() }
        )
    }

    /// The strip as drawn: a live take listens even while earlier ones are
    /// still being written down.
    var miraDictation: DictationStripState {
        if miraListening { return .listening }
        if miraTakesOut > 0 { return .transcribing }
        return miraNotice.map { .notice($0) } ?? .idle
    }

    /// Tapping the composer opens the chat with the keyboard up.
    func openMiraChat() {
        guard !mira.isWorking else { return }
        miraNotice = nil
        miraChatOpen = true
        Task { @MainActor in miraFocus = true }
    }

    /// Canvas, Done or a tap on the scrim: the draft stays in the composer.
    func closeMiraChat() {
        miraFocus = false
        miraChatOpen = false
        cancelMiraDictation()
    }

    func sendMiraPrompt() {
        let words = miraPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !mira.isWorking else { return }
        closeMiraChat()
        miraPrompt = ""
        mira.ask(words, editor: editor)
    }

    // MARK: Mira Dictation (hold to talk)

    /// Touch down on the strip: the mic goes live unless it already is (a
    /// take being written down is not live: a press records a new one).
    func pressMiraDictation() {
        let live = miraListening
        miraPress = (start: .now, wasLive: live)
        if !live { startMiraDictation() }
    }

    /// Release: a hold ends the take (hold to talk); a quick tap leaves the
    /// mic listening until the next tap -- the way VoiceOver, Voice Control
    /// and Switch Control activate it -- and a tap on a live mic ends it.
    func releaseMiraDictation() {
        guard let press = miraPress else { return }
        miraPress = nil
        if press.wasLive || Date.now.timeIntervalSince(press.start) >= 0.35 { finishMiraDictation() }
    }

    /// The mic goes live. One audio owner at a time -- not while the Voice
    /// tool or text dictation holds the recorder.
    func startMiraDictation() {
        miraFinishWhenLive = false
        guard recorder == nil, !dictating, case .idle = recorderState else { return }
        let newRecorder = recorderFactory()
        recorder = newRecorder
        startingMic = .mira
        Task {
            do {
                try await newRecorder.start()
                // The chat closed while the mic came up: it stops now.
                guard holdsMic(newRecorder) else {
                    _ = try? await newRecorder.stop()
                    return
                }
                startingMic = nil
                miraNotice = nil
                miraListening = true
                // A hold let go before the mic came up: finish right away.
                if miraFinishWhenLive { finishMiraDictation() }
            } catch {
                guard holdsMic(newRecorder) else { return }
                startingMic = nil
                recorder = nil
                miraNotice = error.localizedDescription
            }
        }
    }

    /// The take ends: the recorder is let go of (the strip is free for the
    /// next take) and the words land in the question for editing, never
    /// sent.
    func finishMiraDictation() {
        guard miraListening, let recorder else {
            // Still coming up: end it once it is live.
            if recorder != nil { miraFinishWhenLive = true }
            return
        }
        miraFinishWhenLive = false
        self.recorder = nil
        miraListening = false
        miraTakesOut += 1
        Task {
            let words = await miraWords(from: recorder)
            miraTakesOut -= 1
            guard let words else { return }
            miraPrompt = miraPrompt.isEmpty ? words : miraPrompt + " " + words
        }
    }

    /// The take's words, or nil with the strip's notice saying why.
    private func miraWords(from recorder: AudioRecording) async -> String? {
        guard let data = try? await recorder.stop(), !data.isEmpty else {
            miraNotice = "I couldn't catch any words -- try again?"
            return nil
        }
        guard let transcript = try? await transcription.transcribe(audio: data, filename: "dictation.m4a") else {
            miraNotice = "Couldn't reach the transcriber -- try again?"
            return nil
        }
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            miraNotice = "I couldn't catch any words -- try again?"
            return nil
        }
        miraNotice = nil
        return words
    }

    /// The chat closed mid-take (or the app left): stop the mic quietly,
    /// keep nothing -- also one still coming up, which stops once it is.
    func cancelMiraDictation() {
        miraPress = nil
        miraFinishWhenLive = false
        if startingMic == .mira {
            startingMic = nil
            recorder = nil
            return
        }
        guard miraListening else { return }
        let abandoned = recorder
        recorder = nil
        miraListening = false
        Task { _ = try? await abandoned?.stop() }
    }

    #if DEBUG
    /// -UITEST only: the drop-zone phases, readable by XCUITest.
    @ViewBuilder var dropZoneTrailProbe: some View {
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            Text(dropZoneTrail.joined(separator: ","))
                .font(.system(size: 1))
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("canvas.deleteZone.trail")
        }
    }
    #endif
}

/// A custom page color being chosen: which entry opened it, the page as it
/// was (for cancel) and the color the sheet starts on.
struct PageColorEdit {
    let request: PageColorRequest
    let original: CanvasViewModel.PageLook
    let initial: RGBColor
}

extension CanvasViewModel {
    /// The page as a picture, for the custom color sheet's eyedropper.
    func pageSnapshot() -> UIImage? {
        let renderer = ImageRenderer(content: StaticPageView(
            memory: memory, designWidth: MiraNoteConfig.pageWidth, showsSound: false
        ))
        renderer.scale = 2
        return renderer.uiImage
    }
}

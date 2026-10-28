import Foundation
import MiraNoteKit
import SwiftUI

// MARK: - Dictation (hold to talk)

extension CanvasScene {
    /// Touch down on the strip: the mic goes live unless it already is. A
    /// take already let go of and being written down is not live: a press
    /// then records a new take.
    func pressDictation() {
        // A live voice take owns the recorder slot: the strip never takes
        // it over (or its release would transcribe the take into the block).
        // An armed Voice tool holds nothing yet.
        if case .recording = recorderState {
            dictationHint = "Stop the voice recording first."
            return
        }
        dictationPress = (start: .now, wasLive: dictating || recorder != nil)
        if dictationPress?.wasLive == false { startDictation() }
    }

    /// Release: a hold ends the take (hold to talk); a quick tap leaves the
    /// mic listening until the next tap (and a tap on a live mic ends it).
    func releaseDictation() {
        guard let press = dictationPress else { return }
        dictationPress = nil
        let held = Date.now.timeIntervalSince(press.start) >= 0.35
        if press.wasLive || (held && dictating) { stopDictation() }
    }

    /// Ends a dictation that lost its editing session (keyboard dismissed,
    /// editing finished, the app or the editor left): stop the mic quietly,
    /// keep nothing -- also one still coming up, which stops once it is.
    func cancelDictationIfNeeded() {
        dictationPress = nil
        if startingMic == .text {
            startingMic = nil
            recorder = nil
            endDeferredWriting()
            return
        }
        guard dictating else { return }
        let abandoned = recorder
        recorder = nil
        dictating = false
        Task { _ = try? await abandoned?.stop() }
        endDeferredWriting()
    }

    /// The writing's end waited for a held take that then ended without
    /// words (cancelled, or its mic never came up): once the earlier words
    /// have landed, the writing ends now -- still on their way, they end it.
    private func endDeferredWriting() {
        guard doneWaiting != nil, pendingTakes.isEmpty else { return }
        finishWaitingDone(caught: true)
    }

    /// Whether `candidate` still holds the recorder slot (a cancel while it
    /// came up let go of it).
    func holdsMic(_ candidate: AudioRecording) -> Bool {
        recorder.map { $0 as AnyObject } === (candidate as AnyObject)
    }

    /// The sound tool and dictation never share the recorder slot (guarded
    /// on both entry points).
    func startDictation() {
        guard recorder == nil else { return }
        dictationHint = nil
        let newRecorder = recorderFactory()
        recorder = newRecorder
        startingMic = .text
        Task {
            do {
                try await newRecorder.start()
                guard holdsMic(newRecorder) else {
                    _ = try? await newRecorder.stop()
                    return
                }
                startingMic = nil
                dictating = true
            } catch {
                guard holdsMic(newRecorder) else { return }
                startingMic = nil
                recorder = nil
                dictationHint = error.localizedDescription
                endDeferredWriting()
            }
        }
    }

    /// Record, transcribe (:8005), append to the block being edited, inside
    /// its session like typing. Words never land after the session ends:
    /// Done waits for them ("Writing it down...", `endTextEditing`); Cancel,
    /// or a session that ends or moves on, drops them. The take stops being
    /// live here, as the recorder is let go of: its words on their way are
    /// `writingDown`, and the strip is free for the next take.
    func stopDictation() {
        // A mic still coming up is let go of here (its start then stops
        // it): no stale claim left for a later cancel to act on.
        if startingMic == .text { startingMic = nil }
        dictating = false
        guard let recorder else { return }
        self.recorder = nil
        let id = editor.editingTextItemID
        dictationTarget = id
        // A take spoken while an earlier one of the same session is still
        // written down queues behind it: both land, in the order spoken.
        let take = UUID()
        pendingTakes.append(take)
        // The writing's end waited for this take to be let go of: its words
        // get the whole wait from here.
        if doneWaiting != nil {
            doneWaiting = nil
            waitForWordsThenEnd()
        }
        let earlier = lastTake
        lastTake = Task {
            let words = await transcribe(recorder, for: id)
            await earlier?.value
            let queued = pendingTakes.contains(take)
            pendingTakes.removeAll { $0 == take }
            guard let id, queued, dictationTarget == id, editor.editingTextItemID == id else { return }
            if let words { append(words, to: id) }
            // The last take on its way lets go of the block (and Done).
            guard pendingTakes.isEmpty else { return }
            dictationTarget = nil
            if doneWaiting != nil { finishWaitingDone(caught: words != nil) }
        }
    }

    /// The take's words, or nil with the strip saying why -- a silent
    /// return looked like a dead feature.
    private func transcribe(_ recorder: AudioRecording, for id: CanvasItem.ID?) async -> String? {
        guard let data = try? await recorder.stop(), !data.isEmpty else {
            dictationHint = "I couldn't catch any words -- try again?"
            return nil
        }
        guard id != nil else {
            dictationHint = "Tap a text block first, then dictate."
            return nil
        }
        guard let transcript = try? await transcription.transcribe(audio: data, filename: "dictation.m4a") else {
            dictationHint = "Couldn't reach the transcriber -- try again?"
            return nil
        }
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            dictationHint = "I couldn't catch any words -- try again?"
            return nil
        }
        return words
    }

    /// Words are on their way for the block being written.
    var writingDown: Bool { dictationTarget != nil && dictationTarget == editor.editingTextItemID }

    /// Done while the words are on their way: the session stays open until
    /// they land (then Done completes), or for at most `doneWaitCap` -- then
    /// it ends without them, an empty block going as usual.
    func waitForWordsThenEnd() {
        guard doneWaiting == nil else { return }
        let wait = UUID()
        doneWaiting = wait
        Task {
            try? await Task.sleep(for: Self.doneWaitCap)
            guard doneWaiting == wait else { return }
            dictationTarget = nil
            finishWaitingDone(caught: false)
        }
    }

    static let doneWaitCap: Duration = .seconds(10)

    /// Ends the writing, then does what the tap that asked for it does
    /// (deselect, select another element), if a tap did.
    private func finishWaitingDone(caught: Bool) {
        // A take still held (a hold during the wait) keeps recording: the
        // writing ends once it is let go of and its words land. No cap runs
        // while the finger is down.
        if dictating || startingMic == .text {
            doneWaiting = UUID()
            if !caught { flashHint("Couldn't catch those words.") }
            return
        }
        doneWaiting = nil
        let then = afterWritingDown
        afterWritingDown = nil
        endTextEditing()
        // A take started meanwhile (a hold during the wait) is waited for
        // too: the tap's own action follows once its words land.
        if doneWaiting != nil {
            afterWritingDown = then
        } else {
            then?()
        }
        if !caught { flashHint("Couldn't catch those words.") }
    }

    private func append(_ words: String, to id: CanvasItem.ID) {
        guard case .text(let block) = editor.item(id)?.content else { return }
        editor.setText(itemID: id, to: block.text.isEmpty ? words : block.text + " " + words)
        // Grow the box to the new text like typing does, or the dictated
        // words land clipped below the fold and read as "nothing happened."
        remeasureEditedText(id)
    }
}

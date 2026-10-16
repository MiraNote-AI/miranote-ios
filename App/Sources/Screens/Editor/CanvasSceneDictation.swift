import Foundation
import MiraNoteKit
import SwiftUI

// MARK: - Dictation (hold to talk)

extension CanvasScene {
    /// Touch down on the strip: the mic goes live unless it already is.
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
            return
        }
        guard dictating else { return }
        let abandoned = recorder
        recorder = nil
        dictating = false
        Task { _ = try? await abandoned?.stop() }
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
            }
        }
    }

    /// Record, transcribe (:8005), append to the block being edited. Words
    /// still on their way when Done ends the session land in that block as
    /// their own step -- a new block ended empty waits for them; Cancel
    /// (`dictationTarget` cleared) drops them.
    func stopDictation() {
        // A mic still coming up is let go of here (its start then stops
        // it): no stale claim left for a later cancel to act on.
        if startingMic == .text { startingMic = nil }
        guard let recorder else {
            dictating = false
            return
        }
        self.recorder = nil
        let id = editor.editingTextItemID
        dictationTarget = id
        Task {
            defer {
                dictating = false
                releaseTarget(id)
            }
            // A silent return here looked like a dead feature: say why
            // nothing landed instead of swallowing it.
            guard let data = try? await recorder.stop(), !data.isEmpty else {
                dictationHint = "I couldn't catch any words -- try again?"
                return
            }
            guard let id else {
                dictationHint = "Tap a text block first, then dictate."
                return
            }
            guard let transcript = try? await transcription.transcribe(
                audio: data, filename: "dictation.m4a"
            ) else {
                dictationHint = "Couldn't reach the transcriber -- try again?"
                return
            }
            let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else {
                dictationHint = "I couldn't catch any words -- try again?"
                return
            }
            // Cancelled while the words were on their way: they belong to
            // no session any more.
            guard dictationTarget == id else { return }
            dictationTarget = nil
            land(words, in: id)
        }
    }

    private func land(_ words: String, in id: CanvasItem.ID) {
        if editor.editingTextItemID == id {
            append(words, to: id)
        } else if isEmptyText(id) {
            // Done right after dictating into a new block: it waited empty;
            // the words fill it as their own step.
            editor.fillEmptyText(itemID: id, with: words)
        } else if let before = editor.item(id) {
            // Done while "Writing it down...": kept, as one undo step.
            append(words, to: id)
            editor.commitPreview(of: before)
        }
    }

    /// The dictation for `id` ended without words: the empty block that
    /// waited for them goes after all.
    private func releaseTarget(_ id: CanvasItem.ID?) {
        guard let id, dictationTarget == id else { return }
        dictationTarget = nil
        if editor.editingTextItemID != id, isEmptyText(id) {
            editor.discardAbandonedText(itemID: id)
        }
    }

    private func isEmptyText(_ id: CanvasItem.ID) -> Bool {
        guard case .text(let block) = editor.item(id)?.content else { return false }
        return block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func append(_ words: String, to id: CanvasItem.ID) {
        guard case .text(let block) = editor.item(id)?.content else { return }
        editor.setText(itemID: id, to: block.text.isEmpty ? words : block.text + " " + words)
        // Grow the box to the new text like typing does, or the dictated
        // words land clipped below the fold and read as "nothing happened."
        remeasureEditedText(id)
    }
}

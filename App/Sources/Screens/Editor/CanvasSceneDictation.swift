import Foundation
import MiraNoteKit
import SwiftUI

// MARK: - Dictation (hold to talk)

extension CanvasScene {
    /// Touch down on the strip: the mic goes live unless it already is.
    func pressDictation() {
        // A live voice take owns the recorder slot: the strip never takes
        // it over (or its release would transcribe the take into the block).
        guard case .idle = recorderState else {
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
    /// editing finished): stop the mic quietly, keep nothing.
    func cancelDictationIfNeeded() {
        guard dictating else { return }
        let abandoned = recorder
        recorder = nil
        dictating = false
        Task { _ = try? await abandoned?.stop() }
    }

    /// The sound tool and dictation never share the recorder slot (guarded
    /// on both entry points).
    func startDictation() {
        guard recorder == nil else { return }
        dictationHint = nil
        let newRecorder = recorderFactory()
        recorder = newRecorder
        Task {
            do {
                try await newRecorder.start()
                dictating = true
            } catch {
                recorder = nil
                dictationHint = error.localizedDescription
            }
        }
    }

    /// Record, transcribe (:8005), append to the block being edited.
    func stopDictation() {
        guard let recorder else {
            dictating = false
            return
        }
        self.recorder = nil
        Task {
            defer { dictating = false }
            // A silent return here looked like a dead feature: say why
            // nothing landed instead of swallowing it.
            guard let data = try? await recorder.stop(), !data.isEmpty else {
                dictationHint = "I couldn't catch any words -- try again?"
                return
            }
            guard let id = editor.editingTextItemID else {
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
            // Cancelled or ended while the words were on their way: they
            // belong to no session any more (and would have no undo step).
            guard editor.editingTextItemID == id else { return }
            if case .text(let block) = editor.item(id)?.content {
                let joined = block.text.isEmpty ? words : block.text + " " + words
                editor.setText(itemID: id, to: joined)
                // Grow the box to the new text like typing does, or the
                // dictated words land clipped below the fold and read as
                // "nothing happened."
                remeasureEditedText(id)
            }
        }
    }
}

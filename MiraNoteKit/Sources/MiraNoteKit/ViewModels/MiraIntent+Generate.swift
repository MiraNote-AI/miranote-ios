import CoreGraphics
import Foundation

// The generative families of the Mira cue router -- illustrate-the-words,
// page backgrounds, and plain generation -- plus the shared two-candidate
// helper (split from MiraIntent+Image.swift for the file-length cap).
extension MiraIntent {
    /// Pictures FROM the page's words ("turn this text into a picture",
    /// "\u{628A}\u{8FD9}\u{6BB5}\u{6587}\u{5B57}\u{753B}\u{6210}\u{56FE}").
    /// Checked before generation (the hua in hua-cheng-tu) and before the
    /// photo family (the word "picture").
    @MainActor
    static func illustrateTextIntent(
        _ lowered: String, editor: CanvasViewModel
    ) -> MiraIntent? {
        let mentionsText = ["this text", "the text", "my text",
                            "\u{8FD9}\u{6BB5}\u{6587}\u{5B57}", "\u{8FD9}\u{6BB5}\u{8BDD}",
                            "\u{6587}\u{5B57}"]
            .contains(where: lowered.contains)
        let intoPicture = ["into a picture", "into an image", "as a picture",
                           "\u{753B}\u{6210}", "\u{53D8}\u{6210}\u{56FE}"]
            .contains(where: lowered.contains)
        guard mentionsText, intoPicture else { return nil }
        guard let (_, words) = targetTextBlock(editor: editor) else {
            return .clarifyNoText
        }
        return .illustrateText(prompt: "An illustration of: " + words)
    }

    /// The page-background family outranks generation ("draw a starry
    /// background" is a backdrop wish), but photo- and sticker-flavored
    /// background words ("remove the photo's background") stay out.
    static func generativeIntent(
        _ lowered: String, prompt: String,
        mentionsPhoto: Bool, mentionsSticker: Bool
    ) -> MiraIntent? {
        if !mentionsPhoto, !mentionsSticker,
           let background = backgroundIntent(lowered, prompt: prompt) {
            return background
        }
        return generationIntent(lowered, prompt: prompt)
    }

    /// The page-background family ("give this page a sunset background",
    /// "\u{6362}\u{4E2A}\u{661F}\u{7A7A}\u{80CC}\u{666F}"). Callers must
    /// already have excluded photo- and sticker-flavored asks.
    static func backgroundIntent(_ lowered: String, prompt: String) -> MiraIntent? {
        let mentions = ["background", "backdrop", "\u{80CC}\u{666F}", "\u{5E95}\u{8272}"]
            .contains(where: lowered.contains)
        guard mentions else { return nil }
        let clears = ["remove the background", "no background", "default background",
                      "clear the background",
                      "\u{53BB}\u{6389}\u{80CC}\u{666F}", "\u{6E05}\u{7A7A}\u{80CC}\u{666F}"]
        if clears.contains(where: lowered.contains) {
            return .clearBackground
        }
        let generationCues = ["draw ", "paint ", "generate ", "\u{753B}",
                              "\u{751F}\u{6210}", "\u{6765}\u{4E00}\u{5F20}", "\u{6765}\u{4E2A}"]
        guard hasEditVerb(lowered) || generationCues.contains(where: lowered.contains) else {
            return nil
        }
        return .setBackground(prompt: prompt)
    }

    static func generationIntent(_ lowered: String, prompt: String) -> MiraIntent? {
        let cues = ["draw ", "paint ", "generate ", "\u{753B}",
                    "\u{751F}\u{6210}", "\u{6765}\u{4E00}\u{5F20}"]
        guard cues.contains(where: lowered.contains) else { return nil }
        let sticker = lowered.contains("sticker") || lowered.contains("\u{8D34}\u{7EB8}")
        return .generateImage(prompt: prompt, sticker: sticker)
    }

    /// Two candidates from the studio, or the timeout error when it
    /// returns none. Shared by picture, sticker, and background asks.
    func generateChoices(
        _ imageStudio: ImageStudioService, kind: GeneratedImageKind,
        prompt: String, placement: ImageChoicePlacement
    ) async throws -> MiraOutcome {
        let images = try await imageStudio.generate(kind: kind, prompt: prompt)
        guard !images.isEmpty else { throw MiraTimeoutError() }
        return .imageChoices(Array(images.prefix(2)), prompt: prompt, placement: placement)
    }
}

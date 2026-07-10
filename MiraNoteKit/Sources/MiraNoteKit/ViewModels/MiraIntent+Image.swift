import CoreGraphics
import Foundation

// The image and style families of the Mira cue router (split from
// MiraIntent.swift for the size caps). Checked BEFORE the text transform
// cues so photo-flavored wording ("make the photo warmer") wins the
// filter, never polish.
extension MiraIntent {
    /// The image/style side of `perform` (delegated to keep the main
    /// switch under the complexity cap).
    func performImageOrStyle() async throws -> MiraOutcome {
        if case .clarifyPhoto = self {
            throw MiraClarifyError(
                question: "More than one photo here -- tap the one you mean and ask again.",
                chips: []
            )
        }
        // Wired to the image studio in the next commit of this branch.
        throw MiraTimeoutError()
    }

    enum PhotoTarget {
        case one(CanvasItem.ID, ImageRef)
        case none
        case ambiguous
    }

    /// Selected photo first; else the only photo; else ambiguous.
    @MainActor
    static func photoTarget(editor: CanvasViewModel) -> PhotoTarget {
        let photos = editor.orderedItems.compactMap { item -> (CanvasItem.ID, ImageRef)? in
            guard case .image(let ref) = item.content else { return nil }
            return (item.id, ref)
        }
        if let selected = editor.selectedItemID,
           let match = photos.first(where: { $0.0 == selected }) {
            return .one(match.0, match.1)
        }
        if photos.count == 1, let only = photos.first {
            return .one(only.0, only.1)
        }
        return photos.isEmpty ? .none : .ambiguous
    }

    /// nil = no image or style cue matched; the text router continues.
    @MainActor
    static func classifyImageOrStyle(
        _ lowered: String,
        prompt: String,
        editor: CanvasViewModel,
        imageStore: ImageFileStore
    ) -> MiraIntent? {
        if let generation = generationIntent(lowered, prompt: prompt) {
            return generation
        }
        let mentionsPhoto = ["photo", "picture", "\u{7167}\u{7247}", "\u{56FE}"]
            .contains(where: lowered.contains)
        if let photoIntent = photoIntent(
            lowered, prompt: prompt, mentionsPhoto: mentionsPhoto,
            editor: editor, imageStore: imageStore
        ) {
            return photoIntent
        }
        return styleIntent(lowered, editor: editor)
    }

    private static func generationIntent(_ lowered: String, prompt: String) -> MiraIntent? {
        let cues = ["draw ", "paint ", "generate ", "\u{753B}",
                    "\u{751F}\u{6210}", "\u{6765}\u{4E00}\u{5F20}"]
        guard cues.contains(where: lowered.contains) else { return nil }
        let sticker = lowered.contains("sticker") || lowered.contains("\u{8D34}\u{7EB8}")
        return .generateImage(prompt: prompt, sticker: sticker)
    }

    @MainActor
    private static func photoIntent(
        _ lowered: String, prompt: String, mentionsPhoto: Bool,
        editor: CanvasViewModel, imageStore: ImageFileStore
    ) -> MiraIntent? {
        let stickerCut = lowered.contains("into a sticker")
            || lowered.contains("\u{62A0}\u{6210}")
        let filterName = filterCue(lowered)
        let frameName = frameCue(lowered)
        let freeEdit = mentionsPhoto
            && (lowered.contains("make ") || lowered.contains("\u{628A}"))
        guard stickerCut || filterName != nil || frameName != nil || freeEdit else {
            return nil
        }
        switch photoTarget(editor: editor) {
        case .none:
            // A photo-flavored ask with no photo on the page: only claim
            // it when the words really are about a photo.
            return (stickerCut || mentionsPhoto) ? .clarifyPhoto : nil
        case .ambiguous:
            return .clarifyPhoto
        case .one(let id, let ref):
            let data = imageStore.data(forFileName: ref.fileName) ?? Data()
            if stickerCut {
                return .makeSticker(id, imageData: data, prompt: ref.displayName)
            }
            if let filterName {
                return .applyFilter(id, name: filterName)
            }
            if let frameName {
                return .applyFrame(id, name: frameName)
            }
            return .editPhoto(id, imageData: data, instruction: prompt)
        }
    }

    private static func filterCue(_ lowered: String) -> String? {
        if lowered.contains("black and white") || lowered.contains("b&w")
            || lowered.contains("\u{9ED1}\u{767D}") { return "bw" }
        if lowered.contains("warmer") || lowered.contains("warm filter")
            || lowered.contains("warm look") { return "warm" }
        if lowered.contains("film look") || lowered.contains("film filter") { return "film" }
        if lowered.contains("match the page") { return "match" }
        if lowered.contains("no filter") || lowered.contains("original look") { return "" }
        return nil
    }

    private static func frameCue(_ lowered: String) -> String? {
        if lowered.contains("polaroid") || lowered.contains("\u{62CD}\u{7ACB}\u{5F97}") {
            return "polaroid"
        }
        if lowered.contains("white frame") || lowered.contains("\u{767D}\u{6846}") {
            return "white"
        }
        if lowered.contains("no frame") { return "" }
        return nil
    }

    @MainActor
    private static func styleIntent(_ lowered: String, editor: CanvasViewModel) -> MiraIntent? {
        let up = ["bigger", "larger", "\u{5927}\u{4E00}\u{70B9}", "\u{653E}\u{5927}"]
            .contains(where: lowered.contains)
        let down = ["smaller", "\u{5C0F}\u{4E00}\u{70B9}", "\u{7F29}\u{5C0F}"]
            .contains(where: lowered.contains)
        let color = colorCue(lowered)
        guard up || down || color != nil else { return nil }
        guard let (id, _) = targetTextBlock(editor: editor) else { return nil }
        if up || down { return .resizeText(id, up: up) }
        guard let color else { return nil }
        return .recolorText(id, colorName: color)
    }

    private static func colorCue(_ lowered: String) -> String? {
        if lowered.contains("green") || lowered.contains("forest")
            || lowered.contains("\u{7EFF}") { return "forest" }
        if lowered.contains("grey") || lowered.contains("gray")
            || lowered.contains("\u{7070}") { return "textSecondary" }
        if lowered.contains("black text") || lowered.contains("ink")
            || lowered.contains("\u{9ED1}\u{8272}") { return "ink" }
        if lowered.contains("brown") || lowered.contains("taupe")
            || lowered.contains("\u{68D5}") { return "taupe" }
        if lowered.contains("tan") || lowered.contains("beige") { return "tan" }
        return nil
    }
}

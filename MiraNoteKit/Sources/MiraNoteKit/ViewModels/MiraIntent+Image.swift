import CoreGraphics
import Foundation

// The image and style families of the Mira cue router (split from
// MiraIntent.swift for the size caps). Checked BEFORE the text transform
// cues so photo-flavored wording ("make the photo warmer") wins the
// filter, never polish.
extension MiraIntent {
    /// Generation and photo edits run on the studio's long timeout, not
    /// the chat one.
    var isSlowImageWork: Bool {
        switch self {
        case .generateImage, .editPhoto, .makeSticker, .editSticker, .setBackground: return true
        default: return false
        }
    }

    /// The image/style side of `perform` (delegated to keep the main
    /// switch under the complexity cap). Instant local outcomes return
    /// straight away; slow ones ride the studio.
    func performImageOrStyle(imageStudio: ImageStudioService) async throws -> MiraOutcome {
        if let instant = instantOutcome {
            return instant
        }
        return try await performSlowImage(imageStudio: imageStudio)
    }

    /// Filter, frame, size, and color settle before the working bar's
    /// 400 ms delay ever shows -- no network, one undo snapshot.
    private var instantOutcome: MiraOutcome? {
        switch self {
        case .applyFilter(let id, let name):
            return .filterApplied(id, name: name, MiraReceipt(
                changed: name.isEmpty ? "Cleared the filter." : "Changed the photo's look.",
                kept: "Undo restores it."))
        case .applyFrame(let id, let name):
            return .frameApplied(id, name: name, MiraReceipt(
                changed: name.isEmpty ? "Removed the frame." : "Framed the photo.",
                kept: "Undo restores it."))
        case .resizeText(let id, let up):
            return .textResized(id, up: up, MiraReceipt(
                changed: up ? "Made the words bigger." : "Made the words smaller.",
                kept: "Undo restores them."))
        case .recolorText(let id, let colorName):
            return .textRecolored(id, colorName: colorName, MiraReceipt(
                changed: "Recolored the words.", kept: "Undo restores them."))
        case .clearBackground:
            return .backgroundCleared(MiraReceipt(
                changed: "Cleared the background.",
                kept: "Undo restores it."))
        default:
            return nil
        }
    }

    /// Two candidates from the studio, or the timeout error when it
    /// returns none. Shared by picture, sticker, and background asks.
    private func generateChoices(
        _ imageStudio: ImageStudioService, kind: GeneratedImageKind,
        prompt: String, placement: ImageChoicePlacement
    ) async throws -> MiraOutcome {
        let images = try await imageStudio.generate(kind: kind, prompt: prompt)
        guard !images.isEmpty else { throw MiraTimeoutError() }
        return .imageChoices(Array(images.prefix(2)), prompt: prompt, placement: placement)
    }

    private func performSlowImage(imageStudio: ImageStudioService) async throws -> MiraOutcome {
        switch self {
        case .generateImage(let prompt, let sticker):
            return try await generateChoices(
                imageStudio, kind: sticker ? .sticker : .art,
                prompt: prompt, placement: sticker ? .sticker : .picture)
        case .setBackground(let prompt):
            return try await generateChoices(
                imageStudio, kind: .background, prompt: prompt, placement: .background)
        case .editPhoto(let id, let data, let instruction):
            guard !data.isEmpty else { throw Self.missingPixels }
            let styled = try await imageStudio.stylize(image: data, instruction: instruction)
            return .imageReplaced(id, styled, MiraReceipt(
                changed: "Restyled the photo.",
                kept: "Undo brings the old one back."))
        case .makeSticker(let id, let data, let prompt):
            guard !data.isEmpty else { throw Self.missingPixels }
            let cut = try await imageStudio.cutout(image: data, target: nil)
            let outlined = try await imageStudio.outline(image: cut)
            return .stickerReplaced(id, outlined, prompt: prompt, MiraReceipt(
                changed: "Made it a sticker.",
                kept: "Undo brings the photo back."))
        case .editSticker(let id, let data, let instruction, _):
            guard !data.isEmpty else {
                throw MiraClarifyError(
                    question: "This sticker has no stored pixels to work on -- try another?",
                    chips: []
                )
            }
            let styled = try await imageStudio.stylize(image: data, instruction: instruction)
            let cut = try await imageStudio.cutout(image: styled, target: nil)
            let outlined = try await imageStudio.outline(image: cut)
            return .stickerEdited(id, outlined, MiraReceipt(
                changed: "Restyled the sticker.",
                kept: "Undo brings the old one back."))
        case .clarifySticker(let question), .clarifyPhoto(let question):
            throw MiraClarifyError(question: question, chips: [])
        default:
            throw MiraClarifyError(
                question: "More than one photo here -- tap the one you mean and ask again.",
                chips: []
            )
        }
    }

    private static var missingPixels: MiraClarifyError {
        MiraClarifyError(
            question: "This picture has no stored pixels to work on -- try another photo?",
            chips: []
        )
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

    enum StickerTarget {
        case one(CanvasItem.ID, GeneratedSticker)
        case none
        case ambiguous
    }

    /// Selected sticker first; else the only sticker; else ambiguous.
    @MainActor
    static func stickerTarget(editor: CanvasViewModel) -> StickerTarget {
        let stickers = editor.orderedItems.compactMap { item -> (CanvasItem.ID, GeneratedSticker)? in
            guard case .sticker(let sticker) = item.content else { return nil }
            return (item.id, sticker)
        }
        if let selected = editor.selectedItemID,
           let match = stickers.first(where: { $0.0 == selected }) {
            return .one(match.0, match.1)
        }
        if stickers.count == 1, let only = stickers.first {
            return .one(only.0, only.1)
        }
        return stickers.isEmpty ? .none : .ambiguous
    }

    /// The words that make an ask an EDIT -- shared by the sticker and
    /// photo free-edit families. Escaped cues: ba, gai, huan, bian, gei.
    static func hasEditVerb(_ lowered: String) -> Bool {
        let verbs = ["make ", "change ", "turn ", "edit ", "redraw ",
                     "restyle ", "recolor ", "repaint ", "give ", "add ", "put ",
                     "\u{628A}", "\u{6539}", "\u{6362}", "\u{53D8}", "\u{7ED9}"]
        return verbs.contains(where: lowered.contains)
    }

    /// In-place sticker edit: any sticker mention ("change sticker to
    /// blue" included) plus an edit verb -- EXCEPT the indefinite forms
    /// that wish for a NEW one ("a sticker", "another sticker") and the
    /// photo-conversion phrase ("into a sticker").
    @MainActor
    private static func stickerEditIntent(
        _ lowered: String, prompt: String, stickerCut: Bool,
        editor: CanvasViewModel, imageStore: ImageFileStore
    ) -> MiraIntent? {
        let mentionsSticker = ["sticker", "\u{8D34}\u{7EB8}"]
            .contains(where: lowered.contains)
        let wishesForANewOne = ["a sticker", "another sticker", "a new sticker"]
            .contains(where: lowered.contains)
        let editVerb = Self.hasEditVerb(lowered)
        guard mentionsSticker, !wishesForANewOne, editVerb, !stickerCut else { return nil }
        switch stickerTarget(editor: editor) {
        case .none:
            return .clarifySticker(
                question: "No sticker on this page yet -- generate one first?")
        case .ambiguous:
            return .clarifySticker(
                question: "More than one sticker here -- tap the one you mean and ask again.")
        case .one(let id, let sticker):
            let data = imageStore.data(forFileName: sticker.fileName) ?? Data()
            return .editSticker(id, imageData: data, instruction: prompt,
                                prompt: sticker.prompt)
        }
    }

    /// nil = no image or style cue matched; the text router continues.
    @MainActor
    static func classifyImageOrStyle(
        _ lowered: String,
        prompt: String,
        editor: CanvasViewModel,
        imageStore: ImageFileStore
    ) -> MiraIntent? {
        let mentionsSticker = ["sticker", "\u{8D34}\u{7EB8}"].contains(where: lowered.contains)
        let stickerCut = lowered.contains("into a sticker")
            || lowered.contains("\u{62A0}\u{6210}")
        let mentionsPhoto = ["photo", "picture", "\u{7167}\u{7247}", "\u{56FE}"]
            .contains(where: lowered.contains)
        if let generative = generativeIntent(
            lowered, prompt: prompt,
            mentionsPhoto: mentionsPhoto, mentionsSticker: mentionsSticker
        ) {
            return generative
        }
        // Mixed mentions ("make the photo look like the sticker",
        // "\u{628A}\u{7167}\u{7247}\u{53D8}\u{6210}\u{8D34}\u{7EB8}") stay
        // with the photo family: never redraw a sticker when the words
        // are about a photo.
        if !mentionsPhoto, let stickerEdit = stickerEditIntent(
            lowered, prompt: prompt, stickerCut: stickerCut,
            editor: editor, imageStore: imageStore
        ) {
            return stickerEdit
        }
        // A sticker-flavored ask must never mutate a photo ("make the
        // sticker warmer" used to land on the photo warm filter).
        if mentionsSticker && !mentionsPhoto && !stickerCut {
            return styleIntent(lowered, editor: editor)
        }
        if let photoIntent = photoIntent(
            lowered, prompt: prompt, mentionsPhoto: mentionsPhoto,
            editor: editor, imageStore: imageStore
        ) {
            return photoIntent
        }
        return styleIntent(lowered, editor: editor)
    }

    /// The page-background family outranks generation ("draw a starry
    /// background" is a backdrop wish), but photo- and sticker-flavored
    /// background words ("remove the photo's background") stay out.
    private static func generativeIntent(
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
    private static func backgroundIntent(_ lowered: String, prompt: String) -> MiraIntent? {
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
        // Words-wanting asks ("Add a text to describe the picture") are
        // caption wishes: the free edit must decline so classify falls
        // through to addCaption instead of painting words INTO the photo.
        let wantsWords = ["describe", "add a text", "add text", "caption",
                          "write about", "in words",
                          "\u{63CF}\u{8FF0}", "\u{5199}\u{4E00}\u{6BB5}",
                          "\u{914D}\u{6587}", "\u{5199}\u{51E0}\u{53E5}"]
            .contains(where: lowered.contains)
        let freeEdit = mentionsPhoto && !wantsWords && Self.hasEditVerb(lowered)
        guard stickerCut || filterName != nil || frameName != nil || freeEdit else {
            return nil
        }
        switch photoTarget(editor: editor) {
        case .none:
            // A photo-flavored ask with no photo on the page: only claim
            // it when the words really are about a photo.
            return (stickerCut || mentionsPhoto)
                ? .clarifyPhoto(question: "No photo on this page yet -- add one first?")
                : nil
        case .ambiguous:
            return .clarifyPhoto(
                question: "More than one photo here -- tap the one you mean and ask again.")
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

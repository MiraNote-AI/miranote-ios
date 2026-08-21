import Foundation

/// Slow image work Mira asks for after reading the page.
///
/// A chat turn is budgeted in seconds; generating a backdrop or
/// restyling a photo runs on the image budget instead. So these arrive
/// as requests in the reply and start a turn of their own -- see
/// `startSlowTurn`, which owns that mechanic. What lives here is only
/// the decision of WHAT to run, which is why none of it touches the
/// turn machinery directly.
extension MiraCanvasCoordinator {
    /// Clearing is instant and local; painting a new backdrop is not.
    func startBackgroundTurn(_ request: BackgroundRequest, editor: CanvasViewModel) {
        switch request {
        case .clear:
            // The same call the existing .backgroundCleared branch makes.
            editor.beginChange()
            editor.setBackground(fileName: "")
            showReceipt(MiraReceipt(
                changed: "Cleared the backdrop.",
                kept: "Your words and photos are unchanged."
            ), editor: editor)
        case .set(let prompt):
            startSlowTurn(
                .setBackground(prompt: prompt),
                verb: "Painting the backdrop...",
                editor: editor
            )
        }
    }

    /// A photo restyle Mira chose after looking at the page.
    func startPhotoRestyleTurn(
        _ request: PhotoRestyleRequest,
        handles: [String: CanvasItem.ID],
        editor: CanvasViewModel
    ) {
        // The model's handle is usually right. When it is not -- or the
        // page moved since the map was built -- the selected photo, else
        // the only photo, is what the user meant. Several photos with no
        // clear target stay a calm clarify. Same rule as the local photo
        // family (photoTarget), so the two paths cannot drift apart.
        let resolved: (CanvasItem.ID, Data)? = {
            if let id = handles[request.handle],
               case .image(let ref) = editor.item(id)?.content {
                return (id, imageStore.data(forFileName: ref.fileName) ?? Data())
            }
            if case .one(let id, let ref) = MiraIntent.photoTarget(editor: editor) {
                return (id, imageStore.data(forFileName: ref.fileName) ?? Data())
            }
            return nil
        }()
        guard let (id, data) = resolved else {
            failClarify("I could not tell which picture you meant -- tap it and ask again?")
            return
        }
        // Reuses the keyword path's intent wholesale: it already checks
        // for missing pixels and settles as an atomic photo replacement.
        startSlowTurn(
            .editPhoto(id, imageData: data, instruction: request.instruction),
            verb: "Restyling the photo...",
            editor: editor
        )
    }
}

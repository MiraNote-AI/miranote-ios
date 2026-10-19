import Foundation

/// How a page edit is described back to the user.
///
/// The result sheet is a fixed UI element (handoff screen 07: what changed,
/// what was kept, Revert / Keep), so its wording is derived here from the
/// shape of the change rather than written by the model. Mira owns the
/// conversational reply, where variety is welcome.
extension MiraCanvasCoordinator {
    /// The receipt says what changed, in the app's voice -- the sheet is a
    /// fixed UI element, so its wording must stay steady. Mira owns the
    /// conversational reply, where variety is welcome.
    static func receipt(
        for changes: [ResolvedChange], editor: CanvasViewModel
    ) -> MiraReceipt {
        let kept = "Everything else stayed put."
        if changes.count >= 3 {
            return MiraReceipt(changed: "Rearranged the page.", kept: kept)
        }
        let noun = changes.count == 1
            ? Self.noun(for: changes[0].id, editor: editor) : "a few things"
        let moved = changes.contains { $0.x != nil || $0.y != nil }
        let resized = changes.contains { $0.w != nil || $0.h != nil || $0.pointSize != nil }
        if moved && !resized { return MiraReceipt(changed: "Moved \(noun).", kept: kept) }
        if resized && !moved { return MiraReceipt(changed: "Resized \(noun).", kept: kept) }
        if changes.contains(where: { $0.colorName != nil }) {
            return MiraReceipt(changed: "Recolored \(noun).", kept: kept)
        }
        return MiraReceipt(changed: "Adjusted \(noun).", kept: kept)
    }

    /// A page edit that named the right piece but changed nothing: said as
    /// it is, never as a change.
    static func unchangedReceipt(
        for changes: [ResolvedChange], editor: CanvasViewModel
    ) -> MiraReceipt {
        let live = changes.filter { editor.item($0.id) != nil }
        let changed = live.count == 1
            ? "Left \(Self.noun(for: live[0].id, editor: editor)) as it was."
            : "Left the page as it was."
        return MiraReceipt(changed: changed, kept: "Everything else stayed put.")
    }

    private static func noun(for id: CanvasItem.ID, editor: CanvasViewModel) -> String {
        switch editor.item(id)?.content {
        case .text(let block): return block.pointSize >= CanvasViewModel.displayPointSize ? "the title" : "the text"
        case .image: return "the photo"
        case .sticker: return "the sticker"
        case .sound: return "the sound"
        case nil: return "it"
        }
    }
}

import Foundation
import MiraNoteKit

// Shared state shapes for CanvasScene's bottom cluster.

enum RecorderState {
    case idle
    /// The Voice tool is open but the mic is not live yet -- recording
    /// starts only when the user presses Record.
    case armed
    case recording(start: Date)
}

/// Photos picked while another import still loads, waiting their turn.
struct QueuedImport {
    let load: () async -> [Data]
    let then: ([CanvasItem.ID]) -> Void
}

/// Which dictation strip's mic is still coming up (it takes the audio
/// session, and the permission alert the first time): a cancel then has
/// to know whose it is.
enum StartingMic {
    case text, mira
}

/// A take Stop just put on the page (handoff screen 09): the result sheet
/// offers Revert / Keep while the add is still the page's last change.
struct AttachedSound: Equatable {
    let itemID: CanvasItem.ID
    /// `CanvasViewModel.changeCount` right after the add.
    let changeCount: Int
}

/// One photo editing session (handoff screens 27-28): the photo, how it
/// looked when editing began, and whether it has been edited since.
struct PhotoSession {
    let itemID: CanvasItem.ID
    let original: ImageRef
    var edited = false
    /// The photo as the session last saw it. A change made while the panel
    /// was closed (a Mira edit from the bar, a header Undo) is not the
    /// session's to compare or revert, so reopening then starts anew (#102).
    var lastSeen: ImageRef

    init(itemID: CanvasItem.ID, original: ImageRef) {
        self.itemID = itemID
        self.original = original
        self.lastSeen = original
    }

    /// Whether opening `id`, which now looks like `ref`, picks this session
    /// up again: the same photo, unchanged since the session last saw it.
    /// A caption or a description is not an edit.
    func continues(_ id: CanvasItem.ID, showing ref: ImageRef) -> Bool {
        id == itemID && ref.fileName == lastSeen.fileName
            && ref.filterName == lastSeen.filterName && ref.frameName == lastSeen.frameName
    }
}

/// The AI row's open session: the cached rewrites, and the block as it was
/// when the row opened (what the commit's one undo step goes back to).
struct RewriteState {
    var session: TextRewriteSession
    let original: CanvasItem
}

/// The custom color sheet, open for the block's text color (screen 14) or
/// its background (screen 20), and the block before the live preview.
struct ColorRequest {
    enum Target { case text, background }
    let target: Target
    let original: CanvasItem
    let initial: RGBColor

    /// What Apply puts on the block for the color `hex` the sheet shows;
    /// nil when it is the block's own color -- "ink" stays "ink" and no
    /// undo step is spent. A background sheet opened with none set shows
    /// #8B5962, and applies it.
    func applied(_ hex: String) -> String? {
        guard case .text(let block) = original.content else { return hex }
        let own = target == .text ? block.colorName : block.backgroundColorName
        return !own.isEmpty && hex == initial.hex ? nil : hex
    }
}

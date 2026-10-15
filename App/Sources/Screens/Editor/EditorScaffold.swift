import SwiftUI

/// Closures a scene calls to drive the editor flow. Every field defaults to a
/// no-op so the DEBUG catalog can render any scene statically.
struct EditorActions {
    var selectMode: (EditorMode) -> Void = { _ in }
    var go: () -> Void = {}
    var leading: () -> Void = {}
    var done: () -> Void = {}
}

/// Shared editor layout (v2.1): a single-row top bar, the memory page, and a
/// bottom cluster (context card + InputModeBar + action row) pinned to the
/// lower edge. The Page/Spread/zoom sub-toolbar is gone. Editing autosaves;
/// the canvas still labels its trailing action "Save" as the handoff does.
struct EditorScaffold<Page: View, Bottom: View>: View {
    var leading: String? = "Cancel"
    var leadingSymbol: String?
    var title: String = ""
    var trailing: String? = "Done"
    var onLeading: () -> Void = {}
    var onTrailing: () -> Void = {}
    var onUndo: (() -> Void)?
    var undoEnabled = true
    @ViewBuilder var page: () -> Page
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                leading: leading,
                leadingSymbol: leadingSymbol,
                title: title,
                trailing: trailing,
                onLeading: onLeading,
                onTrailing: onTrailing,
                onUndo: onUndo,
                undoEnabled: undoEnabled
            )
            page()
            // Handoff rhythm: canvas card, 20, tool bar, 16, composer, and
            // the composer's bottom 36 above the screen edge (2 above the
            // home-indicator inset).
            Spacer(minLength: Metrics.canvasToToolBar)
            VStack(spacing: 16) {
                bottom()
            }
            .padding(.bottom, 2)
        }
        .screenBackground()
    }
}

/// The small cup-style sticker placed on the page in the sticker/export scenes.
struct StickerBlob: View {
    var symbol = "cup.and.saucer.fill"
    var label = "cup"
    var size: CGFloat = 66

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Palette.taupe)
            Text(label)
                .font(Sans.font(size: 11, weight: 500))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.onInk)
                .shadow(color: Palette.ink.opacity(0.12), radius: 8, y: 3)
        )
    }
}

/// The cup sticker pinned to the top-right of a page's image area. Used by
/// the sticker and export scenes.
struct PlacedSticker: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                StickerBlob()
            }
            Spacer()
        }
        .padding(14)
    }
}

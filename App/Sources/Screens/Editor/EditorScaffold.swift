import MiraNoteKit
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
/// bottom cluster (InputModeBar + composer) pinned to the lower edge. Tool
/// sheets (Choose photos, Photo Editing, Sticker) sit over the canvas card's
/// lower edge, 20 above the tool bar, as the handoff draws them. Editing
/// autosaves; the canvas still labels its trailing action "Save".
struct EditorScaffold<Page: View, Sheet: View, Bottom: View>: View {
    var leading: String? = "Cancel"
    var leadingSymbol: String?
    var title: String = ""
    var trailing: String? = "Done"
    var onLeading: () -> Void = {}
    var onTrailing: () -> Void = {}
    var onUndo: (() -> Void)?
    var undoEnabled = true
    var leadingMuted = true
    var leadingID: String?
    var trailingID: String?
    var trailingEnabled = true
    var trailingFill = Palette.ink
    /// The text editing scrim (screens 11-20) over the margins around the
    /// page; the header and the bottom cluster stay above it. The page
    /// draws its own scrim around the block being written.
    var dimmed = false
    /// The handoff's dim glass scrim (screens 27-35): the canvas blurs under
    /// rgba(41, 51, 34, 0.34) while the chrome and the sheet stay clear.
    var scrimmed = false
    /// A tap on the scrimmed canvas card -- the tool's way back. The side
    /// margins are not the card and do nothing.
    var onScrimTap: () -> Void = {}
    @ViewBuilder var page: () -> Page
    @ViewBuilder var sheet: () -> Sheet
    @ViewBuilder var bottom: () -> Bottom
    @State private var bottomInset: CGFloat = 0

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
                undoEnabled: undoEnabled,
                leadingMuted: leadingMuted,
                leadingID: leadingID,
                trailingID: trailingID,
                trailingEnabled: trailingEnabled,
                trailingFill: trailingFill
            )
            page()
                .blur(radius: scrimmed ? 4 : 0)
                .overlay {
                    if scrimmed {
                        RoundedRectangle(cornerRadius: Metrics.canvasCorner)
                            .fill(Palette.scrim)
                            .canvasCardWidth()
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onScrimTap)
                            .padding(.horizontal, UIVariant.canvasSideInset ?? 0)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    sheet()
                        .padding(.horizontal, Metrics.chromeInset)
                        // Inside a filling card the sheet floats with the
                        // same margin below as beside it.
                        .padding(.bottom, max(0, Metrics.chromeInset - (UIVariant.canvasSideInset ?? Metrics.chromeInset)))
                }
            // Handoff rhythm: canvas card, 20, tool bar, 16, composer, and
            // the composer's bottom 36 above the screen edge (2 above the
            // home-indicator inset).
            Spacer(minLength: Metrics.canvasToToolBar)
            VStack(spacing: 16) {
                bottom()
            }
            .padding(.bottom, Metrics.bottomGap(safeAreaBottom: bottomInset))
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        // Beside and around the card the scrim tints the paper; the card
        // carries its own (blurred) layer above.
        .background {
            if dimmed || scrimmed {
                Palette.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: dimmed)
        .screenBackground()
    }
}

extension EditorScaffold where Sheet == EmptyView {
    init(
        leading: String? = "Cancel",
        leadingSymbol: String? = nil,
        title: String = "",
        trailing: String? = "Done",
        onLeading: @escaping () -> Void = {},
        onTrailing: @escaping () -> Void = {},
        onUndo: (() -> Void)? = nil,
        undoEnabled: Bool = true,
        @ViewBuilder page: @escaping () -> Page,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) {
        self.init(
            leading: leading,
            leadingSymbol: leadingSymbol,
            title: title,
            trailing: trailing,
            onLeading: onLeading,
            onTrailing: onTrailing,
            onUndo: onUndo,
            undoEnabled: undoEnabled,
            page: page,
            sheet: { EmptyView() },
            bottom: bottom
        )
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

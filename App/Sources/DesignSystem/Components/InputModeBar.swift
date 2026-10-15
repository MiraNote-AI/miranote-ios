import SwiftUI

/// The bottom tool bar (2026-10-07 handoff): one 40 pt icon capsule per tool,
/// sharing the row evenly. Inactive tools sit on the tool surface with a
/// hairline; the active one fills with the selected-tool green. Names live in
/// the accessibility label, not on screen.
struct InputModeBar: View {
    var active: EditorMode?
    var onSelect: (EditorMode) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    item(mode)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityIdentifier("mode.\(mode.rawValue)")
                .accessibilityAddTraits(mode == active ? .isSelected : [])
            }
        }
        .padding(.horizontal, Metrics.toolBarInset)
    }

    private func item(_ mode: EditorMode) -> some View {
        let isActive = mode == active
        return icon(mode)
            .foregroundStyle(isActive ? Palette.onInk : Palette.toolIcon)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                Capsule()
                    .fill(isActive ? Palette.selectedTool : Palette.toolSurface)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: isActive ? 0 : 1))
                    // The handoff lifts the active tile: 0 12 12 ink@0.10.
                    .shadow(color: Palette.ink.opacity(isActive ? 0.10 : 0), radius: 6, y: 12)
            )
            .minimumHitTarget()
    }

    private func icon(_ mode: EditorMode) -> some View {
        Image(mode.iconAsset)
            .renderingMode(.template)
            .resizable()
            .frame(width: 20, height: 20)
    }
}

/// Bottom hint + primary action ("Go") shared by most editor scenes.
struct ActionRow: View {
    let hint: String
    var actionTitle: String = "Go"
    var onGo: () -> Void = {}

    var body: some View {
        HStack {
            Text(hint)
                .font(.miraCaption)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button(actionTitle, action: onGo)
                .buttonStyle(PrimaryPill(horizontalPadding: 20, verticalPadding: 9))
        }
        .padding(.horizontal, Metrics.screenPadding)
    }
}

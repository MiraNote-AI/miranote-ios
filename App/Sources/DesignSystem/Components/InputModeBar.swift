import SwiftUI

/// The bottom "instrument panel": Voice / Text / Image / Sticker. The active
/// mode is an ink pill; the rest are quiet icon+label targets, spread evenly.
struct InputModeBar: View {
    var active: EditorMode?
    var onSelect: (EditorMode) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    item(mode)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(mode.title)
                .accessibilityIdentifier("mode.\(mode.rawValue)")
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private func item(_ mode: EditorMode) -> some View {
        let isActive = mode == active
        return HStack(spacing: 6) {
            icon(mode)
            Text(mode.title).font(.miraLabel).lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(isActive ? Palette.onInk : Palette.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isActive {
                Capsule().fill(Palette.ink)
            }
        }
    }

    @ViewBuilder private func icon(_ mode: EditorMode) -> some View {
        if mode == .text {
            Text("T").font(.system(size: 14, weight: .semibold, design: .serif))
        } else {
            Image(systemName: mode.symbol).font(.system(size: 13, weight: .medium))
        }
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

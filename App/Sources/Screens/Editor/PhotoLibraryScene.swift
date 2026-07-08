import SwiftUI

/// Flow 7 Scene 06: the photo picker -- a sheet over the dimmed editor with a
/// selectable Recents grid.
struct PhotoLibraryScene: View {
    var actions = EditorActions()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TopBar(title: "Canvas")
                SubToolbar()
                MemoryPage(
                    title: "Lunch by the river",
                    caption: "June 21 \u{00B7} calm afternoon"
                )
                Spacer()
            }
            .opacity(0.28)

            sheet
        }
        .screenBackground()
    }

    private var sheet: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Palette.hairline)
                .frame(width: 42, height: 5)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("My Photos").font(.miraCardTitle).foregroundStyle(Palette.ink)
                    Spacer()
                    Button(action: actions.leading) {
                        Text("Done")
                            .font(.miraLabel)
                            .foregroundStyle(Palette.onInk)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.ink))
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text("Recents").font(.miraLabel).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("2 selected").font(.miraCaption).foregroundStyle(Palette.textSecondary)
                }

                grid
            }
            .padding(.horizontal, 20)

            InputModeBar(active: .image, onSelect: actions.selectMode)
            ActionRow(hint: "Preview selected photos", onGo: actions.go)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(Palette.paper)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<9, id: \.self) { idx in
                photoTile(idx)
            }
        }
    }

    private func photoTile(_ idx: Int) -> some View {
        let selected = idx == 0 || idx == 2
        let badge = idx == 0 ? "1" : "2"
        return GradientPlaceholder(tint: tileTint(idx), corner: 14)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Palette.ink, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.onInk)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Palette.ink))
                        .padding(6)
                }
            }
    }

    private func tileTint(_ idx: Int) -> Color {
        let tints = [Palette.tan, Palette.sage, Palette.taupe]
        return tints[idx % tints.count]
    }
}

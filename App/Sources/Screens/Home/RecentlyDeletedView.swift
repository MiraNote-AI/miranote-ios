import MiraNoteKit
import SwiftUI

/// The 30-day bin (v2.1): deleted pages wait here instead of vanishing --
/// losing a memory to a slip would be a brand-level accident.
struct RecentlyDeletedView: View {
    var viewModel: HomeViewModel
    var onBack: () -> Void = {}

    var body: some View {
        Group {
            if viewModel.trash.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundStyle(Palette.textSecondary)
                    Text("Nothing waiting here.")
                        .font(.miraBody)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(viewModel.trash) { entry in
                            row(entry)
                        }
                        Text("Pages leave for good after 30 days.")
                            .font(.miraCaption)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .screenBackground()
        .safeAreaInset(edge: .top) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Home")
                    }
                }
                .buttonStyle(SoftPill())
                Spacer()
                Text("Recently deleted")
                    .font(.miraScreenTitle)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Color.clear.frame(width: 64, height: 1)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.vertical, 8)
            .background(Palette.paper.opacity(0.94))
        }
    }

    private func row(_ entry: TrashedMemory) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.memory.title.isEmpty ? "Untitled" : entry.memory.title)
                    .font(.miraCardTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("from \(entry.collectionTitle) \u{00B7} \(daysLeft(entry)) days left")
                    .font(.miraCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button("Restore") {
                viewModel.restore(entry.id)
            }
            .font(.miraLabel)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Palette.ink))
            .buttonStyle(.plain)
            .accessibilityIdentifier("trash.restore.\(entry.memory.title)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Palette.onInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
                )
        )
    }

    private func daysLeft(_ entry: TrashedMemory) -> Int {
        let expiry = entry.deletedAt.addingTimeInterval(30 * 24 * 3600)
        return max(0, Int(ceil(expiry.timeIntervalSince(.now) / 86400)))
    }
}

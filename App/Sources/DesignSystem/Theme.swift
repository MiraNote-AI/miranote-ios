import SwiftUI

/// v1 design tokens. Deliberately minimal -- visual polish is a later pass;
/// structure fidelity to the sketches comes first.
enum Theme {
    static let cornerRadius: CGFloat = 14
    static let pillPadding: CGFloat = 16
    static let canvasSpacing: CGFloat = 120
}

/// Capsule-shaped button used for the sketches' pill controls.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.pillPadding)
            .padding(.vertical, 10)
            .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.thinMaterial), in: Capsule())
            .foregroundStyle(prominent ? .white : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Book-spine look for collection cards on Home (sketch 1).
struct CollectionCard: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.thinMaterial)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.tint.opacity(0.6))
                        .frame(width: 8)
                        .clipShape(.rect(topLeadingRadius: 6, bottomLeadingRadius: 6))
                }
                .overlay {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
                .frame(width: 96, height: 128)
            Text("\(count) memories")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

import SwiftUI

// The tool slot's snap rows: Text (R6B) and Background (Q5A).

/// A snap row (R6B): the cells scroll under a center marker between faded
/// edges. The value cell that comes to rest under the marker applies, as
/// does a tapped one -- one undo step each; opening the row never applies.
/// When the block's value changes from outside (Undo, G24) the row scrolls
/// back to it without applying again. A value with no cell of its own (a
/// new block's ink) rests on the first cell, unselected. Action cells
/// (Custom) only act on a tap.
struct SnapRow<ID: Hashable, Cell: View>: View {
    let ids: [ID]
    /// The block's value: the row opens on it and follows it.
    let selected: ID?
    let cellWidth: CGFloat
    let spacing: CGFloat
    let identifier: (ID) -> String
    let onApply: (ID) -> Void
    var isAction: (ID) -> Bool = { _ in false }
    var onAction: (ID) -> Void = { _ in }
    /// Every tap on a cell, before it acts -- the chosen cell's too, which
    /// applies nothing: the Background color row's Keep (F4A).
    var onTap: (ID) -> Void = { _ in }
    @ViewBuilder let cell: (ID) -> Cell

    /// The cell under the marker.
    @State private var centered: ID?
    /// The cell the row was put on by code (opening, Undo), until a finger
    /// moves it: coming to rest there applies nothing.
    @State private var resting: ID?
    /// Bumped per apply, for its light haptic.
    @State private var applied = 0
    @State private var settleWait: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(ids, id: \.self) { id in
                        Button { tap(id) } label: {
                            cell(id).frame(width: cellWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(id == selected ? .isSelected : [])
                        .accessibilityIdentifier(identifier(id))
                        .id(id)
                    }
                }
                .scrollTargetLayout()
                // Room for the chips' shadows; the scroll view clips.
                .padding(.vertical, 8)
            }
            // Either end can come to rest under the marker.
            .contentMargins(.horizontal, max((geo.size.width - cellWidth) / 2, 0), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .modifier(SettleWatch(centered: centered, onTouch: { resting = nil }, onSettle: settle,
                                  wait: $settleWait))
            .padding(.vertical, -8)
            .frame(height: geo.size.height)
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                   .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .padding(.vertical, -12)
        }
        .overlay(alignment: .top) {
            // Just above the row, under the caption line.
            SnapMarker()
                .fill(Palette.forest)
                .frame(width: 9, height: 5)
                .offset(y: -6)
                .accessibilityHidden(true)
        }
        .onAppear {
            resting = home
            centered = home
        }
        .onChange(of: selected) {
            guard centered != home else { return }
            resting = home
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { centered = home }
        }
        .onDisappear { settleWait?.cancel() }
        .sensoryFeedback(.impact(weight: .light), trigger: applied)
    }

    /// Where the block's value sits in the row.
    private var home: ID? {
        if let selected, ids.contains(selected) { return selected }
        return ids.first
    }

    private func tap(_ id: ID) {
        onTap(id)
        if isAction(id) {
            onAction(id)
            return
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { centered = id }
        apply(id)
    }

    private func settle() {
        guard let id = centered, id != resting else { return }
        // Moved off where code put it: coming back there applies too. iOS 17
        // has no touch to clear it (`SettleWatch`), so the settle does.
        resting = nil
        guard !isAction(id) else { return }
        apply(id)
    }

    private func apply(_ id: ID) {
        guard id != selected else { return }
        onApply(id)
        applied += 1
    }
}

/// Calls `onTouch` when a finger moves the row and `onSettle` once the
/// row it moved comes to rest (iOS 18): a scroll by code, cut short by
/// another (a tap's, then Undo's), never settles. iOS 17 has no scroll
/// phase: the row settles a moment after the centered cell last changed,
/// so a finger held still on a cell for that long applies it too.
private struct SettleWatch<ID: Hashable>: ViewModifier {
    let centered: ID?
    let onTouch: () -> Void
    let onSettle: () -> Void
    @Binding var wait: Task<Void, Never>?
    /// A finger moved the row since it last came to rest.
    @State private var touched = false

    func body(content: Content) -> some View {
        if Self.waitsAsOnIOS17 {
            waited(content)
        } else if #available(iOS 18, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    touched = true
                    onTouch()
                }
                if phase == .idle, touched {
                    touched = false
                    onSettle()
                }
            }
        } else {
            waited(content)
        }
    }

    private func waited(_ content: Content) -> some View {
        content.onChange(of: centered) {
            wait?.cancel()
            wait = Task {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { onSettle() }
            }
        }
    }

    /// Tests only: the iOS 17 settle on a newer system, which the
    /// simulators run (`-SNAP_SETTLE_IOS17`).
    private static var waitsAsOnIOS17: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-SNAP_SETTLE_IOS17")
        #else
        return false
        #endif
    }
}

/// The snap rows' center marker: a small triangle pointing down.
private struct SnapMarker: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

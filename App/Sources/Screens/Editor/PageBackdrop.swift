import MiraNoteKit
import SwiftUI

/// The page's full-bleed backdrop, shared by the editor and the static
/// renderers, bottom to top: the page color (or the default dawn-to-dusk
/// gradient, mockup 2026-07-11), the painted background image if any, then
/// the paper ruling. A missing image file falls back to what is under it --
/// never a hole.
struct PageBackdrop: View {
    let memory: Memory

    private let imageStore = ImageFileStore()
    private static let shape = RoundedRectangle(cornerRadius: 24)

    var body: some View {
        base
            .overlay(backgroundImage)
            .overlay(PaperRuling(kind: memory.paper).clipShape(Self.shape))
    }

    @ViewBuilder private var base: some View {
        if memory.pageColorName.isEmpty {
            Self.shape.fill(
                LinearGradient(
                    colors: [Palette.backdropDawn, Palette.backdropDusk],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            Self.shape.fill(Palette.color(named: memory.pageColorName))
        }
    }

    @ViewBuilder private var backgroundImage: some View {
        // Through the shared cache: journal covers render many pages,
        // and a full-bleed re-decode per appearance stutters the grid.
        if let image = CanvasImageCache.image(
            fileName: memory.backgroundFileName, filterName: "", store: imageStore
        ) {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(Self.shape)
            }
        }
    }
}

/// Grid, lined or dot ruling drawn in faint ink over the page; blank draws
/// nothing. The spacing is fixed in points so a long page keeps an even
/// rhythm instead of stretching.
struct PaperRuling: View {
    let kind: PaperKind
    static let spacing: CGFloat = 22

    var body: some View {
        if kind != .blank {
            Canvas { context, size in
                let ink = GraphicsContext.Shading.color(Palette.ink.opacity(0.14))
                let step = Self.spacing
                switch kind {
                case .grid:
                    var path = Path()
                    for x in stride(from: step, to: size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: step, to: size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: ink, lineWidth: 0.6)
                case .lined:
                    var path = Path()
                    for y in stride(from: step * 2, to: size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: ink, lineWidth: 0.6)
                case .dot:
                    for x in stride(from: step, to: size.width, by: step) {
                        for y in stride(from: step, to: size.height, by: step) {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                                with: ink
                            )
                        }
                    }
                case .blank:
                    break
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

import MiraNoteKit
import SwiftUI
import UIKit

/// The page's full-bleed backdrop, shared by the editor and the static
/// renderers, bottom to top: the page color (or the default dawn-to-dusk
/// gradient, mockup 2026-07-11), the painted background image if any, then
/// the paper ruling. A missing image file falls back to what is under it --
/// never a hole.
struct PageBackdrop: View {
    let memory: Memory

    private let imageStore = ImageFileStore()
    /// r24 as pages have always been drawn and exported; the editor's r30
    /// card (`canvasCard()`) clips its own view of the page.
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

extension View {
    /// The handoff's canvas card (screens 04-07, 22): a page-wide window
    /// onto the page, r30, a 1 pt ink@0.06 rim and the `0 16 38 ink@0.08`
    /// shadow. The page keeps its fixed design width, so on a 402 pt phone
    /// the card sits 21 in from each edge (the design's 20 on 374).
    func canvasCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.canvasCorner)
        return frame(width: MiraNoteConfig.pageWidth)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.ink.opacity(0.06), lineWidth: Metrics.hairline))
            .background(shape.fill(Palette.paper).shadow(color: Palette.ink.opacity(0.08), radius: 19, y: 16))
            .frame(maxWidth: .infinity)
    }
}

/// Grid, lined or dot ruling drawn in faint ink over the page; blank draws
/// nothing. One small tile per kind is drawn once and repeated by the GPU
/// (`ImagePaint`), so a page of any height costs the same -- a page-sized
/// Canvas would rasterize one bitmap that outgrows the texture limit on long
/// pages. The spacing is fixed in points, so a long page keeps an even rhythm.
struct PaperRuling: View {
    let kind: PaperKind
    static let spacing: CGFloat = 22

    var body: some View {
        if let tile = Self.tiles[kind] {
            Rectangle()
                .fill(ImagePaint(image: Image(uiImage: tile)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private static let tiles: [PaperKind: UIImage] = {
        var made: [PaperKind: UIImage] = [:]
        for kind in PaperKind.allCases where kind != .blank {
            made[kind] = tile(for: kind)
        }
        return made
    }()

    /// One `spacing` x `spacing` cell: the line or dot sits on the cell's
    /// right/bottom edge, so repeating cells reproduce the ruling exactly.
    private static func tile(for kind: PaperKind) -> UIImage {
        let side = spacing
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            UIColor(Palette.ink.opacity(0.14)).setFill()
            switch kind {
            case .grid:
                cg.fill(CGRect(x: side - 0.6, y: 0, width: 0.6, height: side))
                cg.fill(CGRect(x: 0, y: side - 0.6, width: side, height: 0.6))
            case .lined:
                cg.fill(CGRect(x: 0, y: side - 0.6, width: side, height: 0.6))
            case .dot:
                cg.fillEllipse(in: CGRect(x: side - 2, y: side - 2, width: 2, height: 2))
            case .blank:
                break
            }
        }
    }
}

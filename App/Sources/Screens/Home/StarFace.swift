import CoreImage
import MiraNoteKit
import SwiftUI
import UIKit

/// A page's star (#206): a strip of the page wound into a lucky star. At
/// Save the page's top is read for its most colorful row (`StarStrip`) and
/// the star's dress -- its washed colors, unlit and upright
/// (`PaperStar.dressing`) -- is baked once and kept by page id in
/// Caches/star-dress; the light is drawn over it live, so a turned star
/// keeps its light from the top left. A page with a photo, a sticker or a
/// photo backdrop gives its most colorful band; a page of words gives a
/// calm paper star. Pages from before are baked when the jar first shows
/// them, a frame apart (`bakeInTurn`). Only the rendering of the page is
/// on the main actor; the cut is not.
@MainActor
enum StarFace {
    /// Points a side; baked at 2x, twice the largest star in the jar.
    static let side: CGFloat = 96
    /// The page's top that the strip is cut from: 196 x 256 px.
    nonisolated private static let snapshot = (width: 196, height: 256)
    private static var pageTop: CGSize {
        CGSize(width: MiraNoteConfig.pageWidth,
               height: MiraNoteConfig.pageWidth * CGFloat(snapshot.height) / CGFloat(snapshot.width))
    }
    private static let dresses = NSCache<NSUUID, UIImage>()
    /// Lit and upright, for the toss's sprites.
    private static let faces = NSCache<NSUUID, UIImage>()

    private static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private static var directory: URL {
        caches.appendingPathComponent("star-dress", isDirectory: true)
    }

    /// Where part A of #206 kept its lit stars: swept, no longer read.
    private static var litStarsDirectory: URL {
        caches.appendingPathComponent("stars", isDirectory: true)
    }

    private static func file(_ id: Memory.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    /// The page's dress as last baked, nil if it never was.
    static func cached(_ id: Memory.ID) -> UIImage? {
        if let dress = dresses.object(forKey: id as NSUUID) { return dress }
        guard let dress = UIImage(contentsOfFile: file(id).path) else { return nil }
        dresses.setObject(dress, forKey: id as NSUUID)
        return dress
    }

    /// The page's star lit and upright, as the toss throws it; a plain
    /// paper star until its dress is baked.
    static func face(for id: Memory.ID) -> UIImage {
        if let face = faces.object(forKey: id as NSUUID) { return face }
        let dress = cached(id)
        let renderer = ImageRenderer(content: PaperStarView(
            dress: dress.map { .baked(Image(uiImage: $0)) } ?? .paint(.paper)
        ).frame(width: side, height: side))
        renderer.scale = 2
        let face = renderer.uiImage ?? UIImage()
        if dress != nil { faces.setObject(face, forKey: id as NSUUID) }
        return face
    }

    /// When the last missing star was baked (`bakeInTurn`).
    private static var lastTurn: ContinuousClock.Instant?
    /// A missing star is being baked: the next one waits for it.
    private static var baking = false
    private static let turnGap = Duration.milliseconds(17)

    /// Bakes a star the jar finds missing (a page not saved since #206, or
    /// one whose dress iOS cleared from Caches) in its turn: one at a
    /// time, at least a frame after the last such bake, so a jar of old
    /// pages fills in a star at a time instead of in one stall. Nil if the
    /// waiting star went away first.
    static func bakeInTurn(_ memory: Memory) async -> UIImage? {
        while let wake = nextTurn() {
            do { try await Task.sleep(until: wake, clock: .continuous) } catch { return nil }
        }
        if let dress = cached(memory.id) { return dress }
        baking = true
        defer {
            baking = false
            lastTurn = .now
        }
        return await bake(memory)
    }

    /// When a waiting bake may look again; nil once its turn has come.
    private static func nextTurn() -> ContinuousClock.Instant? {
        let now = ContinuousClock.now
        if baking { return now + turnGap }
        guard let last = lastTurn, now < last + turnGap else { return nil }
        return last + turnGap
    }

    /// Bakes the page's dress as it is now and keeps it. Save calls this:
    /// an edited page's star follows its page.
    @discardableResult
    static func bake(_ memory: Memory) async -> UIImage? {
        guard let page = render(memory, scale: CGFloat(snapshot.width) / MiraNoteConfig.pageWidth) else { return nil }
        return keep(StarPaint(await cutting(memory, page).look), for: memory.id)
    }

    /// Keeps `paper`'s dress for the page.
    static func keep(_ paper: StarPaper, for id: Memory.ID) {
        keep(paper.paint, for: id)
    }

    /// Drops the page's dress, when the page is gone for good.
    static func forget(_ id: Memory.ID) {
        dresses.removeObject(forKey: id as NSUUID)
        faces.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: file(id))
    }

    /// The page ready to fold or unfold (design X): the page as reading
    /// mode shows it at screen resolution, the row of its top half it
    /// folds up onto, that row as a strip, the strip softened for the
    /// star's faces, and the star's paint.
    static func paper(for memory: Memory) async -> StarPaper? {
        let scale = UITraitCollection.current.displayScale
        let height = foldHeight(memory)
        guard let page = render(memory, height: height, scale: scale),
              let top = page.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(page.width),
                                                 height: (pageTop.height * scale).rounded())) else { return nil }
        let (row, look) = await cutting(memory, top)
        let tile = StarPaper.tile * scale
        guard let band = page.cropping(to: CGRect(x: 0, y: (CGFloat(row) * tile).rounded(),
                                                  width: CGFloat(page.width), height: tile.rounded()))
        else { return nil }
        let face = await Task.detached(priority: .userInitiated) { soften(band, scale: scale) }.value
        return StarPaper(
            page: Image(decorative: page, scale: scale), fullHeight: height, row: row,
            strip: Image(decorative: band, scale: scale), face: Image(decorative: face ?? band, scale: scale),
            paint: StarPaint(look), shadow: Image(uiImage: pageShadow)
        )
    }

    /// How much of the page the fold draws: its top 560, and below that as
    /// far as reading mode shows it on this screen.
    private static func foldHeight(_ memory: Memory) -> CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let screen = window?.bounds.size ?? CGSize(width: 402, height: 874)
        let shown = (screen.height - OpenUnfold.readingTop) / CanvasCard.pageScale(rowWidth: screen.width)
        return min(StaticPageView.contentHeight(of: memory), max(StarPaper.height, shown.rounded(.up)))
    }

    /// The band blurred and a little brighter: the faces' colors without
    /// the photo's detail.
    nonisolated private static func soften(_ band: CGImage, scale: CGFloat) -> CGImage? {
        let source = CIImage(cgImage: band)
        let soft = source.clampedToExtent()
            .applyingGaussianBlur(sigma: 2.4 * scale)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.2])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.07])
            .cropped(to: source.extent)
        return softener.createCGImage(soft, from: source.extent)
    }

    nonisolated private static let softener = CIContext()

    /// The page's soft warm shadow, drawn once: 70 pt round a 360 x 560
    /// page, stretched to what the fold shows.
    private static let pageShadow: UIImage = {
        let margin = StarPaper.shadowMargin
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: StarPaper.width + 2 * margin, height: StarPaper.height + 2 * margin)
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            // Drawn far off and its shadow thrown back in: only the blur shows.
            context.setShadow(offset: CGSize(width: 0, height: 10_000), blur: 32,
                              color: UIColor(red: 150 / 255, green: 82 / 255, blue: 62 / 255, alpha: 0.2).cgColor)
            UIColor.black.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: margin - 10_000, width: StarPaper.width,
                                             height: StarPaper.height),
                         cornerRadius: StarPaper.corner).fill()
        }
    }()

    /// The row of the page's top half it folds onto, and the star's look
    /// from that row (calm paper for a page of words), worked out off the
    /// main actor.
    private static func cutting(_ memory: Memory, _ page: CGImage) async -> (row: Int, look: StarLook) {
        let wordsOnly = isWordsOnly(memory), id = memory.id
        return await Task.detached(priority: .userInitiated) {
            let pixels = pixels(of: page)
            let row = StarStrip.foldRow(in: pixels)
            var strip = StarStrip.strip(StarStrip.foldCut(row, in: pixels), from: pixels)
            if wordsOnly { strip = StarStrip.calm(strip, id: id) }
            return (row, StarStrip.look(strip))
        }.value
    }

    @discardableResult
    private static func keep(_ paint: StarPaint, for id: Memory.ID) -> UIImage? {
        let renderer = ImageRenderer(content: Canvas { context, size in
            var dress = context
            dress.translateBy(x: size.width / 2, y: size.height / 2)
            PaperStar.dressing(in: dress, radius: size.width / 2.1, paint: paint)
        }.frame(width: side, height: side))
        renderer.scale = 2
        guard let dress = renderer.uiImage else { return nil }
        dresses.setObject(dress, forKey: id as NSUUID)
        faces.removeObject(forKey: id as NSUUID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? dress.pngData()?.write(to: file(id), options: .atomic)
        return dress
    }

    /// Drops the stars of pages gone for good (their 30 days in the bin
    /// are up): a page on the shelf or in the bin keeps its star. Both
    /// folders are swept: the dresses, and part A's lit stars.
    static func forget(allBut library: MemoryLibrary) {
        let pages = library.collections.flatMap(\.memories) + library.trash.map(\.memory)
        let kept = Set(pages.map(\.id))
        let manager = FileManager.default
        for folder in [directory, litStarsDirectory] {
            let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "png" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !kept.contains(id) else { continue }
                dresses.removeObject(forKey: id as NSUUID)
                faces.removeObject(forKey: id as NSUUID)
                try? manager.removeItem(at: file)
            }
        }
    }

    /// No photo, sticker or photo backdrop: nothing colorful to find.
    private static func isWordsOnly(_ memory: Memory) -> Bool {
        memory.backgroundFileName.isEmpty && !memory.items.contains { item in
            switch item.content {
            case .image, .sticker: return true
            case .text, .sound: return false
            }
        }
    }

    /// The page's top, `height` points (`pageTop` unless given), on its paper.
    private static func render(_ memory: Memory, height: CGFloat? = nil, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: StaticPageView(
            memory: memory, designWidth: MiraNoteConfig.pageWidth, showsSound: false
        )
        .frame(width: pageTop.width, height: height ?? pageTop.height, alignment: .top)
        .background(Palette.paper)
        .clipped())
        renderer.scale = scale
        return renderer.cgImage
    }

    /// `page` at `snapshot`'s size.
    nonisolated private static func pixels(of page: CGImage) -> StarPixels {
        let width = snapshot.width, height = snapshot.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .high
            context.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return StarPixels(width: width, height: height, rgba: rgba)
    }
}

/// A page's star as the jar shows it: its baked dress under a live light
/// that stays top left however the star is turned (`rotation`, degrees,
/// animatable), or until the dress is ready a plain paper star.
struct PageStar: View, Animatable {
    let memory: Memory
    var rotation: Double = 0

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    @State private var dress: UIImage?

    var body: some View {
        // The cache first: a Save bakes the page again, and a dress baked
        // here earlier would be the page as it was.
        let baked = StarFace.cached(memory.id) ?? dress
        PaperStarView(dress: baked.map { .baked(Image(uiImage: $0)) } ?? .paint(.paper),
                      rotation: CGFloat(rotation * .pi / 180))
            .task(id: memory.id) {
                guard StarFace.cached(memory.id) == nil else { return }
                // One page at a time, a frame apart: a jar of old pages
                // bakes without a stall.
                dress = await StarFace.bakeInTurn(memory)
            }
    }
}

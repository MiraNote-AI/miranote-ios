import MiraNoteKit
import SwiftUI
import UIKit

/// A page's star (#206): a strip of the page wound into a lucky star. At
/// Save the page's top is cut (`StarStrip`, the most colorful band) and
/// the star's dress -- its washed colors, unlit and upright
/// (`PaperStar.dressing`) -- is baked once and kept by page id in
/// Caches/star-dress; the light is drawn over it live, so a turned star
/// keeps its light from the top left. A page with a photo, a sticker or a
/// photo backdrop gives its most colorful band; a page of words gives a
/// calm paper star. Pages from before are baked when the jar first shows
/// them. Only the rendering of the page is on the main actor; the cut is
/// not.
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

    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("star-dress", isDirectory: true)
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

    /// The page ready to fold or unfold: its top at screen resolution,
    /// the cut, the strip and the star's paint.
    static func paper(for memory: Memory) async -> StarPaper? {
        let scale = UITraitCollection.current.displayScale
        guard let page = render(memory, scale: scale) else { return nil }
        let (cut, look) = await cutting(memory, page)
        let toPage = MiraNoteConfig.pageWidth / CGFloat(snapshot.width)
        let center = CGPoint(x: cut.centerX * toPage, y: cut.centerY * toPage)
        let length = cut.length * toPage, thickness = cut.thickness * toPage
        let strip = UIGraphicsImageRenderer(size: CGSize(width: length, height: thickness)).image { renderer in
            let context = renderer.cgContext
            UIColor(Color(hex: 0xF4EEE3)).setFill()
            context.fill(CGRect(x: 0, y: 0, width: length, height: thickness))
            context.translateBy(x: length / 2, y: thickness / 2)
            context.rotate(by: -cut.angle)
            context.translateBy(x: -center.x, y: -center.y)
            UIImage(cgImage: page).draw(in: CGRect(origin: .zero, size: pageTop))
        }
        let margin = StarPaper.shadowMargin
        // Soft enough to bake at 1x: a 50 pt blur at 3x costs the Save.
        let flat = UIGraphicsImageRendererFormat()
        flat.scale = 1
        let shadow = UIGraphicsImageRenderer(
            size: CGSize(width: pageTop.width + 2 * margin, height: pageTop.height + 2 * margin), format: flat
        ).image { renderer in
            let context = renderer.cgContext
            context.setShadow(offset: CGSize(width: 0, height: 20), blur: 50,
                              color: UIColor(red: 40 / 255, green: 28 / 255, blue: 16 / 255, alpha: 0.25).cgColor)
            UIColor(Color(hex: 0xF4EEE3)).setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: margin, width: pageTop.width, height: pageTop.height),
                         cornerRadius: 30).fill()
        }
        return StarPaper(
            page: Image(decorative: page, scale: scale), pageSize: pageTop,
            cutCenter: center, cutAngle: cut.angle, stripLength: length, stripThickness: thickness,
            strip: Image(uiImage: strip), paint: StarPaint(look), pageShadow: Image(uiImage: shadow)
        )
    }

    /// The most colorful band of the page's top, and the star's look from
    /// it (calm paper for a page of words), worked out off the main actor.
    private static func cutting(_ memory: Memory, _ page: CGImage) async -> (cut: StarStrip.Cut, look: StarLook) {
        let wordsOnly = isWordsOnly(memory), id = memory.id
        return await Task.detached(priority: .userInitiated) {
            let pixels = pixels(of: page)
            let cut = StarStrip.colorfulCut(in: pixels)
            var strip = StarStrip.strip(cut, from: pixels)
            if wordsOnly { strip = StarStrip.calm(strip, id: id) }
            return (cut, StarStrip.look(strip))
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

    /// No photo, sticker or photo backdrop: nothing colorful to find.
    private static func isWordsOnly(_ memory: Memory) -> Bool {
        memory.backgroundFileName.isEmpty && !memory.items.contains { item in
            switch item.content {
            case .image, .sticker: return true
            case .text, .sound: return false
            }
        }
    }

    /// The page's top, `pageTop` points, on its paper.
    private static func render(_ memory: Memory, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: StaticPageView(
            memory: memory, designWidth: MiraNoteConfig.pageWidth, showsSound: false
        )
        .frame(width: pageTop.width, height: pageTop.height, alignment: .top)
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
        let baked = dress ?? StarFace.cached(memory.id)
        PaperStarView(dress: baked.map { .baked(Image(uiImage: $0)) } ?? .paint(.paper),
                      rotation: CGFloat(rotation * .pi / 180))
            .task(id: memory.id) {
                guard StarFace.cached(memory.id) == nil else { return }
                // One page at a time, between frames: a jar of old pages
                // bakes without a stall.
                await Task.yield()
                dress = await StarFace.bake(memory)
            }
    }
}

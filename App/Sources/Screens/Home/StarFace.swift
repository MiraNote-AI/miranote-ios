import MiraNoteKit
import SwiftUI
import UIKit

/// A page's star (#206): a strip of the page wound into a lucky star. At
/// Save the page's top is cut (`StarStrip`, the most colorful band) and
/// the star is drawn once in its washed colors (`PaperStar`), kept by
/// page id in Caches/paper-stars. A page with a photo, a sticker or a
/// photo backdrop gives its most colorful band; a page of words gives a
/// calm paper star. Pages from before are baked when the jar first shows
/// them.
@MainActor
enum StarFace {
    /// Points a side; baked at 2x, twice the largest star in the jar.
    static let side: CGFloat = 96
    /// The page's top that the strip is cut from: 196 x 256 px.
    private static let snapshot = (width: 196, height: 256)
    private static var pageTop: CGSize {
        CGSize(width: MiraNoteConfig.pageWidth,
               height: MiraNoteConfig.pageWidth * CGFloat(snapshot.height) / CGFloat(snapshot.width))
    }
    private static let faces = NSCache<NSUUID, UIImage>()

    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("paper-stars", isDirectory: true)
    }

    private static func file(_ id: Memory.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    /// The page's star as last baked, nil if it never was.
    static func cached(_ id: Memory.ID) -> UIImage? {
        if let face = faces.object(forKey: id as NSUUID) { return face }
        guard let face = UIImage(contentsOfFile: file(id).path) else { return nil }
        faces.setObject(face, forKey: id as NSUUID)
        return face
    }

    /// The page's star, baked now if it never was.
    static func face(for memory: Memory) -> UIImage? {
        cached(memory.id) ?? bake(memory)
    }

    /// Bakes the page's star as it is now and keeps it. Save calls this:
    /// an edited page's star follows its page.
    @discardableResult
    static func bake(_ memory: Memory) -> UIImage? {
        guard let page = render(memory, scale: CGFloat(snapshot.width) / MiraNoteConfig.pageWidth) else { return nil }
        return keep(StarPaint(cutting(memory, page).look), for: memory.id)
    }

    /// Keeps `paper`'s star as the page's face: a Save that folds bakes
    /// once the star has landed, not while the fold starts.
    static func keep(_ paper: StarPaper, for id: Memory.ID) {
        keep(paper.paint, for: id)
    }

    /// The page ready to fold or unfold: its top at screen resolution,
    /// the cut, the strip and the star's paint.
    static func paper(for memory: Memory) -> StarPaper? {
        let scale = UITraitCollection.current.displayScale
        guard let page = render(memory, scale: scale) else { return nil }
        let (cut, look) = cutting(memory, page)
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
    /// it: calm paper for a page of words.
    private static func cutting(_ memory: Memory, _ page: CGImage) -> (cut: StarStrip.Cut, look: StarLook) {
        let pixels = pixels(of: page)
        let cut = StarStrip.colorfulCut(in: pixels)
        var strip = StarStrip.strip(cut, from: pixels)
        if isWordsOnly(memory) { strip = StarStrip.calm(strip, id: memory.id) }
        return (cut, StarStrip.look(strip))
    }

    @discardableResult
    private static func keep(_ paint: StarPaint, for id: Memory.ID) -> UIImage? {
        let renderer = ImageRenderer(content: PaperStarView(paint: paint).frame(width: side, height: side))
        renderer.scale = 2
        guard let face = renderer.uiImage else { return nil }
        faces.setObject(face, forKey: id as NSUUID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? face.pngData()?.write(to: file(id), options: .atomic)
        return face
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
    private static func pixels(of page: CGImage) -> StarPixels {
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

/// A page's star as the jar shows it: its baked face, or until that is
/// ready a plain paper star.
struct PageStar: View {
    let memory: Memory

    @State private var face: UIImage?

    var body: some View {
        Group {
            if let face = face ?? StarFace.cached(memory.id) {
                Image(uiImage: face).resizable()
            } else {
                PaperStarView(paint: .paper)
            }
        }
        .task(id: memory.id) {
            guard StarFace.cached(memory.id) == nil else { return }
            // One page at a time, between frames: a jar of old pages
            // bakes without a stall.
            await Task.yield()
            face = StarFace.bake(memory)
        }
    }
}

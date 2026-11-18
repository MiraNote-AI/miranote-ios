import MiraNoteKit
import SwiftUI
import UIKit

/// A page's star (#206): a strip of the page wound into a lucky star,
/// baked once at Save from a 196 x 256 px snapshot of the page's top
/// (`StarStrip`) and kept by page id in Caches/stars. A page with a photo,
/// a sticker or a photo backdrop gives its most colorful band; a page of
/// words gives a calm paper star. Pages from before are baked when the
/// jar first shows them.
@MainActor
enum StarFace {
    /// Pixels a side: twice the largest star in the jar.
    static let side = 192
    private static let snapshot = (width: 196, height: 256)
    private static let faces = NSCache<NSUUID, UIImage>()

    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("stars", isDirectory: true)
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

    /// When the last missing star was baked (`bakeInTurn`).
    private static var lastTurn: ContinuousClock.Instant?
    private static let turnGap = Duration.milliseconds(17)

    /// Bakes a star the jar finds missing (a page not saved since #206, or
    /// one whose star iOS cleared from Caches) in its turn: at least a
    /// frame after the last such bake, so a jar of old pages fills in a
    /// star at a time instead of in one stall. Nil if the waiting star
    /// went away first.
    static func bakeInTurn(_ memory: Memory) async -> UIImage? {
        while let last = lastTurn, ContinuousClock.now < last + turnGap {
            do { try await Task.sleep(until: last + turnGap, clock: .continuous) } catch { return nil }
        }
        if let face = cached(memory.id) { return face }
        defer { lastTurn = .now }
        return bake(memory)
    }

    /// Bakes the page's star as it is now and keeps it. Save calls this:
    /// an edited page's star follows its page.
    @discardableResult
    static func bake(_ memory: Memory) -> UIImage? {
        guard let page = pixels(of: memory) else { return nil }
        var strip = StarStrip.strip(StarStrip.colorfulCut(in: page), from: page)
        if isWordsOnly(memory) { strip = StarStrip.calm(strip, id: memory.id) }
        guard let wound = image(StarStrip.wrap(strip, side: side)) else { return nil }
        let renderer = ImageRenderer(content: StarFaceMark(wound: Image(uiImage: wound))
            .frame(width: CGFloat(side) / 2, height: CGFloat(side) / 2))
        renderer.scale = 2
        guard let face = renderer.uiImage else { return nil }
        faces.setObject(face, forKey: memory.id as NSUUID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? face.pngData()?.write(to: file(memory.id), options: .atomic)
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

    /// The page's top at `snapshot`'s size, on the paper where its
    /// corners round off.
    private static func pixels(of memory: Memory) -> StarPixels? {
        let renderer = ImageRenderer(content: StaticPageView(
            memory: memory, designWidth: MiraNoteConfig.pageWidth, showsSound: false
        ))
        renderer.scale = CGFloat(snapshot.width) / MiraNoteConfig.pageWidth
        guard let page = renderer.cgImage else { return nil }
        let width = snapshot.width, height = snapshot.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(UIColor(Palette.paper).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Core Graphics is y up: the page's top lands at the top row.
            context.draw(page, in: CGRect(x: 0, y: height - page.height, width: page.width, height: page.height))
            return true
        }
        return drawn ? StarPixels(width: width, height: height, rgba: rgba) : nil
    }

    private static func image(_ pixels: StarPixels) -> UIImage? {
        let data = Data(pixels.rgba) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(
            width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// The wound strip in the star's outline, with `StarMark`'s soft light
/// from above and hairline edge.
private struct StarFaceMark: View {
    let wound: Image

    var body: some View {
        wound
            .resizable()
            .clipShape(RoundedStar())
            .overlay(
                RoundedStar().fill(
                    LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                )
            )
            .overlay(RoundedStar().stroke(Palette.ink.opacity(0.12), lineWidth: 0.6))
    }
}

/// A page's star as the jar shows it: its baked face, or until that is
/// ready a plain paper star.
struct PageStar: View {
    let memory: Memory

    @State private var face: UIImage?

    var body: some View {
        Group {
            // The cache first: a Save bakes the page again, and a face
            // baked here earlier would be the page as it was.
            if let face = StarFace.cached(memory.id) ?? face {
                Image(uiImage: face).resizable()
            } else {
                StarMark(color: StarMark.paper)
            }
        }
        .task(id: memory.id) {
            guard StarFace.cached(memory.id) == nil else { return }
            // One page at a time, a frame apart: a jar of old pages bakes
            // without a stall.
            face = await StarFace.bakeInTurn(memory)
        }
    }
}

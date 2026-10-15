import CoreGraphics
import MiraNoteKit
import UIKit
import XCTest
@testable import MiraNote

/// The export formats (redesign phase C1): the rendered long page becomes
/// PNG, JPG or PDF, and PDF can be one long page or cut into A4 pages.
final class PageExporterTests: XCTestCase {
    /// A long page as the renderer would hand it over: 100 x 500 pt, 1x.
    private let page: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 500), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 500))
        }
    }()

    private func prefix(_ data: Data, _ count: Int) -> [UInt8] { Array(data.prefix(count)) }

    private func pdfPages(_ data: Data) throws -> [CGRect] {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        return (1...document.numberOfPages).compactMap { document.page(at: $0)?.getBoxRect(.mediaBox) }
    }

    func testPNGIsAPNG() throws {
        let data = try XCTUnwrap(PageExporter.data(from: page, format: .png))
        XCTAssertEqual(prefix(data, 4), [0x89, 0x50, 0x4E, 0x47])
    }

    func testJPGIsAJPEG() throws {
        let data = try XCTUnwrap(PageExporter.data(from: page, format: .jpg))
        XCTAssertEqual(prefix(data, 3), [0xFF, 0xD8, 0xFF])
    }

    // The page's backdrop has rounded corners, so the render is transparent
    // there; JPG has no alpha and must not turn those corners black.
    func testJPGCornersAreTheScreenNotBlack() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rounded = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in
            UIColor.orange.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 24).fill()
        }
        let data = try XCTUnwrap(PageExporter.data(from: rounded, format: .jpg))
        let corner = try XCTUnwrap(pixel(at: CGPoint(x: 0, y: 0), in: data))
        XCTAssertGreaterThan(corner.red + corner.green + corner.blue, 600, "the corner is light, like the app's screen")
    }

    // Exports keep the r24 page corner they always had; the editor's r30
    // card clips its own view of the page. At (8.5, 8.5) pt a r24 corner is
    // filled and a r30 one is not.
    @MainActor
    func testExportedPagesKeepTheR24Corner() throws {
        let image = try XCTUnwrap(PageExporter.render(Memory(pageColorName: "#24382D"), quality: .standard))
        let cgImage = try XCTUnwrap(image.cgImage)
        func alpha(atPoint point: CGFloat) -> UInt8 {
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            let pixel = point * image.scale
            context?.draw(cgImage, in: CGRect(x: -pixel, y: -(CGFloat(cgImage.height) - 1 - pixel),
                                              width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            return bytes[3]
        }
        XCTAssertGreaterThan(alpha(atPoint: 8.5), 200, "inside a r24 corner")
        XCTAssertLessThan(alpha(atPoint: 2), 50, "the corner itself stays open")
    }

    /// The RGB of one pixel of an encoded image.
    private func pixel(at point: CGPoint, in data: Data) -> (red: Int, green: Int, blue: Int)? {
        guard let cgImage = UIImage(data: data)?.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: -point.x, y: -(CGFloat(cgImage.height) - 1 - point.y),
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    func testLongPDFIsOnePageTheSizeOfThePage() throws {
        let data = try XCTUnwrap(PageExporter.data(from: page, format: .pdf, pdfLayout: .longPage))
        XCTAssertEqual(prefix(data, 4), Array("%PDF".utf8))
        let pages = try pdfPages(data)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].size.width, 100, accuracy: 0.5)
        XCTAssertEqual(pages[0].size.height, 500, accuracy: 0.5)
    }

    func testA4PDFCutsTheLongPageIntoA4ShapedPages() throws {
        let data = try XCTUnwrap(PageExporter.data(from: page, format: .pdf, pdfLayout: .a4Pages))
        let pages = try pdfPages(data)
        // A4 is 1 : sqrt(2); a 100 pt wide page is 141.4 pt tall, so 500 pt
        // of content needs four pages, the last one partly empty.
        XCTAssertEqual(pages.count, 4)
        for box in pages {
            XCTAssertEqual(box.size.width, 100, accuracy: 0.5)
            XCTAssertEqual(box.size.height / box.size.width, 2.squareRoot(), accuracy: 0.01)
        }
    }

    func testALongPDFTallerThanThePDFLimitIsScaledToFit() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 20_000), format: format).image { _ in }
        let data = try XCTUnwrap(PageExporter.data(from: tall, format: .pdf, pdfLayout: .longPage))
        let pages = try pdfPages(data)
        XCTAssertEqual(pages.count, 1)
        XCTAssertLessThanOrEqual(pages[0].size.height, PageExporter.maxPDFPageSide)
        XCTAssertEqual(pages[0].size.height / pages[0].size.width, 200, accuracy: 0.5, "shape is kept")
    }

    func testAnExactA4MultipleAddsNoEmptyPage() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let side: CGFloat = 100
        let twoPages = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side * 2.squareRoot() * 2), format: format
        ).image { _ in }
        let data = try XCTUnwrap(PageExporter.data(from: twoPages, format: .pdf, pdfLayout: .a4Pages))
        XCTAssertEqual(try pdfPages(data).count, 2)
    }

    func testFileNamesFollowTheTitleAndFormat() {
        XCTAssertEqual(PageExporter.fileName(title: "Lunch by the river", format: .png), "Lunch-by-the-river.png")
        XCTAssertEqual(PageExporter.fileName(title: "Lunch by the river", format: .jpg), "Lunch-by-the-river.jpg")
        XCTAssertEqual(PageExporter.fileName(title: "  ", format: .pdf), "MiraNote-page.pdf")
    }

    // Quality (screen 37): Standard 2x and High 3x at any length; Original
    // renders 4x, but a page too long for the pixel budget comes down
    // toward High -- never below it.
    func testQualityScales() {
        let short = CGSize(width: 360, height: 620)
        XCTAssertEqual(ExportQuality.standard.scale(for: short), 2)
        XCTAssertEqual(ExportQuality.high.scale(for: short), 3)
        XCTAssertEqual(ExportQuality.original.scale(for: short), 4)
        XCTAssertEqual(ExportQuality.high.scale(for: CGSize(width: 360, height: 40_000)), 3)
    }

    func testOriginalStaysInsideItsPixelBudget() {
        let long = CGSize(width: 360, height: 5_000)
        let scale = ExportQuality.original.scale(for: long)
        XCTAssertGreaterThan(scale, 3)
        XCTAssertLessThan(scale, 4)
        XCTAssertEqual(long.width * long.height * scale * scale, ExportQuality.originalPixelBudget,
                       accuracy: ExportQuality.originalPixelBudget * 0.001)
    }

    func testOriginalNeverDropsBelowHigh() {
        XCTAssertEqual(ExportQuality.original.scale(for: CGSize(width: 360, height: 40_000)), 3)
    }

    func testOnlyImageFormatsCanGoToPhotos() {
        XCTAssertTrue(ExportFormat.png.savesToPhotos)
        XCTAssertTrue(ExportFormat.jpg.savesToPhotos)
        XCTAssertFalse(ExportFormat.pdf.savesToPhotos)
    }
}

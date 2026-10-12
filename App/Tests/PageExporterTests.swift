import CoreGraphics
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

    func testFileNamesFollowTheTitleAndFormat() {
        XCTAssertEqual(PageExporter.fileName(title: "Lunch by the river", format: .png), "Lunch-by-the-river.png")
        XCTAssertEqual(PageExporter.fileName(title: "Lunch by the river", format: .jpg), "Lunch-by-the-river.jpg")
        XCTAssertEqual(PageExporter.fileName(title: "  ", format: .pdf), "MiraNote-page.pdf")
    }

    func testOnlyImageFormatsCanGoToPhotos() {
        XCTAssertTrue(ExportFormat.png.savesToPhotos)
        XCTAssertTrue(ExportFormat.jpg.savesToPhotos)
        XCTAssertFalse(ExportFormat.pdf.savesToPhotos)
    }
}

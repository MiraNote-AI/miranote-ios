import MiraNoteKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One choice row of the export sheet's Advanced fold.
protocol ExportOption: CaseIterable, Identifiable, Hashable where ID == String {
    var label: String { get }
}

/// The file formats a page exports to (handoff screen 37).
enum ExportFormat: String, ExportOption {
    case png, jpg, pdf

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .pdf: return .pdf
        }
    }

    /// Photos takes images, not documents.
    var savesToPhotos: Bool { self != .pdf }
}

/// Render density: the page is laid out in points and drawn at this scale.
enum ExportQuality: String, ExportOption {
    case standard, high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scale: CGFloat { self == .standard ? 2 : 3 }
}

/// How a PDF holds the long page: as one tall page, or cut into A4-shaped
/// pages for printing -- the optional format crop. The canvas itself is
/// always one long page.
enum PDFLayout: String, ExportOption {
    case longPage, a4Pages

    var id: String { rawValue }
    var label: String { self == .longPage ? "One long page" : "A4 pages" }
}

enum PageExporter {
    /// The long page as an image: sound markers hidden (a speaker nobody can
    /// tap reads as broken -- v2.1).
    @MainActor static func render(_ memory: Memory, quality: ExportQuality) -> UIImage? {
        let renderer = ImageRenderer(
            content: StaticPageView(memory: memory, designWidth: MiraNoteConfig.pageWidth, showsSound: false)
        )
        renderer.scale = quality.scale
        return renderer.uiImage
    }

    static func data(from image: UIImage, format: ExportFormat, pdfLayout: PDFLayout = .longPage) -> Data? {
        switch format {
        case .png: return image.pngData()
        case .jpg: return image.jpegData(compressionQuality: 0.9)
        case .pdf: return pdf(from: image, layout: pdfLayout)
        }
    }

    /// PDF pages are sized in points, so the drawn image keeps its full pixel
    /// density. A4 pages share the long page's width; the last page is
    /// partly empty rather than stretched.
    private static func pdf(from image: UIImage, layout: PDFLayout) -> Data {
        let size = image.size
        let pageHeight = layout == .longPage ? size.height : size.width * 2.squareRoot()
        let pageCount = max(1, Int((size.height / pageHeight).rounded(.up)))
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: pageHeight)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for index in 0..<pageCount {
                context.beginPage()
                image.draw(at: CGPoint(x: 0, y: -CGFloat(index) * pageHeight))
            }
        }
    }

    /// "Lunch by the river" -> "Lunch-by-the-river.png"; an untitled page
    /// gets a generic name instead of an empty one.
    static func fileName(title: String, format: ExportFormat) -> String {
        let slug = title
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { partial, char in
                if char != "-" || partial.last != "-" { partial.append(char) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(slug.isEmpty ? "MiraNote-page" : slug).\(format.rawValue)"
    }
}

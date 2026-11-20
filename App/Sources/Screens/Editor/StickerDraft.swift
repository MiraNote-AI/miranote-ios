import CoreImage
import UIKit

/// The sticker style tiles of screens 32-33.
enum StickerLook: String, CaseIterable, Identifiable {
    case outline, cutout, bw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .outline: return "Outline"
        case .cutout: return "Cutout"
        case .bw: return "B&W"
        }
    }

    private static let context = CIContext()

    /// Black and white that keeps the sticker's transparent edges.
    static func monochrome(_ data: Data) -> Data? {
        guard let input = CIImage(data: data) else { return nil }
        let output = PhotoFilter.bw.apply(to: input)
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}

/// One look of a made sticker; nil style is as it came from the studio.
struct StickerVariant {
    let data: Data
    let style: StickerLook?
    var favorite = false
}

/// A made sticker and its style history: the floating Undo and Redo step
/// through it, a new style drops what was undone.
struct StickerDraft: Identifiable {
    let id = UUID()
    let prompt: String
    private(set) var variants: [StickerVariant]
    var index: Int

    init(prompt: String, data: Data, style: StickerLook? = nil) {
        self.prompt = prompt
        variants = [StickerVariant(data: data, style: style)]
        index = 0
    }

    var current: StickerVariant { variants[index] }
    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index < variants.count - 1 }

    mutating func push(_ variant: StickerVariant) {
        variants.removeSubrange((index + 1)...)
        variants.append(variant)
        index = variants.count - 1
    }

    mutating func markFavorite() {
        variants[index].favorite = true
    }
}

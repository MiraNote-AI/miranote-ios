import Foundation
import Observation

/// Style Transfer sheet (sketch 2.2, split out per D2).
/// Image count is capped by D1 (MiraNoteConfig.maxImagesPerAdd).
@MainActor
@Observable
public final class StyleTransferViewModel {
    public private(set) var images: [ImageRef] = []
    public var selectedStyle: StickerStyle? {
        didSet { if oldValue != selectedStyle { results = nil } }
    }
    public private(set) var results: [ImageRef]?
    public private(set) var isGenerating = false
    public private(set) var lastError: String?

    private let service: StyleTransferService

    public init(service: StyleTransferService = MockStyleTransferService()) {
        self.service = service
    }

    public var remainingSlots: Int {
        max(0, MiraNoteConfig.maxImagesPerAdd - images.count)
    }

    public var canAddMore: Bool { remainingSlots > 0 }

    public var canGenerate: Bool {
        !images.isEmpty && selectedStyle != nil && !isGenerating
    }

    /// D1: silently truncates anything beyond the remaining slots; the view
    /// also passes the cap to the picker so this is a second line of defense.
    /// Changing the input set invalidates any previous results.
    public func addImages(_ newImages: [ImageRef]) {
        guard !newImages.isEmpty else { return }
        images.append(contentsOf: newImages.prefix(remainingSlots))
        results = nil
    }

    public func removeImage(id: ImageRef.ID) {
        images.removeAll { $0.id == id }
        results = nil
    }

    public func generate() async {
        guard canGenerate, let style = selectedStyle else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            results = try await service.apply(style: style, to: images)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

import MiraNoteKit
import UIKit

/// The ending's button: the memory's photos saved the way the Image tool
/// saves picks (`PhotoPlacer`: downscaled to 1440, then `ImageFileStore`),
/// laid out as a canvas draft by `TriggerDraftBuilder` (handoff 7.8).
enum TriggerDraftMaker {
    static func make(_ memory: TriggerMemory, photoIds: [String: String],
                     photos: TriggerPhotoProviding, store: ImageFileStore = ImageFileStore()) async -> TriggerDraft {
        var files: [String: String] = [:]
        for photo in memory.storyPhotos {
            guard let id = photoIds[photo.id],
                  let image = await photos.image(for: id, maxPixel: 2000, allowNetwork: true),
                  let data = image.downscaled(),
                  let file = try? store.save(data, id: UUID()) else { continue }
            files[photo.id] = file
        }
        return TriggerDraftBuilder.draft(memory: memory, imageFiles: files, detailFont: TriggerEndingText.detailFont)
    }

    /// A draft `make` made that is not kept (left untouched, or never
    /// opened): its photo copies are deleted. Pass the page as it was
    /// made, so only those files go.
    static func discard(_ page: Memory, store: ImageFileStore = ImageFileStore()) {
        for item in page.items {
            if case .image(let ref) = item.content { store.delete(fileName: ref.fileName) }
        }
    }
}

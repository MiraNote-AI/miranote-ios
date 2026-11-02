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
}

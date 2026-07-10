import Foundation
import MiraNoteKit

extension StickerFavoritesStore {
    /// UI tests get a per-process scratch file so mock stickers from one
    /// run never leak into the next run's MY STICKERS row; everyone else
    /// gets the real persisted favorites.
    static func forCurrentProcess() -> StickerFavoritesStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("uitest-stickers-\(ProcessInfo.processInfo.processIdentifier).json")
            return StickerFavoritesStore(url: url)
        }
        #endif
        return StickerFavoritesStore()
    }
}

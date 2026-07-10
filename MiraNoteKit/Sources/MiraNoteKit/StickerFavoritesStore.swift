import Foundation

/// "My stickers": every generated or cut-out sticker lands here for reuse
/// (v2.1 -- the favorites row doubles as the sticker feature's shop window).
/// Newest first, capped, persisted as JSON next to the collections file.
public struct StickerFavoritesStore: Sendable {
    private let url: URL
    private let cap: Int

    public init(url: URL? = nil, cap: Int = 12) {
        if let url {
            self.url = url
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.url = documents.appendingPathComponent("MiraNoteStickers.json")
        }
        self.cap = cap
    }

    public func all() -> [GeneratedSticker] {
        guard let data = try? Data(contentsOf: url),
              let stickers = try? JSONDecoder().decode([GeneratedSticker].self, from: data) else {
            return []
        }
        return stickers
    }

    /// One-shot hygiene at panel open: keep only stickers whose image
    /// still decodes to something visible (missing files and degenerate
    /// mock-era thumbnails read as blank squares), rewrite the file when
    /// anything was dropped, and return the survivors. `imageSide`
    /// reports the shorter decoded side for a stored file name.
    public func pruned(
        imageSide: (String) -> CGFloat?,
        minSide: CGFloat = 24
    ) -> [GeneratedSticker] {
        let stickers = all()
        let kept = stickers.filter {
            guard let side = imageSide($0.fileName) else { return false }
            return side >= minSide
        }
        if kept.count != stickers.count, let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: url)
        }
        return kept
    }

    /// Adds to the front, dropping duplicates by id and anything past the cap.
    public func add(_ sticker: GeneratedSticker) {
        var stickers = all().filter { $0.id != sticker.id }
        stickers.insert(sticker, at: 0)
        if stickers.count > cap {
            stickers.removeLast(stickers.count - cap)
        }
        if let data = try? JSONEncoder().encode(stickers) {
            try? data.write(to: url)
        }
    }
}

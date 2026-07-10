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

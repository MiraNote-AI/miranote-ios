import CoreGraphics
import Foundation

/// A group of memories shown as one "book" card on the Home screen.
public struct MemoryCollection: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var memories: [Memory]

    public init(id: UUID = UUID(), title: String, memories: [Memory] = []) {
        self.id = id
        self.title = title
        self.memories = memories
    }
}

/// One canvas worth of content, started from "Start a memory".
public struct Memory: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var body: String
    public var createdAt: Date
    /// The day the memory is ABOUT (v2.1): grouping and retrieval sort by
    /// this, not by when the file was made. Defaults to creation time and
    /// stays user-editable.
    public var memoryDate: Date
    public var savedAt: Date?
    public var items: [CanvasItem]

    public init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        createdAt: Date = .now,
        memoryDate: Date? = nil,
        savedAt: Date? = nil,
        items: [CanvasItem] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.memoryDate = memoryDate ?? createdAt
        self.savedAt = savedAt
        self.items = items
    }
}

extension Memory: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Persisted form keeps identity, title, timestamps, and (since Flow v2) the
/// full canvas item list. Older saves without `items` decode to empty.
extension Memory: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, body, createdAt, memoryDate, savedAt, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let created = try container.decode(Date.self, forKey: .createdAt)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            body: try container.decodeIfPresent(String.self, forKey: .body) ?? "",
            createdAt: created,
            memoryDate: try container.decodeIfPresent(Date.self, forKey: .memoryDate) ?? created,
            savedAt: try container.decodeIfPresent(Date.self, forKey: .savedAt),
            items: try container.decodeIfPresent([CanvasItem].self, forKey: .items) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(memoryDate, forKey: .memoryDate)
        try container.encodeIfPresent(savedAt, forKey: .savedAt)
        try container.encode(items, forKey: .items)
    }
}

/// A styled block of text placed on the canvas.
public struct TextBlock: Equatable, Sendable, Codable {
    public var text: String
    public var pointSize: CGFloat
    /// A named palette color resolved by the app layer (e.g. "ink").
    public var colorName: String

    public init(text: String, pointSize: CGFloat = 17, colorName: String = "ink") {
        self.text = text
        self.pointSize = pointSize
        self.colorName = colorName
    }
}

/// A recorded sound attached to the page: a small marker plus a note label
/// (v2.1: tap the icon to play, tap the pill to edit the note).
public struct SoundClip: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var duration: TimeInterval
    public var note: String
    /// File name inside the sound store; empty when no audio was kept.
    public var fileName: String

    public init(id: UUID = UUID(), duration: TimeInterval, note: String = "", fileName: String = "") {
        self.id = id
        self.duration = duration
        self.note = note
        self.fileName = fileName
    }
}

/// Anything placed on the canvas. Geometry is center-based: `position` is the
/// element's center in canvas coordinates, `rotation` is in degrees, and `z`
/// orders stacking (higher draws on top).
public struct CanvasItem: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(TextBlock)
        case image(ImageRef)
        case sticker(GeneratedSticker)
        case sound(SoundClip)
    }

    public let id: UUID
    public var content: Content
    public var position: CGPoint
    public var size: CGSize
    public var rotation: Double
    public var zIndex: Int

    public init(
        id: UUID = UUID(),
        content: Content,
        position: CGPoint,
        size: CGSize = CGSize(width: 160, height: 120),
        rotation: Double = 0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.size = size
        self.rotation = rotation
        self.zIndex = zIndex
    }
}

extension CanvasItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, content, position, size, rotation, zIndex
    }
}

extension CanvasItem.Content: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, text, image, sticker, sound
    }

    private enum Kind: String, Codable {
        case text, image, sticker, sound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(TextBlock.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ImageRef.self, forKey: .image))
        case .sticker:
            self = .sticker(try container.decode(GeneratedSticker.self, forKey: .sticker))
        case .sound:
            self = .sound(try container.decode(SoundClip.self, forKey: .sound))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let block):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(block, forKey: .text)
        case .image(let ref):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(ref, forKey: .image)
        case .sticker(let sticker):
            try container.encode(Kind.sticker, forKey: .kind)
            try container.encode(sticker, forKey: .sticker)
        case .sound(let clip):
            try container.encode(Kind.sound, forKey: .kind)
            try container.encode(clip, forKey: .sound)
        }
    }
}

/// Reference to a picked or generated image. Pixels live in the
/// ImageFileStore under `fileName`; an empty file name renders as the warm
/// gradient placeholder. `filterName` / `frameName` are the photo-edit
/// treatments (resolved by the app layer; empty = none).
public struct ImageRef: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    public var fileName: String
    public var filterName: String
    public var frameName: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        fileName: String = "",
        filterName: String = "",
        frameName: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.filterName = filterName
        self.frameName = frameName
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, fileName, filterName, frameName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            fileName: try container.decodeIfPresent(String.self, forKey: .fileName) ?? "",
            filterName: try container.decodeIfPresent(String.self, forKey: .filterName) ?? "",
            frameName: try container.decodeIfPresent(String.self, forKey: .frameName) ?? ""
        )
    }
}

/// Output of the AI sticker generator. Real artwork lives in the
/// ImageFileStore under `fileName`; when empty, `symbolName` renders a
/// placeholder glyph.
public struct GeneratedSticker: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var prompt: String
    public var symbolName: String
    public var fileName: String

    public init(id: UUID = UUID(), prompt: String, symbolName: String, fileName: String = "") {
        self.id = id
        self.prompt = prompt
        self.symbolName = symbolName
        self.fileName = fileName
    }

    private enum CodingKeys: String, CodingKey {
        case id, prompt, symbolName, fileName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            prompt: try container.decode(String.self, forKey: .prompt),
            symbolName: try container.decode(String.self, forKey: .symbolName),
            fileName: try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        )
    }
}

/// D2: style transfer is its own entry with these three styles (sketch 2.2).
public enum StickerStyle: String, CaseIterable, Identifiable, Sendable {
    case cartoon
    case vintage
    case handDrawn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cartoon: return "Cartoon"
        case .vintage: return "Vintage"
        case .handDrawn: return "Hand-drawn"
        }
    }
}

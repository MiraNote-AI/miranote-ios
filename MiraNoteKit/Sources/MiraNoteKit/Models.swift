import CoreGraphics
import Foundation

/// A group of memories shown as one "book" card on the Home screen.
public struct MemoryCollection: Identifiable, Equatable, Sendable {
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
    public var createdAt: Date
    public var savedAt: Date?
    public var items: [CanvasItem]

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        savedAt: Date? = nil,
        items: [CanvasItem] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.savedAt = savedAt
        self.items = items
    }
}

extension Memory: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Anything placed on the canvas.
public struct CanvasItem: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        case image(ImageRef)
        case sticker(GeneratedSticker)
    }

    public let id: UUID
    public var content: Content
    public var position: CGPoint

    public init(id: UUID = UUID(), content: Content, position: CGPoint) {
        self.id = id
        self.content = content
        self.position = position
    }
}

/// Reference to a user-picked image. v1 keeps display names only;
/// pixel data handling and persistence are later tasks (see spec).
public struct ImageRef: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String

    public init(id: UUID = UUID(), displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// Output of the AI sticker generator (mocked in v1).
public struct GeneratedSticker: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var prompt: String
    public var symbolName: String

    public init(id: UUID = UUID(), prompt: String, symbolName: String) {
        self.id = id
        self.prompt = prompt
        self.symbolName = symbolName
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

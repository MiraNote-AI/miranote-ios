import Foundation

// Service protocols mirror the miranote-api POC surface so swapping the
// mocks for HTTP clients later does not touch view models (spec Q3).

/// Text transforms offered by the Text input sheet (sketch 2.1).
/// Backend mapping: text-clean-expand POC (:8001).
public enum TextTransformMode: String, CaseIterable, Identifiable, Sendable {
    case clean
    case expand
    case polish

    public var id: String { rawValue }

    public var displayName: String { rawValue.capitalized }
}

public protocol TextTransformService: Sendable {
    func transform(_ text: String, mode: TextTransformMode) async throws -> String
}

/// Voice dictation entry (sketch 2.1 "voice", Home pill glyph).
/// Backend mapping: voice-to-text POC (:8000).
public protocol VoiceTranscriptionService: Sendable {
    func transcribe() async throws -> String
}

/// AI sticker generation (sketch 2.2, D2 entry one).
public protocol StickerGenerationService: Sendable {
    func generateSticker(prompt: String) async throws -> GeneratedSticker
}

/// Style transfer (sketch 2.2, D2 entry two).
public protocol StyleTransferService: Sendable {
    func apply(style: StickerStyle, to images: [ImageRef]) async throws -> [ImageRef]
}

// MARK: - Mocks (v1 ships these; see spec non-goals)

public struct MockTextTransformService: TextTransformService {
    public init() {}

    public func transform(_ text: String, mode: TextTransformMode) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .clean:
            return trimmed
        case .expand:
            return trimmed + "\n\n(expanded draft -- mock)"
        case .polish:
            return "(polished -- mock) " + trimmed
        }
    }
}

public struct MockVoiceTranscriptionService: VoiceTranscriptionService {
    public init() {}

    public func transcribe() async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return "Transcribed voice note (mock)"
    }
}

public struct MockStickerGenerationService: StickerGenerationService {
    public init() {}

    public func generateSticker(prompt: String) async throws -> GeneratedSticker {
        try await Task.sleep(for: .milliseconds(300))
        return GeneratedSticker(prompt: prompt, symbolName: "sparkles")
    }
}

public struct MockStyleTransferService: StyleTransferService {
    public init() {}

    public func apply(style: StickerStyle, to images: [ImageRef]) async throws -> [ImageRef] {
        try await Task.sleep(for: .milliseconds(300))
        return images.map { image in
            ImageRef(displayName: image.displayName + " (" + style.displayName + ")")
        }
    }
}

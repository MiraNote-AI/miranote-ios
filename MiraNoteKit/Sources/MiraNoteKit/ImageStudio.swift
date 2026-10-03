import Foundation

/// What the image-generation POC can produce from a prompt.
public enum GeneratedImageKind: String, Sendable {
    /// Transparent-background subject art (the POC removes the background).
    case sticker
    /// Full-bleed page backdrop art (the api's background command).
    case background
    /// Standalone subject illustration (the api's art command).
    case art
}

/// Generated stickers, and which of them still have their background.
///
/// Cutting a sticker out can fail on its own merits -- a generated image with
/// no salient subject gives Vision nothing to lift -- and that is not a reason
/// to throw the picture away. Callers show every image and mention the ones
/// that came back whole.
public struct StickerGeneration: Sendable, Equatable {
    public let images: [Data]
    /// Positions in `images` whose background could not be removed.
    public let unmatted: [Int]

    public init(images: [Data], unmatted: [Int] = []) {
        self.images = images
        self.unmatted = unmatted
    }

    public var allMatted: Bool { unmatted.isEmpty }
}

/// The image pipelines behind the Image panel and photo editing. Backend
/// mapping: image-generation POC (/generate, /cutout, /stylize, /border).
public protocol ImageStudioService: Sendable {
    /// Text-to-image; returns one or more encoded images.
    func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data]
    /// Background removal; `target` optionally names the subject to keep.
    func cutout(image: Data, target: String?) async throws -> Data
    /// Instruction-guided image-to-image edit.
    func stylize(image: Data, instruction: String) async throws -> Data
    /// The white sticker outline around a cutout.
    func outline(image: Data) async throws -> Data
    /// One warm sentence about the photo (vision) -- page context for chat.
    func describe(image: Data) async throws -> String
    /// Stickers plus per-image matte results, for callers that offer a choice.
    func generateStickers(prompt: String) async throws -> StickerGeneration
}

public extension ImageStudioService {
    /// Default for any service that mattes server-side: what comes back is
    /// already cut out, or the call threw.
    func generateStickers(prompt: String) async throws -> StickerGeneration {
        StickerGeneration(images: try await generate(kind: .sticker, prompt: prompt))
    }
}

/// Deterministic offline double: instant tiny PNGs, no network.
public struct MockImageStudioService: ImageStudioService {
    /// A valid 8x8 opaque tan PNG -- visible in snapshots, and opaque so
    /// the accessibility tree never prunes a fully transparent element.
    public static let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGM4uWkqVsQwtCQAoMWEAbpmkkwAAAAASUVORK5CYII="
    )!

    public init() {}

    public func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        try await Task.sleep(for: .milliseconds(200))
        return [Self.tinyPNG, Self.tinyPNG]
    }

    public func cutout(image: Data, target: String?) async throws -> Data {
        try await Task.sleep(for: .milliseconds(200))
        return Self.tinyPNG
    }

    public func stylize(image: Data, instruction: String) async throws -> Data {
        try await Task.sleep(for: .milliseconds(200))
        return Self.tinyPNG
    }

    public func outline(image: Data) async throws -> Data {
        try await Task.sleep(for: .milliseconds(200))
        return Self.tinyPNG
    }

    public func describe(image: Data) async throws -> String {
        try await Task.sleep(for: .milliseconds(80))
        return "a warm little photo"
    }
}

/// Live client for the image-generation POC.
///
/// Given a `matte`, the two pipelines that are pure background removal stop
/// going to the server at all: a cutout with no target, and the sticker pass
/// after `/generate` has drawn the image. Both are Apple Vision either way --
/// this only decides whose silicon runs it. Doing it here keeps every caller
/// and the whole `ImageStudioService` surface unchanged.
///
/// It also takes both off the tunnel, where they were the two calls closest to
/// Cloudflare's 125s ceiling, and leaves them working with the backend down.
///
/// A cutout *with* a target stays remote: Vision is about 3% of that pipeline
/// and GroundingDINO and SAM, which are the rest of it, are far too large to
/// ship in an app.
public struct LiveImageStudioService: ImageStudioService {
    private let baseURL: URL
    private let client: HTTPClient
    private let matte: ForegroundMatte?

    public init(
        baseURL: URL = MiraNoteConfig.Backend.imageBaseURL,
        client: HTTPClient = HTTPClient(),
        matte: ForegroundMatte? = nil
    ) {
        self.baseURL = baseURL
        self.client = client
        self.matte = matte
    }

    public func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        guard kind == .sticker, matte != nil else {
            return try await remoteGenerate(kind: kind, prompt: prompt, matte: nil)
        }
        // Drop the per-image matte results: a caller on this path asked for
        // pictures, not a report. generateStickers is where they survive.
        return try await generateStickers(prompt: prompt).images
    }

    public func generateStickers(prompt: String) async throws -> StickerGeneration {
        guard let matte else {
            return StickerGeneration(images: try await remoteGenerate(
                kind: .sticker, prompt: prompt, matte: nil))
        }
        let raw = try await remoteGenerate(kind: .sticker, prompt: prompt, matte: "none")

        var images: [Data] = []
        var unmatted: [Int] = []
        for (index, image) in raw.enumerated() {
            do {
                images.append(try await Self.lift(image, with: matte))
            } catch {
                // The picture is already here and already paid for. Keep it,
                // background and all, and let the caller say so.
                images.append(image)
                unmatted.append(index)
            }
        }
        return StickerGeneration(images: images, unmatted: unmatted)
    }

    /// `matte` is the server's background remover: "none" tells it to skip the
    /// step because this device does it. The field is ignored by any build of
    /// the service that predates it, which would then matte server-side and
    /// leave the local pass with an already-transparent image to fail on -- so
    /// this needs the api-side change deployed first.
    private func remoteGenerate(
        kind: GeneratedImageKind, prompt: String, matte: String?
    ) async throws -> [Data] {
        struct Request: Encodable {
            let command: String
            let prompt: String
            let expand: Bool
            let matte: String?
        }
        struct Response: Decodable {
            let images: [String]
        }
        // Generation legitimately runs past URLSession's 60s default (two
        // images plus background removal), but it must still finish inside
        // Cloudflare's 125s proxy read timeout, which cannot be raised below
        // the Enterprise plan. Measured worst case on the host Mac is 36.8s
        // for a cutout, so 110s is a ceiling rather than the normal path.
        let response: Response = try await client.postJSON(
            to: baseURL.appendingPathComponent("generate"),
            body: Request(command: kind.rawValue, prompt: prompt,
                          expand: true, matte: matte),
            timeout: 110
        )
        let decoded = response.images.compactMap { Data(base64Encoded: $0) }
        guard !decoded.isEmpty else { throw BackendError.decoding }
        return decoded
    }

    public func cutout(image: Data, target: String?) async throws -> Data {
        var query: [URLQueryItem] = []
        if let target, !target.isEmpty {
            query.append(URLQueryItem(name: "prompt", value: target))
        } else if let matte {
            return try await Self.lift(image, with: matte)
        }
        return try await uploadForImage(path: "cutout", image: image, query: query)
    }

    /// Vision off the calling executor: `perform` is synchronous and takes
    /// long enough to be worth not doing on whatever thread asked.
    private static func lift(_ image: Data, with matte: ForegroundMatte) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try matte.removeBackground(image)
        }.value
    }

    public func stylize(image: Data, instruction: String) async throws -> Data {
        try await uploadForImage(
            path: "stylize",
            image: image,
            query: [URLQueryItem(name: "prompt", value: instruction)]
        )
    }

    public func outline(image: Data) async throws -> Data {
        try await uploadForImage(
            path: "border",
            image: image,
            query: [URLQueryItem(name: "mode", value: "outline")]
        )
    }

    public func describe(image: Data) async throws -> String {
        struct Response: Decodable {
            let description: String
        }
        let data = try await upload(path: "describe", image: image, query: [])
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.description.isEmpty else {
            throw BackendError.decoding
        }
        return response.description
    }

    /// POST one image file (multipart) with query params; decode `{image}`.
    private func uploadForImage(path: String, image: Data, query: [URLQueryItem]) async throws -> Data {
        struct Response: Decodable {
            let image: String
        }
        let data = try await upload(path: path, image: image, query: query)
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let decoded = Data(base64Encoded: response.image) else {
            throw BackendError.decoding
        }
        return decoded
    }

    /// POST one image file (multipart); return the raw response body.
    private func upload(path: String, image: Data, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            // Keep Foundation's escaping (it correctly encodes separators
            // like & and = inside values), then fix its one gap: a bare '+'
            // that the server would decode as a space.
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        let boundary = "MiraNoteBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: components.url!)
        // Same ceiling as /generate: below Cloudflare's 125s edge timeout.
        request.timeoutInterval = 110
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = LiveVoiceTranscriptionService.multipartBody(
            boundary: boundary,
            fieldName: "file",
            filename: "image.png",
            mimeType: "image/png",
            fileData: image
        )
        return try await client.send(request)
    }
}

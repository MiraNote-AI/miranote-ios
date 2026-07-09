import Foundation

/// What the image-generation POC can produce from a prompt.
public enum GeneratedImageKind: String, Sendable {
    /// Transparent-background subject art (the POC removes the background).
    case sticker
    /// Full-bleed art -- also the closest match for the photo / illustration
    /// / watercolor generate styles until a dedicated command exists.
    case background
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
}

/// Live client for the image-generation POC.
public struct LiveImageStudioService: ImageStudioService {
    private let baseURL: URL
    private let client: HTTPClient

    public init(
        baseURL: URL = MiraNoteConfig.Backend.imageBaseURL,
        client: HTTPClient = HTTPClient()
    ) {
        self.baseURL = baseURL
        self.client = client
    }

    public func generate(kind: GeneratedImageKind, prompt: String) async throws -> [Data] {
        struct Request: Encodable {
            let command: String
            let prompt: String
            let expand: Bool
        }
        struct Response: Decodable {
            let images: [String]
        }
        // Generation legitimately runs past URLSession's 60s default
        // (two images plus background removal); give it real room.
        let response: Response = try await client.postJSON(
            to: baseURL.appendingPathComponent("generate"),
            body: Request(command: kind.rawValue, prompt: prompt, expand: true),
            timeout: 180
        )
        let decoded = response.images.compactMap { Data(base64Encoded: $0) }
        guard !decoded.isEmpty else { throw BackendError.decoding }
        return decoded
    }

    public func cutout(image: Data, target: String?) async throws -> Data {
        var query: [URLQueryItem] = []
        if let target, !target.isEmpty {
            query.append(URLQueryItem(name: "prompt", value: target))
        }
        return try await uploadForImage(path: "cutout", image: image, query: query)
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

    /// POST one image file (multipart) with query params; decode `{image}`.
    private func uploadForImage(path: String, image: Data, query: [URLQueryItem]) async throws -> Data {
        struct Response: Decodable {
            let image: String
        }
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
        request.timeoutInterval = 180
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = LiveVoiceTranscriptionService.multipartBody(
            boundary: boundary,
            fieldName: "file",
            filename: "image.png",
            mimeType: "image/png",
            fileData: image
        )
        let data = try await client.send(request)
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let decoded = Data(base64Encoded: response.image) else {
            throw BackendError.decoding
        }
        return decoded
    }
}

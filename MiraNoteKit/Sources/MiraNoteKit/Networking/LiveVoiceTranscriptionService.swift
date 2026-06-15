import Foundation

/// Live `VoiceTranscriptionService`: uploads recorded audio to the voice-to-text
/// POC and returns the transcript. Query params per spec D8: correct=true,
/// with_emotion=false, lang defaults to "en" (English demo default, Q7).
public struct LiveVoiceTranscriptionService: VoiceTranscriptionService {
    private let baseURL: URL
    private let client: HTTPClient
    private let language: String

    public init(
        baseURL: URL = MiraNoteConfig.Backend.voiceBaseURL,
        client: HTTPClient = HTTPClient(),
        language: String = "en"
    ) {
        self.baseURL = baseURL
        self.client = client
        self.language = language
    }

    public func transcribe(audio: Data, filename: String) async throws -> String {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("transcribe"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "correct", value: "true"),
            URLQueryItem(name: "with_emotion", value: "false"),
            URLQueryItem(name: "lang", value: language),
        ]

        let boundary = "MiraNoteBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fieldName: "file",
            filename: filename,
            mimeType: "audio/m4a",
            fileData: audio
        )

        let data = try await client.send(request)
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            return response.correctedText ?? response.rawText
        } catch {
            throw BackendError.decoding
        }
    }

    /// Build a single-file `multipart/form-data` body.
    static func multipartBody(
        boundary: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// The POC returns several fields; v1 only needs the text (spec D8 skips
    /// emotion and per-segment data).
    private struct Response: Decodable {
        let rawText: String
        let correctedText: String?

        enum CodingKeys: String, CodingKey {
            case rawText = "raw_text"
            case correctedText = "corrected_text"
        }
    }
}

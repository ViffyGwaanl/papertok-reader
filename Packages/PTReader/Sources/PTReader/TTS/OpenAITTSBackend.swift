import Foundation
import PTCore

/// TTS backend backed by OpenAI's `/v1/audio/speech` endpoint.
///
/// The API responds with the full audio blob (MP3 by default). We return the
/// blob as a one-shot `AsyncThrowingStream` so the orchestrator can treat
/// cloud backends uniformly.
public final class OpenAITTSBackend: TTSBackend {
    public let id = "openai"
    public let displayName = "OpenAI TTS"

    public enum Model: String, Sendable {
        case standard = "tts-1"
        case hd = "tts-1-hd"
    }

    private let model: Model
    private let session: URLSession
    private let endpoint: URL

    // OpenAI's catalogue is small and fixed — hardcode rather than hitting a
    // list endpoint that doesn't exist.
    private static let fixedVoices: [TTSVoice] = [
        TTSVoice(id: "alloy", name: "Alloy", language: "en-US", gender: "neutral"),
        TTSVoice(id: "echo", name: "Echo", language: "en-US", gender: "male"),
        TTSVoice(id: "fable", name: "Fable", language: "en-GB", gender: "neutral"),
        TTSVoice(id: "onyx", name: "Onyx", language: "en-US", gender: "male"),
        TTSVoice(id: "nova", name: "Nova", language: "en-US", gender: "female"),
        TTSVoice(id: "shimmer", name: "Shimmer", language: "en-US", gender: "female"),
    ]

    public init(
        model: Model = .standard,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/speech")!
    ) {
        self.model = model
        self.session = session
        self.endpoint = endpoint
    }

    public func availableVoices() async throws -> [TTSVoice] {
        Self.fixedVoices
    }

    public func synthesize(
        text: String,
        voice: TTSVoice,
        rate: Double
    ) async throws -> TTSAudioStream {
        guard !text.isEmpty else { throw TTSBackendError.emptyText }
        let apiKey = try Self.loadAPIKey()

        struct Body: Encodable {
            let model: String
            let input: String
            let voice: String
            let response_format: String
            let speed: Double
        }

        // OpenAI accepts speed in the 0.25...4.0 range — our 0.5...2.0 fits.
        let body = Body(
            model: model.rawValue,
            input: text,
            voice: voice.id,
            response_format: "mp3",
            speed: max(0.25, min(4.0, rate))
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TTSBackendError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TTSBackendError.invalidResponse
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(data)
            continuation.finish()
        }
        return .streaming(stream)
    }

    /// Prefer a dedicated TTS key, fall back to the shared chat key.
    static func loadAPIKey() throws -> String {
        if let key = (try? KeychainService.load(key: "openai_tts_api_key")) ?? nil,
           !key.isEmpty {
            return key
        }
        if let key = (try? KeychainService.load(key: "openai_api_key")) ?? nil,
           !key.isEmpty {
            return key
        }
        throw TTSBackendError.missingAPIKey
    }
}

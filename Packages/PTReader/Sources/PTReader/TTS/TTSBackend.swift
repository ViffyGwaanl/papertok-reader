import Foundation

/// A voice that a TTS backend can render speech with.
public struct TTSVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    /// "male", "female", "neutral", or nil if unknown.
    public let gender: String?

    public init(id: String, name: String, language: String, gender: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.gender = gender
    }
}

/// The audio stream produced by a `TTSBackend`.
///
/// - `.synchronous`: the backend drives playback itself (e.g. `AVSpeechSynthesizer`).
///   Callers should not attempt to play any audio data — the backend has already
///   started speaking by the time `synthesize` returns.
/// - `.streaming`: the backend returns audio bytes (typically MP3) that the caller
///   must feed into an audio player such as `AVAudioPlayer`.
public enum TTSAudioStream: Sendable {
    case synchronous
    case streaming(AsyncThrowingStream<Data, Error>)
}

/// Errors that TTS backends can throw.
public enum TTSBackendError: Error, Sendable {
    case missingAPIKey
    case missingConfiguration(String)
    case networkError(Error)
    case invalidResponse
    case emptyText
}

/// A pluggable TTS backend — system (on-device) or cloud.
public protocol TTSBackend: Sendable {
    var id: String { get }
    var displayName: String { get }

    /// List voices supported by this backend. May hit the network.
    func availableVoices() async throws -> [TTSVoice]

    /// Synthesize speech for the given text.
    ///
    /// - Parameters:
    ///   - text: The input text.
    ///   - voice: The voice to use.
    ///   - rate: Playback rate multiplier (1.0 = normal, 0.5 = half, 2.0 = double).
    func synthesize(
        text: String,
        voice: TTSVoice,
        rate: Double
    ) async throws -> TTSAudioStream
}

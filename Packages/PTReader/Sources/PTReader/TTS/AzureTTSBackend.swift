import Foundation
import PTCore

/// TTS backend backed by Azure Cognitive Services Speech.
///
/// Requires two Keychain entries:
/// - `azure_tts_key`: subscription key
/// - `azure_tts_region`: region name (e.g. `eastus`)
public final class AzureTTSBackend: TTSBackend {
    public let id = "azure"
    public let displayName = "Azure Neural TTS"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Voices

    // Curated list — Azure exposes 400+ voices but a focused set is more useful
    // in the picker. Power users can still pass an arbitrary voice id programmatically.
    private static let curatedVoices: [TTSVoice] = [
        // English (US)
        .init(id: "en-US-JennyNeural", name: "Jenny", language: "en-US", gender: "female"),
        .init(id: "en-US-GuyNeural", name: "Guy", language: "en-US", gender: "male"),
        .init(id: "en-US-AriaNeural", name: "Aria", language: "en-US", gender: "female"),
        .init(id: "en-US-DavisNeural", name: "Davis", language: "en-US", gender: "male"),
        .init(id: "en-US-JaneNeural", name: "Jane", language: "en-US", gender: "female"),
        .init(id: "en-US-TonyNeural", name: "Tony", language: "en-US", gender: "male"),
        // English (UK)
        .init(id: "en-GB-SoniaNeural", name: "Sonia", language: "en-GB", gender: "female"),
        .init(id: "en-GB-RyanNeural", name: "Ryan", language: "en-GB", gender: "male"),
        .init(id: "en-GB-LibbyNeural", name: "Libby", language: "en-GB", gender: "female"),
        // Chinese (Mandarin)
        .init(id: "zh-CN-XiaoxiaoNeural", name: "Xiaoxiao", language: "zh-CN", gender: "female"),
        .init(id: "zh-CN-YunxiNeural", name: "Yunxi", language: "zh-CN", gender: "male"),
        .init(id: "zh-CN-YunyangNeural", name: "Yunyang", language: "zh-CN", gender: "male"),
        .init(id: "zh-CN-XiaoyiNeural", name: "Xiaoyi", language: "zh-CN", gender: "female"),
        // Chinese (Taiwan)
        .init(id: "zh-TW-HsiaoChenNeural", name: "HsiaoChen", language: "zh-TW", gender: "female"),
        .init(id: "zh-TW-YunJheNeural", name: "YunJhe", language: "zh-TW", gender: "male"),
        // Japanese
        .init(id: "ja-JP-NanamiNeural", name: "Nanami", language: "ja-JP", gender: "female"),
        .init(id: "ja-JP-KeitaNeural", name: "Keita", language: "ja-JP", gender: "male"),
        // Korean
        .init(id: "ko-KR-SunHiNeural", name: "SunHi", language: "ko-KR", gender: "female"),
        .init(id: "ko-KR-InJoonNeural", name: "InJoon", language: "ko-KR", gender: "male"),
        // French / German / Spanish
        .init(id: "fr-FR-DeniseNeural", name: "Denise", language: "fr-FR", gender: "female"),
        .init(id: "de-DE-KatjaNeural", name: "Katja", language: "de-DE", gender: "female"),
        .init(id: "es-ES-ElviraNeural", name: "Elvira", language: "es-ES", gender: "female"),
    ]

    public func availableVoices() async throws -> [TTSVoice] {
        Self.curatedVoices
    }

    // MARK: - Synthesis

    public func synthesize(
        text: String,
        voice: TTSVoice,
        rate: Double
    ) async throws -> TTSAudioStream {
        guard !text.isEmpty else { throw TTSBackendError.emptyText }

        let (key, region) = try Self.loadCredentials()
        guard let url = URL(
            string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1"
        ) else {
            throw TTSBackendError.invalidResponse
        }

        let ssml = Self.makeSSML(text: text, voice: voice, rate: rate)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "audio-16khz-32kbitrate-mono-mp3",
            forHTTPHeaderField: "X-Microsoft-OutputFormat"
        )
        request.setValue("PaperTokReader", forHTTPHeaderField: "User-Agent")
        request.httpBody = ssml.data(using: .utf8)
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

    // MARK: - SSML

    /// Build an SSML document for a single-voice utterance.
    ///
    /// Azure expresses rate as a percentage offset, e.g. `+0%` for 1.0x,
    /// `-50%` for 0.5x, `+100%` for 2.0x.
    static func makeSSML(text: String, voice: TTSVoice, rate: Double) -> String {
        let percent = Int(((rate - 1.0) * 100).rounded())
        let ratePercent = percent >= 0 ? "+\(percent)%" : "\(percent)%"
        let escaped = Self.xmlEscape(text)
        return """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(voice.language)'>
          <voice name='\(voice.id)'>
            <prosody rate='\(ratePercent)'>\(escaped)</prosody>
          </voice>
        </speak>
        """
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Credentials

    static func loadCredentials() throws -> (key: String, region: String) {
        guard let key = (try? KeychainService.load(key: "azure_tts_key")) ?? nil,
              !key.isEmpty else {
            throw TTSBackendError.missingAPIKey
        }
        guard let region = (try? KeychainService.load(key: "azure_tts_region")) ?? nil,
              !region.isEmpty else {
            throw TTSBackendError.missingConfiguration("azure_tts_region")
        }
        return (key, region)
    }
}

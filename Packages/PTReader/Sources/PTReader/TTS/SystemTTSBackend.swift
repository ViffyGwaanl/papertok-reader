import Foundation

#if canImport(AVFoundation)
import AVFoundation

/// TTS backend that wraps `AVSpeechSynthesizer` for on-device speech.
///
/// Because `AVSpeechSynthesizer` drives audio playback itself, `synthesize`
/// starts speaking immediately and returns `.synchronous`. Callers interact
/// with it via `TTSOrchestrator`, which owns the shared synthesizer.
public final class SystemTTSBackend: NSObject, TTSBackend, @unchecked Sendable {
    public let id = "system"
    public let displayName = "System (On-device)"

    // The synthesizer is injected so that orchestration code (pause/resume/stop)
    // operates on the same instance that produced the utterance.
    private let synthesizer: AVSpeechSynthesizer

    public init(synthesizer: AVSpeechSynthesizer) {
        self.synthesizer = synthesizer
        super.init()
    }

    public func availableVoices() async throws -> [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { v in
            let gender: String?
            switch v.gender {
            case .male: gender = "male"
            case .female: gender = "female"
            case .unspecified: gender = nil
            @unknown default: gender = nil
            }
            return TTSVoice(
                id: v.identifier,
                name: v.name,
                language: v.language,
                gender: gender
            )
        }
    }

    public func synthesize(
        text: String,
        voice: TTSVoice,
        rate: Double
    ) async throws -> TTSAudioStream {
        try await synthesize(text: text, voice: voice, rate: rate, pitch: 1.0, volume: 1.0)
    }

    public func synthesize(
        text: String,
        voice: TTSVoice,
        rate: Double,
        pitch: Double,
        volume: Double
    ) async throws -> TTSAudioStream {
        guard !text.isEmpty else { throw TTSBackendError.emptyText }

        await MainActor.run {
            let utterance = AVSpeechUtterance(string: text)
            // Map the user-facing 0.5...2.0 multiplier onto AVSpeech's internal range.
            utterance.rate = Self.mapRate(rate)
            utterance.pitchMultiplier = Float(max(0.5, min(2.0, pitch)))
            utterance.volume = Float(max(0.0, min(1.0, volume)))

            if let avVoice = AVSpeechSynthesisVoice(identifier: voice.id) {
                utterance.voice = avVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: voice.language)
            }
            synthesizer.speak(utterance)
        }
        return .synchronous
    }

    /// Convert a 0.5...2.0 multiplier to the AVSpeechUtterance rate domain.
    static func mapRate(_ multiplier: Double) -> Float {
        let clamped = max(0.5, min(2.0, multiplier))
        let minR = Double(AVSpeechUtteranceMinimumSpeechRate)
        let defR = Double(AVSpeechUtteranceDefaultSpeechRate)
        let maxR = Double(AVSpeechUtteranceMaximumSpeechRate)
        let mapped: Double
        if clamped < 1.0 {
            // 0.5 -> min, 1.0 -> default
            let t = (clamped - 0.5) / 0.5
            mapped = minR + (defR - minR) * t
        } else {
            // 1.0 -> default, 2.0 -> max
            let t = (clamped - 1.0)
            mapped = defR + (maxR - defR) * t
        }
        return Float(mapped)
    }
}
#endif

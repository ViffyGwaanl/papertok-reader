import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation

public enum TTSState: String, Sendable {
    case stopped
    case speaking
    case paused
}

/// Backward-compatible facade over `TTSOrchestrator`.
///
/// Existing call sites (reader controls, FAB) continue to use this API. New
/// code can reach into `orchestrator` for queue / cloud-backend features.
@Observable
@MainActor
public final class TTSService {
    public let orchestrator: TTSOrchestrator

    public init() {
        self.orchestrator = TTSOrchestrator()
    }

    public init(orchestrator: TTSOrchestrator) {
        self.orchestrator = orchestrator
    }

    // MARK: - Legacy state mapping

    public var state: TTSState {
        if orchestrator.isPaused { return .paused }
        if orchestrator.isPlaying { return .speaking }
        return .stopped
    }

    public var currentText: String? { orchestrator.currentText }

    // Legacy AVSpeech rate (0.0...1.0ish) — map to orchestrator's 0.5...2.0.
    public var rate: Float {
        get {
            let min = Double(AVSpeechUtteranceMinimumSpeechRate)
            let max = Double(AVSpeechUtteranceMaximumSpeechRate)
            let def = Double(AVSpeechUtteranceDefaultSpeechRate)
            let mul = orchestrator.rate
            // Inverse of SystemTTSBackend.mapRate
            if mul < 1.0 {
                return Float(min + (def - min) * ((mul - 0.5) / 0.5))
            } else {
                return Float(def + (max - def) * (mul - 1.0))
            }
        }
        set {
            let min = Double(AVSpeechUtteranceMinimumSpeechRate)
            let max = Double(AVSpeechUtteranceMaximumSpeechRate)
            let def = Double(AVSpeechUtteranceDefaultSpeechRate)
            let v = Double(newValue)
            let multiplier: Double
            if v <= def {
                multiplier = 0.5 + 0.5 * ((v - min) / (def - min))
            } else {
                multiplier = 1.0 + ((v - def) / (max - def))
            }
            orchestrator.rate = Swift.max(0.5, Swift.min(2.0, multiplier))
        }
    }

    public var voiceLanguage: String = "en-US" {
        didSet { syncVoice() }
    }

    public var voiceIdentifier: String? {
        didSet { syncVoice() }
    }

    private func syncVoice() {
        let id = voiceIdentifier ?? AVSpeechSynthesisVoice(language: voiceLanguage)?.identifier ?? voiceLanguage
        let name = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0)?.name } ?? "Default"
        orchestrator.setVoice(TTSVoice(id: id, name: name, language: voiceLanguage, gender: nil))
    }

    // MARK: - Playback

    public func speak(_ text: String) {
        Task { @MainActor in
            do {
                try await orchestrator.play(text: text)
            } catch {
                // Swallow — state reflects error via orchestrator.lastError
            }
        }
    }

    public func pause() { orchestrator.pause() }
    public func resume() { orchestrator.resume() }
    public func stop() { orchestrator.stop() }

    // MARK: - Voice catalogue (legacy helpers)

    nonisolated public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    nonisolated public static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
    }
}
#endif

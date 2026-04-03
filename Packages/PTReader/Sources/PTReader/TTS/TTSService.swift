import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation

public enum TTSState: String, Sendable {
    case stopped
    case speaking
    case paused
}

@Observable
public final class TTSService: NSObject, @unchecked Sendable {
    @ObservationIgnored private var _synthesizer: AVSpeechSynthesizer?
    private var synthesizer: AVSpeechSynthesizer {
        if let s = _synthesizer { return s }
        let s = AVSpeechSynthesizer()
        s.delegate = self
        _synthesizer = s
        return s
    }

    public private(set) var state: TTSState = .stopped
    public private(set) var currentText: String?

    @ObservationIgnored private var _rate: Float = AVSpeechUtteranceDefaultSpeechRate
    public var rate: Float {
        get { _rate }
        set { _rate = min(max(newValue, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate) }
    }

    public var voiceLanguage: String = "en-US"
    public var voiceIdentifier: String?

    public override init() {
        super.init()
    }

    public func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate

        if let id = voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: id)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }

        currentText = text
        state = .speaking
        synthesizer.speak(utterance)
    }

    public func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        state = .stopped
        currentText = nil
    }

    public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    public static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
    }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        state = .stopped
        currentText = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        state = .stopped
        currentText = nil
    }
}
#endif

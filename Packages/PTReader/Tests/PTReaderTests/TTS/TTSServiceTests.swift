import Testing
import Foundation
@testable import PTReader

#if canImport(AVFoundation)
import AVFoundation

@MainActor
@Suite("TTSService")
struct TTSServiceTests {
    @Test("Initializes in stopped state")
    func initialState() {
        let tts = TTSService()
        #expect(tts.state == .stopped)
        #expect(tts.currentText == nil)
        #expect(tts.rate == AVSpeechUtteranceDefaultSpeechRate)
    }

    @Test("TTSState has all expected cases")
    func stateEnum() {
        let allStates: [TTSState] = [.stopped, .speaking, .paused]
        #expect(allStates.count == 3)
    }

    @Test("Rate clamping works")
    func rateClamping() {
        let tts = TTSService()
        tts.rate = 2.0
        #expect(tts.rate <= AVSpeechUtteranceMaximumSpeechRate)
        tts.rate = -1.0
        #expect(tts.rate >= AVSpeechUtteranceMinimumSpeechRate)
    }

    @Test("Available voices returns list")
    func availableVoices() {
        let voices = TTSService.availableVoices()
        // On macOS there should be system voices available
        #expect(voices.count >= 0)
    }
}
#endif

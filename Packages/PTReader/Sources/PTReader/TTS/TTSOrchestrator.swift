import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation

/// High-level TTS playback manager that unifies on-device and cloud backends.
///
/// - On-device (`SystemTTSBackend`) plays through `AVSpeechSynthesizer`.
/// - Cloud backends return MP3 data which is played via `AVAudioPlayer`.
///
/// The orchestrator supports a chapter queue so callers can hand off a whole
/// book to be read sequentially with skip forward/backward controls.
@MainActor
@Observable
public final class TTSOrchestrator: NSObject {
    // MARK: - Published state

    public private(set) var isPlaying: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var currentText: String?
    /// 0.0...1.0 progress within the current chunk (best-effort).
    public private(set) var playbackProgress: Double = 0.0
    public private(set) var currentChunkIndex: Int = 0
    public private(set) var queue: [String] = []
    public private(set) var lastError: Error?

    /// User-facing rate multiplier, 0.5...2.0. 1.0 is normal speed.
    public var rate: Double = 1.0

    public private(set) var currentBackend: TTSBackend
    public var currentVoice: TTSVoice

    // MARK: - Internals

    @ObservationIgnored private let synthesizer: AVSpeechSynthesizer
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var synthDelegate: SynthDelegate?
    @ObservationIgnored private var playerDelegate: PlayerDelegate?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        backend: TTSBackend? = nil,
        voice: TTSVoice? = nil
    ) {
        let synth = AVSpeechSynthesizer()
        self.synthesizer = synth
        let defaultBackend: TTSBackend = backend ?? SystemTTSBackend(synthesizer: synth)
        self.currentBackend = defaultBackend
        self.currentVoice = voice ?? TTSVoice(
            id: AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? "en-US",
            name: "Default",
            language: "en-US",
            gender: nil
        )
        super.init()

        let sd = SynthDelegate(owner: self)
        self.synthDelegate = sd
        synth.delegate = sd

        let pd = PlayerDelegate(owner: self)
        self.playerDelegate = pd
    }

    // MARK: - Configuration

    public func setBackend(_ backend: TTSBackend) {
        stop()
        currentBackend = backend
    }

    public func setVoice(_ voice: TTSVoice) {
        currentVoice = voice
    }

    // MARK: - Queue

    public func enqueue(chapters: [String]) {
        queue = chapters
        currentChunkIndex = 0
    }

    public func skipForward() {
        guard currentChunkIndex + 1 < queue.count else { stop(); return }
        currentChunkIndex += 1
        playCurrentChunk()
    }

    public func skipBackward() {
        guard currentChunkIndex > 0 else {
            // Restart current chunk.
            playCurrentChunk()
            return
        }
        currentChunkIndex -= 1
        playCurrentChunk()
    }

    // MARK: - Playback

    /// Play an ad-hoc piece of text (not part of the queue).
    public func play(text: String) async throws {
        configureAudioSession()
        stopInternal(resetState: true)
        currentText = text
        isPlaying = true
        isPaused = false
        playbackProgress = 0
        lastError = nil

        do {
            let stream = try await currentBackend.synthesize(
                text: text,
                voice: currentVoice,
                rate: rate
            )
            try await handleStream(stream)
        } catch {
            lastError = error
            isPlaying = false
            throw error
        }
    }

    /// Start playing the queued chapters from `currentChunkIndex`.
    public func playQueue() {
        guard !queue.isEmpty else { return }
        playCurrentChunk()
    }

    private func playCurrentChunk() {
        guard currentChunkIndex < queue.count else { return }
        let text = queue[currentChunkIndex]
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.play(text: text)
            } catch {
                self.lastError = error
            }
        }
    }

    public func pause() {
        guard isPlaying, !isPaused else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
        audioPlayer?.pause()
        progressTimer?.invalidate()
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        audioPlayer?.play()
        startProgressTimer()
        isPaused = false
    }

    public func stop() {
        stopInternal(resetState: true)
    }

    private func stopInternal(resetState: Bool) {
        playbackTask?.cancel()
        playbackTask = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        if resetState {
            isPlaying = false
            isPaused = false
            currentText = nil
            playbackProgress = 0
        }
    }

    // MARK: - Stream handling

    private func handleStream(_ stream: TTSAudioStream) async throws {
        switch stream {
        case .synchronous:
            // System backend has already started speaking via AVSpeechSynthesizer.
            // The SynthDelegate will update isPlaying when it finishes.
            return

        case .streaming(let bytes):
            var accumulated = Data()
            for try await chunk in bytes {
                accumulated.append(chunk)
            }
            guard !accumulated.isEmpty else {
                throw TTSBackendError.invalidResponse
            }
            try playAudioData(accumulated)
        }
    }

    private func playAudioData(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = playerDelegate
        player.enableRate = true
        player.rate = Float(rate)
        player.prepareToPlay()
        audioPlayer = player
        player.play()
        startProgressTimer()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.audioPlayer else { return }
                if p.duration > 0 {
                    self.playbackProgress = p.currentTime / p.duration
                }
            }
        }
        progressTimer = timer
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal — TTS still works in foreground without explicit session.
        }
        #endif
    }

    // MARK: - Delegate callbacks

    fileprivate func handleSynthFinished() {
        // Auto-advance queue if we were playing from one.
        if !queue.isEmpty, currentChunkIndex + 1 < queue.count {
            currentChunkIndex += 1
            playCurrentChunk()
        } else {
            isPlaying = false
            isPaused = false
            currentText = nil
        }
    }

    fileprivate func handleAudioPlayerFinished(success: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil
        if success, !queue.isEmpty, currentChunkIndex + 1 < queue.count {
            currentChunkIndex += 1
            playCurrentChunk()
        } else {
            isPlaying = false
            isPaused = false
            currentText = nil
            playbackProgress = 0
        }
    }
}

// MARK: - Delegates

private final class SynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var owner: TTSOrchestrator?

    init(owner: TTSOrchestrator) {
        self.owner = owner
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak owner] in owner?.handleSynthFinished() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak owner] in owner?.handleSynthFinished() }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    weak var owner: TTSOrchestrator?

    init(owner: TTSOrchestrator) {
        self.owner = owner
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak owner] in owner?.handleAudioPlayerFinished(success: flag) }
    }
}
#endif

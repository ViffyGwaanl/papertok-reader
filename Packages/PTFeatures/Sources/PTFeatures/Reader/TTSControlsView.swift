import SwiftUI
import PTReader
import PTUI

#if canImport(AVFoundation)
import AVFoundation

/// Floating action button for TTS in the reader.
public struct TTSFabButton: View {
    @Bindable var ttsService: TTSService
    let currentText: () -> String?
    @State private var showControls = false

    public init(ttsService: TTSService, currentText: @escaping () -> String?) {
        self.ttsService = ttsService
        self.currentText = currentText
    }

    public var body: some View {
        Button {
            if ttsService.state == .stopped {
                if let text = currentText(), !text.isEmpty {
                    configureTTSAudioSession()
                    ttsService.speak(text)
                }
            } else {
                showControls = true
            }
        } label: {
            Image(systemName: ttsService.state == .speaking ? "speaker.wave.2.fill" : "speaker.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Morandi.accent, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .accessibilityLabel(ttsService.state == .speaking ? "Text-to-speech playing" : "Read aloud")
        .sheet(isPresented: $showControls) {
            TTSControlsSheet(ttsService: ttsService, currentText: currentText)
                .presentationDetents([.medium])
        }
    }
}

/// Full TTS controls sheet with play/pause, rate slider, voice picker.
public struct TTSControlsSheet: View {
    @Bindable var ttsService: TTSService
    let currentText: () -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVoiceID: String?
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []

    public init(ttsService: TTSService, currentText: @escaping () -> String?) {
        self.ttsService = ttsService
        self.currentText = currentText
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                // State indicator
                stateIndicator

                // Playback controls
                playbackControls

                // Rate slider
                rateSlider

                // Voice picker
                voicePicker

                Spacer()
            }
            .padding()
            .background(Morandi.background)
            .navigationTitle("Text-to-Speech")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                availableVoices = TTSService.voices(for: String(ttsService.voiceLanguage.prefix(2)))
                selectedVoiceID = ttsService.voiceIdentifier
            }
        }
    }

    private var stateIndicator: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(stateText)
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.secondaryText)
        }
        .padding(.top, AppSpacing.md)
    }

    private var playbackControls: some View {
        HStack(spacing: AppSpacing.xl) {
            // Stop
            Button {
                ttsService.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundStyle(ttsService.state == .stopped ? Morandi.tertiaryText : Morandi.primaryText)
            }
            .disabled(ttsService.state == .stopped)
            .accessibilityLabel("Stop")

            // Play / Pause
            Button {
                togglePlayback()
            } label: {
                Image(systemName: ttsService.state == .speaking ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(ttsService.state == .speaking ? "Pause" : "Play")

            // Replay
            Button {
                ttsService.stop()
                if let text = currentText(), !text.isEmpty {
                    ttsService.speak(text)
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title2)
                    .foregroundStyle(Morandi.primaryText)
            }
            .accessibilityLabel("Restart")
        }
        .padding(.vertical, AppSpacing.md)
    }

    private var rateSlider: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Speed")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Text(rateLabel)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "tortoise.fill")
                    .font(.caption)
                    .foregroundStyle(Morandi.tertiaryText)

                Slider(
                    value: Binding(
                        get: { normalizedRate },
                        set: { ttsService.rate = denormalizeRate($0) }
                    ),
                    in: 0...1,
                    step: 0.05
                )
                .tint(Morandi.accent)

                Image(systemName: "hare.fill")
                    .font(.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            }
        }
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Voice")
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.primaryText)

            if availableVoices.isEmpty {
                Text("No voices available for current language")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            } else {
                Picker("Voice", selection: $selectedVoiceID) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier as String?)
                    }
                }
                .pickerStyle(.menu)
                .tint(Morandi.accent)
                .onChange(of: selectedVoiceID) { _, newValue in
                    ttsService.voiceIdentifier = newValue
                }
            }

            // Language selector
            HStack {
                Text("Language")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                Spacer()
                Picker("Language", selection: $ttsService.voiceLanguage) {
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Chinese (Simplified)").tag("zh-CN")
                    Text("Chinese (Traditional)").tag("zh-TW")
                    Text("Japanese").tag("ja-JP")
                    Text("Korean").tag("ko-KR")
                    Text("French").tag("fr-FR")
                    Text("German").tag("de-DE")
                    Text("Spanish").tag("es-ES")
                }
                .pickerStyle(.menu)
                .tint(Morandi.accent)
                .onChange(of: ttsService.voiceLanguage) { _, lang in
                    availableVoices = TTSService.voices(for: String(lang.prefix(2)))
                    selectedVoiceID = nil
                    ttsService.voiceIdentifier = nil
                }
            }
        }
    }

    // MARK: - Helpers

    private func togglePlayback() {
        switch ttsService.state {
        case .speaking:
            ttsService.pause()
        case .paused:
            ttsService.resume()
        case .stopped:
            if let text = currentText(), !text.isEmpty {
                configureTTSAudioSession()
                ttsService.speak(text)
            }
        }
    }

    private var stateText: String {
        switch ttsService.state {
        case .stopped: return "Stopped"
        case .speaking: return "Speaking"
        case .paused: return "Paused"
        }
    }

    private var stateColor: Color {
        switch ttsService.state {
        case .stopped: return Morandi.tertiaryText
        case .speaking: return Morandi.sage
        case .paused: return Morandi.accent
        }
    }

    // Map rate from AVSpeech range to 0-1 normalized, and display as multiplier (0.5x-2x)
    private var normalizedRate: Float {
        let min = AVSpeechUtteranceMinimumSpeechRate
        let max = AVSpeechUtteranceMaximumSpeechRate
        return (ttsService.rate - min) / (max - min)
    }

    private func denormalizeRate(_ normalized: Float) -> Float {
        let min = AVSpeechUtteranceMinimumSpeechRate
        let max = AVSpeechUtteranceMaximumSpeechRate
        return min + normalized * (max - min)
    }

    private var rateLabel: String {
        // Map to human-friendly 0.5x - 2.0x range
        let multiplier = 0.5 + Double(normalizedRate) * 1.5
        return String(format: "%.1fx", multiplier)
    }
}

/// Configure the audio session for TTS background playback.
private func configureTTSAudioSession() {
    #if os(iOS)
    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    } catch {
        // Audio session setup failed — TTS will still work in foreground
    }
    #endif
}
#endif

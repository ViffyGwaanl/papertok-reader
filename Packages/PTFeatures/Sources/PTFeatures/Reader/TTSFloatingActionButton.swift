import SwiftUI
import PTReader
import PTUI

#if canImport(AVFoundation)
import AVFoundation

/// Floating pill control for TTS playback shown over the reader.
///
/// - Collapsed: compact pill showing play/pause, current title, and a progress bar.
/// - Expanded (via tap): a sheet with backend + voice pickers, rate slider, and
///   transport controls (skip/stop).
///
/// The button hides itself when `chapterTitle` is nil — i.e. no book is loaded.
public struct TTSFloatingActionButton: View {
    @Bindable var service: TTSService
    let chapterTitle: String?
    let currentText: () -> String?

    @State private var showControls = false

    public init(
        service: TTSService,
        chapterTitle: String?,
        currentText: @escaping () -> String?
    ) {
        self.service = service
        self.chapterTitle = chapterTitle
        self.currentText = currentText
    }

    public var body: some View {
        if let title = chapterTitle {
            pill(title: title)
                .sheet(isPresented: $showControls) {
                    TTSExpandedControlsSheet(service: service, currentText: currentText)
                        .presentationDetents([.medium, .large])
                }
        }
    }

    @ViewBuilder
    private func pill(title: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Button(action: togglePlayback) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Morandi.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.state == .speaking ? "Pause" : "Play")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(1)
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .tint(Morandi.accent)
                    .frame(height: 3)
            }
            .frame(maxWidth: 160)

            Button {
                showControls = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Morandi.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More TTS controls")
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            Capsule()
                .fill(Morandi.background)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Morandi.tertiaryText.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch service.state {
        case .speaking: return "pause.fill"
        case .paused: return "play.fill"
        case .stopped: return "play.fill"
        }
    }

    private var progressValue: Double {
        let p = service.orchestrator.playbackProgress
        return (service.state == .stopped && p == 0) ? 0 : max(0, min(1, p))
    }

    private func togglePlayback() {
        switch service.state {
        case .speaking:
            service.pause()
        case .paused:
            service.resume()
        case .stopped:
            if let text = currentText(), !text.isEmpty {
                service.speak(text)
            }
        }
    }
}

// MARK: - Expanded controls sheet

struct TTSExpandedControlsSheet: View {
    @Bindable var service: TTSService
    let currentText: () -> String?
    @Environment(\.dismiss) private var dismiss

    enum BackendKind: String, CaseIterable, Identifiable {
        case system, openai, azure
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .openai: return "OpenAI"
            case .azure: return "Azure"
            }
        }
    }

    @State private var selectedBackend: BackendKind = .system
    @State private var voices: [TTSVoice] = []
    @State private var selectedVoiceID: String = ""
    @State private var loadingVoices = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    backendSection
                    voiceSection
                    rateSection
                    transportSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
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
            .task { await loadVoices() }
        }
    }

    // MARK: - Sections

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Voice engine")
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.primaryText)

            Picker("Engine", selection: $selectedBackend) {
                ForEach(BackendKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedBackend) { _, newValue in
                switchBackend(to: newValue)
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Voice")
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.primaryText)

            if loadingVoices {
                ProgressView().tint(Morandi.accent)
            } else if voices.isEmpty {
                Text("No voices available")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            } else {
                Picker("Voice", selection: $selectedVoiceID) {
                    ForEach(voices) { v in
                        Text("\(v.name) — \(v.language)").tag(v.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Morandi.accent)
                .onChange(of: selectedVoiceID) { _, newID in
                    if let v = voices.first(where: { $0.id == newID }) {
                        service.orchestrator.setVoice(v)
                    }
                }
            }
        }
    }

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Speed")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Text(String(format: "%.1fx", service.orchestrator.rate))
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "tortoise.fill")
                    .font(.caption)
                    .foregroundStyle(Morandi.tertiaryText)
                Slider(
                    value: Binding(
                        get: { service.orchestrator.rate },
                        set: { service.orchestrator.rate = $0 }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                )
                .tint(Morandi.accent)
                Image(systemName: "hare.fill")
                    .font(.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            }
        }
    }

    private var transportSection: some View {
        HStack(spacing: AppSpacing.xl) {
            Button {
                service.orchestrator.skipBackward()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(Morandi.primaryText)
            }
            .accessibilityLabel("Previous chapter")

            Button {
                togglePlay()
            } label: {
                Image(systemName: service.state == .speaking ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(service.state == .speaking ? "Pause" : "Play")

            Button {
                service.orchestrator.skipForward()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(Morandi.primaryText)
            }
            .accessibilityLabel("Next chapter")

            Button {
                service.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundStyle(service.state == .stopped ? Morandi.tertiaryText : Morandi.primaryText)
            }
            .disabled(service.state == .stopped)
            .accessibilityLabel("Stop")
        }
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Actions

    private func togglePlay() {
        switch service.state {
        case .speaking: service.pause()
        case .paused: service.resume()
        case .stopped:
            if let text = currentText(), !text.isEmpty {
                service.speak(text)
            }
        }
    }

    private func switchBackend(to kind: BackendKind) {
        let backend: TTSBackend
        switch kind {
        case .system:
            backend = SystemTTSBackend(synthesizer: AVSpeechSynthesizer())
        case .openai:
            backend = OpenAITTSBackend()
        case .azure:
            backend = AzureTTSBackend()
        }
        service.orchestrator.setBackend(backend)
        Task { await loadVoices() }
    }

    private func loadVoices() async {
        loadingVoices = true
        errorMessage = nil
        defer { loadingVoices = false }
        do {
            let list = try await service.orchestrator.currentBackend.availableVoices()
            voices = list
            selectedVoiceID = list.first?.id ?? ""
            if let first = list.first {
                service.orchestrator.setVoice(first)
            }
        } catch {
            voices = []
            errorMessage = "Failed to load voices: \(error.localizedDescription)"
        }
    }
}
#endif

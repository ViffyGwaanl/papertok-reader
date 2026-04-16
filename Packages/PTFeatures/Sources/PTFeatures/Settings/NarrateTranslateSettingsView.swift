import SwiftUI
import PTCore
import PTUI

/// Settings view for narration (TTS) and translation configuration.
public struct NarrateTranslateSettingsView: View {
    @State private var targetLanguage: String
    @State private var translationUseChatModel: Bool
    @State private var translationModelId: String
    @State private var narrationBackend: String
    @State private var narrationVoiceId: String
    @State private var narrationSpeed: Double

    private let defaults: UserDefaults
    private let viewModel: SettingsViewModel

    @MainActor
    public init(
        viewModel: SettingsViewModel,
        defaults: UserDefaults = AppConfig.groupDefaults
    ) {
        self.defaults = defaults
        self.viewModel = viewModel
        let prefs = NarrateTranslatePreferences.load(defaults: defaults)
        _targetLanguage = State(initialValue: prefs.targetLanguage)
        _translationUseChatModel = State(initialValue: prefs.translationUseChatModel)
        _translationModelId = State(initialValue: prefs.translationModelId)
        _narrationBackend = State(initialValue: prefs.narrationBackend)
        _narrationVoiceId = State(initialValue: prefs.narrationVoiceId)
        _narrationSpeed = State(initialValue: prefs.narrationSpeed)
    }

    public var body: some View {
        Form {
            translationSection
            narrationSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.ai.translation.section"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Translation

    private var translationSection: some View {
        Section {
            Picker(
                String(localized: "settings.ai.translation.target_language"),
                selection: $targetLanguage
            ) {
                ForEach(NarrateTranslatePreferences.supportedLanguages, id: \.id) { lang in
                    Text(lang.name).tag(lang.id)
                }
            }
            .foregroundStyle(Morandi.primaryText)
            .onChange(of: targetLanguage) { _, newValue in
                NarrateTranslatePreferences.persistTargetLanguage(newValue, defaults: defaults)
            }

            Toggle(
                String(localized: "settings.ai.translation.use_chat_model"),
                isOn: $translationUseChatModel
            )
            .tint(Morandi.accent)
            .onChange(of: translationUseChatModel) { _, newValue in
                NarrateTranslatePreferences.persistTranslationUseChatModel(newValue, defaults: defaults)
            }

            if !translationUseChatModel {
                Picker(
                    String(localized: "settings.ai.translation.model"),
                    selection: $translationModelId
                ) {
                    ForEach(AIProviderID.allCases) { provider in
                        Text(provider.displayName)
                            .tag(provider.defaultModel)
                    }
                }
                .foregroundStyle(Morandi.primaryText)
                .onChange(of: translationModelId) { _, newValue in
                    NarrateTranslatePreferences.persistTranslationModelId(newValue, defaults: defaults)
                }
            }
        } header: {
            Text("settings.ai.translation.section")
        }
    }

    // MARK: - Narration

    private var narrationSection: some View {
        Section {
            Picker(
                String(localized: "settings.ai.narration.backend"),
                selection: $narrationBackend
            ) {
                ForEach(NarrateTranslatePreferences.availableBackends, id: \.id) { backend in
                    Text(backend.name).tag(backend.id)
                }
            }
            .foregroundStyle(Morandi.primaryText)
            .onChange(of: narrationBackend) { _, newValue in
                NarrateTranslatePreferences.persistNarrationBackend(newValue, defaults: defaults)
            }

            TextField(
                String(localized: "settings.ai.narration.voice"),
                text: $narrationVoiceId
            )
            .foregroundStyle(Morandi.primaryText)
            .onChange(of: narrationVoiceId) { _, newValue in
                NarrateTranslatePreferences.persistNarrationVoiceId(newValue, defaults: defaults)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "settings.ai.narration.speed"))
                        .foregroundStyle(Morandi.primaryText)
                    Spacer()
                    Text(String(format: "%.1fx", narrationSpeed))
                        .foregroundStyle(Morandi.secondaryText)
                        .monospacedDigit()
                }
                Slider(value: $narrationSpeed, in: 0.5...2.0, step: 0.1)
                    .tint(Morandi.accent)
                    .onChange(of: narrationSpeed) { _, newValue in
                        NarrateTranslatePreferences.persistNarrationSpeed(newValue, defaults: defaults)
                    }
            }
        } header: {
            Text("settings.ai.narration.section")
        }
    }
}

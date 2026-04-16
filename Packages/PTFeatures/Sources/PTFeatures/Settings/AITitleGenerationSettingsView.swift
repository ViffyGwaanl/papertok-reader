import SwiftUI
import PTCore
import PTUI

/// Settings view for AI title generation configuration.
public struct AITitleGenerationSettingsView: View {
    @State private var isEnabled: Bool
    @State private var useChatModel: Bool
    @State private var titleModelId: String
    @State private var maxWords: Int

    private let defaults: UserDefaults
    private let viewModel: SettingsViewModel

    @MainActor
    public init(
        viewModel: SettingsViewModel,
        defaults: UserDefaults = AppConfig.groupDefaults
    ) {
        self.defaults = defaults
        self.viewModel = viewModel
        let prefs = AITitleGenerationPreferences.load(defaults: defaults)
        _isEnabled = State(initialValue: prefs.isEnabled)
        _useChatModel = State(initialValue: prefs.useChatModel)
        _titleModelId = State(initialValue: prefs.titleModelId)
        _maxWords = State(initialValue: prefs.maxWords)
    }

    public var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "settings.ai.title_gen.enabled"),
                    isOn: $isEnabled
                )
                .tint(Morandi.accent)
                .onChange(of: isEnabled) { _, newValue in
                    AITitleGenerationPreferences.persistEnabled(newValue, defaults: defaults)
                }
            } header: {
                Text("settings.ai.title_gen.section")
            }

            if isEnabled {
                Section {
                    Toggle(
                        String(localized: "settings.ai.title_gen.use_chat_model"),
                        isOn: $useChatModel
                    )
                    .tint(Morandi.accent)
                    .onChange(of: useChatModel) { _, newValue in
                        AITitleGenerationPreferences.persistUseChatModel(newValue, defaults: defaults)
                    }

                    if !useChatModel {
                        Picker(
                            String(localized: "settings.ai.title_gen.model"),
                            selection: $titleModelId
                        ) {
                            ForEach(AIProviderID.allCases) { provider in
                                Text(provider.displayName)
                                    .tag(provider.defaultModel)
                            }
                        }
                        .foregroundStyle(Morandi.primaryText)
                        .onChange(of: titleModelId) { _, newValue in
                            AITitleGenerationPreferences.persistModelId(newValue, defaults: defaults)
                        }
                    }
                } header: {
                    Text("settings.ai.title_gen.model")
                }

                Section {
                    Stepper(
                        value: $maxWords,
                        in: 4...20
                    ) {
                        HStack {
                            Text(String(localized: "settings.ai.title_gen.max_words"))
                                .foregroundStyle(Morandi.primaryText)
                            Spacer()
                            Text("\(maxWords)")
                                .foregroundStyle(Morandi.secondaryText)
                        }
                    }
                    .onChange(of: maxWords) { _, newValue in
                        AITitleGenerationPreferences.persistMaxWords(newValue, defaults: defaults)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.ai.title_gen.section"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

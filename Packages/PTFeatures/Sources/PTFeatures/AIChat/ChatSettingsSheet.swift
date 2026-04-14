import SwiftUI
import PTUI

/// Chat generation settings sheet — temperature, maxTokens, topP, system prompt.
struct ChatSettingsSheet: View {
    @Bindable var viewModel: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var temperature: Double = AIChatViewModel.ChatGenerationSettings.default.temperature
    @State private var maxTokens: Double = Double(AIChatViewModel.ChatGenerationSettings.default.maxTokens)
    @State private var topP: Double = AIChatViewModel.ChatGenerationSettings.default.topP
    @State private var systemPrompt: String = AIChatViewModel.ChatGenerationSettings.default.systemPrompt
    @State private var perConversation: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    slider(
                        title: String(localized: "ai.temperature"),
                        value: $temperature,
                        range: 0...2,
                        step: 0.05,
                        format: "%.2f",
                        hint: String(localized: "ai.chat_settings.temperature_hint")
                    )
                    slider(
                        title: String(localized: "ai.max_tokens"),
                        value: $maxTokens,
                        range: 100...8192,
                        step: 64,
                        format: "%.0f",
                        hint: String(localized: "ai.chat_settings.max_tokens_hint")
                    )
                    slider(
                        title: String(localized: "ai.top_p"),
                        value: $topP,
                        range: 0...1,
                        step: 0.01,
                        format: "%.2f",
                        hint: String(localized: "ai.chat_settings.top_p_hint")
                    )
                } header: {
                    Text("settings.generation")
                        .foregroundStyle(Morandi.secondaryText)
                }

                Section {
                    TextEditor(text: $systemPrompt)
                        .font(AppTypography.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Morandi.cardBackground)
                } header: {
                    Text("ai.chat_settings.system_prompt")
                        .foregroundStyle(Morandi.secondaryText)
                }

                Section {
                    Toggle("ai.chat_settings.per_conversation", isOn: $perConversation)
                        .tint(Morandi.accent)
                } footer: {
                    Text(
                        perConversation
                            ? String(localized: "ai.chat_settings.per_conversation_footer")
                            : String(localized: "ai.chat_settings.global_footer")
                    )
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                }

                Section {
                    Button(role: .destructive) {
                        reset()
                    } label: {
                        Label("ai.chat_settings.reset_to_defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle("ai.chat_settings.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(Morandi.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        save()
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(Morandi.accent)
                }
            }
            .onAppear {
                let s = viewModel.settings
                temperature = s.temperature
                maxTokens = Double(s.maxTokens)
                topP = s.topP
                systemPrompt = s.systemPrompt
                perConversation = s.perConversation
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func slider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Morandi.secondaryText)
            }
            Slider(value: value, in: range, step: step)
                .tint(Morandi.accent)
            Text(hint)
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private func reset() {
        let d = AIChatViewModel.ChatGenerationSettings.default
        temperature = d.temperature
        maxTokens = Double(d.maxTokens)
        topP = d.topP
        systemPrompt = d.systemPrompt
        perConversation = false
    }

    private func save() {
        viewModel.settings = AIChatViewModel.ChatGenerationSettings(
            temperature: temperature,
            maxTokens: Int(maxTokens),
            topP: topP,
            systemPrompt: systemPrompt,
            perConversation: perConversation
        )
    }
}

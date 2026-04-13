import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// Settings page for AI image analysis (vision) — selects a vision-capable
/// provider and model, default prompt, max image size, quality, and toggles
/// integration into the reader / highlights.
@MainActor
public struct AIImageAnalysisView: View {
    @State private var providerId: String
    @State private var modelId: String
    @State private var defaultPrompt: String
    @State private var maxImageSize: Double
    @State private var quality: String
    @State private var enableForReader: Bool
    @State private var enableForHighlights: Bool

    private let defaults = AppConfig.groupDefaults

    private func localized(_ key: String, _ fallback: String) -> String {
        AppLocalization.string(key, value: fallback)
    }

    public init() {
        let d = AppConfig.groupDefaults
        _providerId = State(initialValue: d.string(forKey: "ai_vision_provider") ?? "openai")
        _modelId = State(initialValue: d.string(forKey: "ai_vision_model") ?? "gpt-4o-mini")
        _defaultPrompt = State(initialValue: d.string(forKey: "ai_vision_prompt")
            ?? AppLocalization.string(
                "ai.image_analysis.default_prompt_value",
                value: "Describe this image in detail. Highlight any text, diagrams, or notable elements."
            ))
        _maxImageSize = State(initialValue: d.object(forKey: "ai_vision_max_size") as? Double ?? 1024)
        _quality = State(initialValue: d.string(forKey: "ai_vision_quality") ?? "medium")
        _enableForReader = State(initialValue: d.bool(forKey: "ai_vision_reader_enabled"))
        _enableForHighlights = State(initialValue: d.bool(forKey: "ai_vision_highlights_enabled"))
    }

    public var body: some View {
        formContent
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(String(localized: "settings.ai_image_analysis"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private var formContent: some View {
        Form {
            providerSection
            modelSection
            promptSection
            qualitySection
            integrationSection
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section(String(localized: "ai.vision")) {
            Picker(String(localized: "common.provider"), selection: $providerId) {
                ForEach(visionProviders, id: \.0) { (id, name) in
                    Text(name).tag(id)
                }
            }
        }
        .onChange(of: providerId) { _, v in
            defaults.set(v, forKey: "ai_vision_provider")
            let models = visionModels(for: v)
            if !models.contains(modelId), let first = models.first {
                modelId = first
            }
        }
    }

    private var modelSection: some View {
        Section(String(localized: "common.model")) {
            Picker(String(localized: "common.model"), selection: $modelId) {
                ForEach(visionModels(for: providerId), id: \.self) { m in
                    Text(m).tag(m)
                }
                if !visionModels(for: providerId).contains(modelId) && !modelId.isEmpty {
                    Text(modelId).tag(modelId)
                }
            }
            TextField(localized("ai.providers.custom_model_id", "Or enter custom model ID"), text: $modelId)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .font(AppTypography.caption)
        }
        .onChange(of: modelId) { _, v in defaults.set(v, forKey: "ai_vision_model") }
    }

    private var promptSection: some View {
        Section {
            TextEditor(text: $defaultPrompt)
                .frame(minHeight: 100)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)
        } header: {
            Text(localized("ai.image_analysis.default_prompt", "Default Prompt"))
        } footer: {
            Text(localized(
                "ai.image_analysis.prompt_footer",
                "Used as the system prompt when analysing an image without an explicit user prompt."
            ))
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
        .onChange(of: defaultPrompt) { _, v in defaults.set(v, forKey: "ai_vision_prompt") }
    }

    private var qualitySection: some View {
        Section(localized("ai.image_analysis.quality", "Quality")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(localized("ai.image_analysis.max_image_size", "Max Image Size"))
                    Spacer()
                    Text("\(Int(maxImageSize)) px")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(Morandi.secondaryText)
                }
                Slider(value: $maxImageSize, in: 256...4096, step: 128)
                    .tint(Morandi.accent)
            }
            Picker(localized("ai.image_analysis.quality", "Quality"), selection: $quality) {
                Text(localized("ai.image_analysis.quality.low", "Low")).tag("low")
                Text(localized("ai.image_analysis.quality.medium", "Medium")).tag("medium")
                Text(localized("ai.image_analysis.quality.high", "High")).tag("high")
            }
        }
        .onChange(of: maxImageSize) { _, v in defaults.set(v, forKey: "ai_vision_max_size") }
        .onChange(of: quality) { _, v in defaults.set(v, forKey: "ai_vision_quality") }
    }

    private var integrationSection: some View {
        Section(localized("ai.image_analysis.integrations", "Integrations")) {
            Toggle(localized("ai.image_analysis.enable_for_reader_images", "Enable for Reader Images"), isOn: $enableForReader)
                .tint(Morandi.accent)
            Toggle(localized("ai.image_analysis.enable_for_highlights", "Enable for Highlights"), isOn: $enableForHighlights)
                .tint(Morandi.accent)
        }
        .onChange(of: enableForReader) { _, v in defaults.set(v, forKey: "ai_vision_reader_enabled") }
        .onChange(of: enableForHighlights) { _, v in defaults.set(v, forKey: "ai_vision_highlights_enabled") }
    }

    // MARK: - Helpers

    private var visionProviders: [(String, String)] {
        [
            ("openai", "OpenAI"),
            ("anthropic", "Anthropic"),
            ("gemini", "Google Gemini"),
            ("azure", "Azure OpenAI")
        ]
    }

    private func visionModels(for providerId: String) -> [String] {
        switch providerId {
        case "openai":
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case "anthropic":
            return ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-3-5-sonnet-20241022"]
        case "gemini":
            return ["gemini-2.0-flash-exp", "gemini-1.5-pro", "gemini-1.5-flash"]
        case "azure":
            return []
        default:
            return []
        }
    }
}

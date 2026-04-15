import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// In-reader popup for translating selected text.
///
/// Shows the original text, language pair selection, and the translated result.
/// Designed to appear as a sheet or popover from reader text selection context menus.
public struct TranslationPopupView: View {
    let selectedText: String
    let translationService: AITranslationService
    let onDismiss: () -> Void

    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var targetLanguage = LanguageOption.defaultTargetIdentifier
    @State private var sourceLanguage = LanguageOption.autoDetect.identifier

    public init(
        selectedText: String,
        translationService: AITranslationService,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.translationService = translationService
        self.onDismiss = onDismiss
    }

    private struct LanguageOption: Identifiable, Hashable {
        let identifier: String
        let englishName: String

        var id: String { identifier }

        var localizedName: String {
            if identifier == Self.autoDetect.identifier {
                return String(localized: "ai.detect_language")
            }

            if let localized = Locale.autoupdatingCurrent.localizedString(forIdentifier: identifier),
               localized.isEmpty == false {
                return localized
            }

            return englishName
        }

        static let autoDetect = LanguageOption(identifier: "auto", englishName: "Auto-detect")

        static let all: [LanguageOption] = [
            .autoDetect,
            .init(identifier: "en", englishName: "English"),
            .init(identifier: "zh-Hans", englishName: "Chinese (Simplified)"),
            .init(identifier: "zh-Hant", englishName: "Chinese (Traditional)"),
            .init(identifier: "ja", englishName: "Japanese"),
            .init(identifier: "ko", englishName: "Korean"),
            .init(identifier: "fr", englishName: "French"),
            .init(identifier: "de", englishName: "German"),
            .init(identifier: "es", englishName: "Spanish"),
            .init(identifier: "pt", englishName: "Portuguese"),
            .init(identifier: "it", englishName: "Italian"),
            .init(identifier: "ru", englishName: "Russian"),
            .init(identifier: "ar", englishName: "Arabic"),
            .init(identifier: "hi", englishName: "Hindi"),
            .init(identifier: "th", englishName: "Thai"),
            .init(identifier: "vi", englishName: "Vietnamese"),
            .init(identifier: "id", englishName: "Indonesian"),
            .init(identifier: "tr", englishName: "Turkish"),
            .init(identifier: "nl", englishName: "Dutch"),
            .init(identifier: "pl", englishName: "Polish"),
            .init(identifier: "sv", englishName: "Swedish")
        ]

        static let targetLanguages = all.filter { $0.identifier != autoDetect.identifier }

        static var defaultTargetIdentifier: String {
            let localeIdentifier = Locale.autoupdatingCurrent.identifier.lowercased()
            if localeIdentifier.contains("hant") || localeIdentifier.contains("zh_tw") || localeIdentifier.contains("zh-hk") {
                return "zh-Hant"
            }
            if localeIdentifier.hasPrefix("zh") {
                return "zh-Hans"
            }
            return "en"
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Original text
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("reader.original")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(Morandi.secondaryText)

                        Text(selectedText)
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.primaryText)
                            .padding(AppSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                                    .fill(Morandi.cardBackground)
                            )
                            .textSelection(.enabled)
                    }

                    // Language pair
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("common.languages")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(Morandi.secondaryText)

                        HStack(spacing: AppSpacing.md) {
                            Picker(String(localized: "common.from"), selection: $sourceLanguage) {
                                ForEach(LanguageOption.all) { option in
                                    Text(option.localizedName).tag(option.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Morandi.accent)

                            Image(systemName: "arrow.right")
                                .foregroundStyle(Morandi.tertiaryText)

                            Picker(String(localized: "common.to"), selection: $targetLanguage) {
                                ForEach(LanguageOption.targetLanguages) { option in
                                    Text(option.localizedName).tag(option.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Morandi.accent)
                        }
                    }

                    // Translate button
                    Button {
                        Task { await translate() }
                    } label: {
                        HStack {
                            if isTranslating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isTranslating ? String(localized: "common.translating") : String(localized: "reader.translate"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Morandi.accent)
                    .disabled(isTranslating)

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.destructive)
                    }

                    // Translation result
                    if !translatedText.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                Text("ai.translation_popup")
                                    .font(AppTypography.caption.weight(.semibold))
                                    .foregroundStyle(Morandi.secondaryText)

                                Spacer()

                                Button {
                                    #if os(iOS)
                                    UIPasteboard.general.string = translatedText
                                    #else
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(translatedText, forType: .string)
                                    #endif
                                } label: {
                                    Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(Morandi.accent)
                                }
                                .buttonStyle(.plain)
                            }

                            Text(translatedText)
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)
                                .padding(AppSpacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                                        .fill(Morandi.sage.opacity(0.15))
                                )
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "reader.translate"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) { onDismiss() }
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .task {
            await translate()
        }
    }

    private func translate() async {
        guard !isTranslating else { return }
        isTranslating = true
        errorMessage = nil
        translatedText = ""

        let source = LanguageOption.all.first(where: { $0.identifier == sourceLanguage })
        let target = LanguageOption.targetLanguages.first(where: { $0.identifier == targetLanguage })

        do {
            translatedText = try await translationService.translate(
                selectedText,
                to: target?.englishName ?? "English",
                from: source?.identifier == LanguageOption.autoDetect.identifier ? nil : source?.englishName
            )
        } catch {
            errorMessage = AppLocalization.userFacingErrorMessage(
                for: error,
                fallbackKey: "errors.translation.failed"
            )
        }

        isTranslating = false
    }
}

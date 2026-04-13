import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// In-reader translation sheet with source text, language grid, and result display.
struct TranslationMenuSheet: View {
    let selectedText: String
    let translationService: AITranslationService?
    let onDismiss: () -> Void

    @State private var targetLanguage = LanguageOption.defaultTargetIdentifier
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?

    private struct LanguageOption: Identifiable, Hashable {
        let identifier: String
        let englishName: String

        var id: String { identifier }

        var localizedName: String {
            if let localized = Locale.autoupdatingCurrent.localizedString(forIdentifier: identifier),
               localized.isEmpty == false {
                return localized
            }
            return englishName
        }

        static let all: [LanguageOption] = [
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
            .init(identifier: "sv", englishName: "Swedish"),
            .init(identifier: "da", englishName: "Danish")
        ]

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    sourceSection
                    languageGrid
                    resultSection
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
                    Button(String(localized: "common.done"), action: onDismiss)
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await translate()
        }
    }

    // MARK: - Source Text

    private var sourceSection: some View {
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
    }

    // MARK: - Language Grid

    private var languageGrid: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("reader.target_language")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(Morandi.secondaryText)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 3),
                spacing: AppSpacing.sm
            ) {
                ForEach(LanguageOption.all) { option in
                    Button {
                        targetLanguage = option.identifier
                        Task { await translate() }
                    } label: {
                        Text(option.localizedName)
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                option.identifier == targetLanguage ? .white : Morandi.primaryText
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.xs)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                                    .fill(
                                        option.identifier == targetLanguage
                                            ? Morandi.accent
                                            : Morandi.cardBackground
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Translation Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if isTranslating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Morandi.accent)
                    Text("common.translating")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.destructive)
            }

            if !translatedText.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text("reader.translation")
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
    }

    // MARK: - Translation Logic

    private func translate() async {
        guard let translationService else {
            errorMessage = AppLocalization.string(
                "errors.translation.not_configured",
                value: "Translation service is not configured."
            )
            return
        }
        guard !isTranslating else { return }

        isTranslating = true
        errorMessage = nil
        translatedText = ""

        do {
            let target = LanguageOption.all.first(where: { $0.identifier == targetLanguage })
            translatedText = try await translationService.translate(
                selectedText,
                to: target?.englishName ?? "English"
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }
}

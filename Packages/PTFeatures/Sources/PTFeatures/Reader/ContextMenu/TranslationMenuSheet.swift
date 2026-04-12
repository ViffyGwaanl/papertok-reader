import SwiftUI
import PTAIServices
import PTUI

/// In-reader translation sheet with source text, language grid, and result display.
struct TranslationMenuSheet: View {
    let selectedText: String
    let translationService: AITranslationService?
    let onDismiss: () -> Void

    @State private var targetLanguage: String = "English"
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?

    private static let languages = [
        "English", "Chinese (Simplified)", "Chinese (Traditional)",
        "Japanese", "Korean", "French", "German", "Spanish",
        "Portuguese", "Italian", "Russian", "Arabic", "Hindi",
        "Thai", "Vietnamese", "Indonesian", "Turkish", "Dutch",
        "Polish", "Swedish", "Danish"
    ]

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
                    Button("Done", action: onDismiss)
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
            Text("Original")
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
            Text("Target Language")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(Morandi.secondaryText)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 3),
                spacing: AppSpacing.sm
            ) {
                ForEach(Self.languages, id: \.self) { lang in
                    Button {
                        targetLanguage = lang
                        Task { await translate() }
                    } label: {
                        Text(lang)
                            .font(AppTypography.caption)
                            .foregroundStyle(
                                lang == targetLanguage ? .white : Morandi.primaryText
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.xs)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                                    .fill(
                                        lang == targetLanguage
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
                    Text("Translating...")
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
                        Text("Translation")
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
                            Label("Copy", systemImage: "doc.on.doc")
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
            errorMessage = "Translation service is not configured."
            return
        }
        guard !isTranslating else { return }

        isTranslating = true
        errorMessage = nil
        translatedText = ""

        do {
            translatedText = try await translationService.translate(
                selectedText,
                to: targetLanguage
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }
}

import SwiftUI
import PTAIServices
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
    @State private var targetLanguage: String = "English"
    @State private var sourceLanguage: String = "Auto-detect"

    public init(
        selectedText: String,
        translationService: AITranslationService,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.translationService = translationService
        self.onDismiss = onDismiss
    }

    private static let languages = [
        "Auto-detect", "English", "Chinese (Simplified)", "Chinese (Traditional)",
        "Japanese", "Korean", "French", "German", "Spanish", "Portuguese",
        "Italian", "Russian", "Arabic", "Hindi", "Thai", "Vietnamese",
        "Indonesian", "Turkish", "Dutch", "Polish", "Swedish"
    ]

    private static let targetLanguages: [String] = {
        languages.filter { $0 != "Auto-detect" }
    }()

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
                            Picker("From", selection: $sourceLanguage) {
                                ForEach(Self.languages, id: \.self) { lang in
                                    Text(lang).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Morandi.accent)

                            Image(systemName: "arrow.right")
                                .foregroundStyle(Morandi.tertiaryText)

                            Picker("To", selection: $targetLanguage) {
                                ForEach(Self.targetLanguages, id: \.self) { lang in
                                    Text(lang).tag(lang)
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
                            Text(isTranslating ? "Translating..." : "Translate")
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

        let source: String? = sourceLanguage == "Auto-detect" ? nil : sourceLanguage

        do {
            translatedText = try await translationService.translate(
                selectedText,
                to: targetLanguage,
                from: source
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }
}

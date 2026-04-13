import SwiftUI
import PTCore
import PTUI

/// Advanced reading appearance settings — font family/size, line height,
/// spacing, margins, theme preview, custom CSS editor, and a live sample
/// card showing the result of the current choices.
public struct ReadingDetailSettingsView: View {
    @State private var viewModel: SettingsViewModel

    private struct ThemeOption {
        let id: String
        let name: String
        let bg: Color
        let fg: Color
    }

    private static let themes: [ThemeOption] = [
        ThemeOption(
            id: "light",
            name: AppLocalization.string("reader.appearance.theme_light", value: "Light"),
            bg: Color(hex: "FAF8F5"),
            fg: Color(hex: "343434")
        ),
        ThemeOption(
            id: "sepia",
            name: AppLocalization.string("reader.appearance.theme_sepia", value: "Sepia"),
            bg: Color(hex: "F4ECD8"),
            fg: Color(hex: "5B4636")
        ),
        ThemeOption(
            id: "dark",
            name: AppLocalization.string("reader.appearance.theme_dark", value: "Dark"),
            bg: Color(hex: "1A1A2E"),
            fg: Color(hex: "E8E4E0")
        ),
        ThemeOption(
            id: "custom",
            name: AppLocalization.string("reader.appearance.theme_custom", value: "Custom"),
            bg: Color(hex: "EFEFF4"),
            fg: Color(hex: "343434")
        ),
    ]

    @MainActor
    public init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
    }

    public var body: some View {
        Form {
            previewSection
            fontSection
            layoutSection
            marginSection
            themeSection
            customCSSSection
            resetSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "reader.appearance.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: viewModel.lineHeight) { _, _ in viewModel.save() }
        .onChange(of: viewModel.letterSpacing) { _, _ in viewModel.save() }
        .onChange(of: viewModel.paragraphSpacing) { _, _ in viewModel.save() }
        .onChange(of: viewModel.textIndent) { _, _ in viewModel.save() }
        .onChange(of: viewModel.sideMargin) { _, _ in viewModel.save() }
        .onChange(of: viewModel.topMargin) { _, _ in viewModel.save() }
        .onChange(of: viewModel.bottomMargin) { _, _ in viewModel.save() }
        .onChange(of: viewModel.customCSS) { _, _ in viewModel.save() }
        .onChange(of: viewModel.readingTheme) { _, _ in viewModel.save() }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section(String(localized: "common.preview")) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(previewBackground)
                    .shadow(color: Morandi.shadow, radius: 4, y: 2)

                VStack(alignment: .leading, spacing: viewModel.paragraphSpacing) {
                    Text("reader.chapter_title")
                        .font(.system(size: viewModel.defaultFontSize + 4, weight: .semibold))
                        .foregroundStyle(previewForeground)

                    Text(viewModel.textIndent ? indentedPreviewSentence : previewSentence)
                        .font(.system(size: viewModel.defaultFontSize))
                        .foregroundStyle(previewForeground)
                        .lineSpacing((viewModel.lineHeight - 1.0) * viewModel.defaultFontSize)
                        .tracking(viewModel.letterSpacing)

                    Text("settings.lorem")
                        .font(.system(size: viewModel.defaultFontSize))
                        .foregroundStyle(previewForeground)
                        .lineSpacing((viewModel.lineHeight - 1.0) * viewModel.defaultFontSize)
                        .tracking(viewModel.letterSpacing)
                }
                .padding(.horizontal, viewModel.sideMargin)
                .padding(.top, viewModel.topMargin)
                .padding(.bottom, viewModel.bottomMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var previewBackground: Color {
        Self.themes.first(where: { $0.id == viewModel.readingTheme })?.bg ?? Morandi.cardBackground
    }

    private var previewForeground: Color {
        Self.themes.first(where: { $0.id == viewModel.readingTheme })?.fg ?? Morandi.primaryText
    }

    private var systemFontFamilies: [String] {
        let extras = [
            "System",
            "Times New Roman",
            "Helvetica Neue",
            "Avenir",
            "Avenir Next",
            "Charter",
            "New York",
            "Menlo",
            "Courier New",
        ]
        return unique(BookStyle.preferredFontFamilies() + extras)
    }

    private var previewSentence: String {
        AppLocalization.string(
            "reader.appearance.preview_sentence",
            value: "The quick brown fox jumps over the lazy dog."
        )
    }

    private var indentedPreviewSentence: String {
        "    \(previewSentence)"
    }

    // MARK: - Font

    private var fontSection: some View {
        Section(String(localized: "reader.appearance.font")) {
            Picker(AppLocalization.string("reader.appearance.family", value: "Family"), selection: $viewModel.defaultFontFamily) {
                ForEach(systemFontFamilies, id: \.self) { Text($0).tag($0) }
            }
            .foregroundStyle(Morandi.primaryText)
            .onChange(of: viewModel.defaultFontFamily) { _, _ in viewModel.save() }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(format: NSLocalizedString("reader.font_size_pt_format", comment: ""), Int(viewModel.defaultFontSize)))
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                Slider(value: $viewModel.defaultFontSize, in: 12...32, step: 1)
                    .tint(Morandi.accent)
                    .onChange(of: viewModel.defaultFontSize) { _, _ in viewModel.save() }
            }
        }
    }

    // MARK: - Layout

    private var layoutSection: some View {
        Section(String(localized: "reader.appearance.layout")) {
            sliderRow(
                AppLocalization.string("reader.appearance.line_height", value: "Line Height"),
                value: $viewModel.lineHeight,
                range: 0.8...2.0,
                step: 0.05,
                format: "%.2f×"
            )
            sliderRow(
                AppLocalization.string("reader.appearance.letter_spacing", value: "Letter Spacing"),
                value: $viewModel.letterSpacing,
                range: -2...4,
                step: 0.1,
                format: "%.1f pt"
            )
            sliderRow(
                AppLocalization.string("reader.appearance.paragraph_spacing", value: "Paragraph Spacing"),
                value: $viewModel.paragraphSpacing,
                range: 0...24,
                step: 1,
                format: "%.0f pt"
            )
            Toggle(AppLocalization.string("reader.appearance.first_line_indent", value: "First-line Indent"), isOn: $viewModel.textIndent)
                .tint(Morandi.accent)
                .foregroundStyle(Morandi.primaryText)
        }
    }

    // MARK: - Margins

    private var marginSection: some View {
        Section(String(localized: "reader.appearance.margins")) {
            sliderRow(AppLocalization.string("reader.appearance.side_margin", value: "Side Margin"), value: $viewModel.sideMargin, range: 0...48, step: 1, format: "%.0f pt")
            sliderRow(AppLocalization.string("reader.appearance.top_margin", value: "Top Margin"), value: $viewModel.topMargin, range: 0...48, step: 1, format: "%.0f pt")
            sliderRow(AppLocalization.string("reader.appearance.bottom_margin", value: "Bottom Margin"), value: $viewModel.bottomMargin, range: 0...48, step: 1, format: "%.0f pt")
        }
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(label)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }
            Slider(value: value, in: range, step: step)
                .tint(Morandi.accent)
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        Section(String(localized: "settings.theme")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: AppSpacing.md) {
                ForEach(Self.themes, id: \.id) { theme in
                    Button {
                        viewModel.readingTheme = theme.id
                    } label: {
                        themeCard(theme.id, name: theme.name, bg: theme.bg, fg: theme.fg)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }

    @ViewBuilder
    private func themeCard(_ id: String, name: String, bg: Color, fg: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("reader.appearance.aa_label")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(fg)
            Text(name)
                .font(AppTypography.caption)
                .foregroundStyle(fg)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(AppSpacing.md)
        .background(RoundedRectangle(cornerRadius: 10).fill(bg))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(viewModel.readingTheme == id ? Morandi.accent : Morandi.divider, lineWidth: viewModel.readingTheme == id ? 2 : 1)
        )
    }

    // MARK: - Custom CSS

    private var customCSSSection: some View {
        Section {
            TextEditor(text: $viewModel.customCSS)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 120)
                .foregroundStyle(Morandi.primaryText)
        } header: {
            Text("reader.appearance.custom_css")
        } footer: {
            Text("reader.appearance.custom_css_hint")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.resetReadingDetail()
            } label: {
                Text("common.reset_to_defaults")
            }
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

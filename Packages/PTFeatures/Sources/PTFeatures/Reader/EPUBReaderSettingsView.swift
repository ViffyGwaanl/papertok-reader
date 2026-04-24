import SwiftUI
import Observation
import PTAIServices
import PTCore
import PTReader
import PTUI

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#endif

private enum EPUBReaderThemePreset: String, CaseIterable, Identifiable {
    case light
    case dark
    case sepia
    case night
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return AppLocalization.string("reader.appearance.theme_light")
        case .dark:
            return AppLocalization.string("reader.appearance.theme_dark")
        case .sepia:
            return AppLocalization.string("reader.appearance.theme_sepia")
        case .night:
            return AppLocalization.string("reader.theme.night")
        case .custom:
            return AppLocalization.string("reader.appearance.theme_custom")
        }
    }

    var theme: ReadTheme {
        switch self {
        case .light:
            return .defaultLight
        case .dark:
            return .defaultDark
        case .sepia:
            return .defaultSepia
        case .night:
            return .defaultNight
        case .custom:
            return .defaultLight
        }
    }

    static func resolve(from theme: ReadTheme) -> Self {
        if theme == .defaultLight {
            return .light
        }
        if theme == .defaultDark {
            return .dark
        }
        if theme == .defaultSepia {
            return .sepia
        }
        if theme == .defaultNight {
            return .night
        }
        return .custom
    }
}

@MainActor
public final class EPUBFulltextTranslationSettingsController {
    public let runtime: FulltextTranslationRuntime
    public let cache: FulltextTranslationCache
    public let onEnabledChanged: (Bool) async -> Void
    public let onTargetLanguageChanged: () async -> Void

    public init(
        runtime: FulltextTranslationRuntime,
        cache: FulltextTranslationCache,
        onEnabledChanged: @escaping (Bool) async -> Void = { _ in },
        onTargetLanguageChanged: @escaping () async -> Void = {}
    ) {
        self.runtime = runtime
        self.cache = cache
        self.onEnabledChanged = onEnabledChanged
        self.onTargetLanguageChanged = onTargetLanguageChanged
    }
}

public struct EPUBReaderSettingsView: View {
    @Bindable public var viewModel: EPUBReaderPreferencesViewModel

    private let onDone: () -> Void
    private let fulltextTranslationController: EPUBFulltextTranslationSettingsController?

    @State private var selectedThemePreset: EPUBReaderThemePreset
    @State private var showClearCacheConfirmation: Bool = false
    @State private var customFonts: [CustomFontDescriptor] = []

    public init(
        viewModel: EPUBReaderPreferencesViewModel,
        fulltextTranslationController: EPUBFulltextTranslationSettingsController? = nil,
        onDone: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.fulltextTranslationController = fulltextTranslationController
        self.onDone = onDone
        _selectedThemePreset = State(initialValue: EPUBReaderThemePreset.resolve(from: viewModel.readingPreferences.theme))
    }

    public var body: some View {
        NavigationStack {
            Form {
                previewSection
                typographySection
                customFontsSection
                spacingSection
                marginSection
                layoutSection
                writingDirectionSection
                readingInfoSection
                immersionSection
                themeSection
                if fulltextTranslationController != nil {
                    fulltextTranslationSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .task { await reloadCustomFonts() }
            .navigationTitle(String(localized: "reader.reader_settings"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done"), action: onDone)
                        .foregroundStyle(Morandi.accent)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: "common.reset")) {
                        Task {
                            await viewModel.resetToDefaults()
                            selectedThemePreset = .light
                        }
                    }
                    .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var previewSection: some View {
        Section(String(localized: "reader.settings.preview.section")) {
            let style = viewModel.readingPreferences.style
            let theme = viewModel.readingPreferences.theme
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("reader.settings.preview.sample_text"))
                    .font(previewFont(for: style))
                    .foregroundStyle(Color(hex: theme.textColor))
                    .lineSpacing(previewLineSpacing(for: style))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: theme.backgroundColor))
                    )
                    .accessibilityIdentifier("reader.settings.preview")
            }
            .listRowBackground(Morandi.background)
        }
    }

    private func previewFont(for style: BookStyle) -> Font {
        // Map the stored font-size multiplier (0.8...3.0) onto a compact
        // point size suitable for the inline preview card.
        let base: CGFloat = 15
        let size = base * CGFloat(style.fontSize)
        return Font.system(size: min(max(size, 11), 30))
    }

    private func previewLineSpacing(for style: BookStyle) -> CGFloat {
        // SwiftUI `lineSpacing` is *additional* spacing on top of the
        // font's intrinsic line height, so convert the ratio minus 1.0
        // into points.
        let base: CGFloat = 15
        let lineHeightPoints = base * CGFloat(style.lineHeight) * CGFloat(style.fontSize)
        let fontPoints = base * CGFloat(style.fontSize)
        return max(0, lineHeightPoints - fontPoints)
    }

    private var typographySection: some View {
        Section(String(localized: "reader.appearance.typography")) {
            sliderRow(
                title: AppLocalization.string("reader.appearance.font_size"),
                value: binding(
                    get: { viewModel.readingPreferences.style.fontSize },
                    set: { viewModel.readingPreferences.style.fontSize = $0 }
                ),
                range: 0.8...3.0,
                step: 0.1,
                format: "%.1f"
            )

            Picker(
                AppLocalization.string("reader.appearance.font_family"),
                selection: binding(
                    get: { viewModel.readingPreferences.style.fontFamily },
                    set: { viewModel.readingPreferences.style.fontFamily = $0 }
                )
            ) {
                ForEach(fontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }

            Picker(
                AppLocalization.string("reader.appearance.text_alignment"),
                selection: binding(
                    get: { viewModel.readingPreferences.textAlignment },
                    set: { viewModel.readingPreferences.textAlignment = $0 }
                )
            ) {
                Text("reader.appearance.left").tag(PTReader.TextAlignment.left)
                Text("reader.appearance.center").tag(PTReader.TextAlignment.center)
                Text("reader.appearance.right").tag(PTReader.TextAlignment.right)
                Text("reader.appearance.justify").tag(PTReader.TextAlignment.justify)
            }
        }
    }

    private var spacingSection: some View {
        Section(String(localized: "reader.appearance.spacing")) {
            sliderRow(
                title: AppLocalization.string("reader.appearance.line_height"),
                value: binding(
                    get: { viewModel.readingPreferences.style.lineHeight },
                    set: { viewModel.readingPreferences.style.lineHeight = $0 }
                ),
                range: 1.0...2.0,
                step: 0.05,
                format: "%.2f"
            )

            sliderRow(
                title: AppLocalization.string("reader.appearance.letter_spacing"),
                value: binding(
                    get: { viewModel.readingPreferences.style.letterSpacing },
                    set: { viewModel.readingPreferences.style.letterSpacing = $0 }
                ),
                range: 0...1.0,
                step: 0.05,
                format: "%.2f"
            )

            sliderRow(
                title: AppLocalization.string("reader.settings.spacing.word"),
                value: binding(
                    get: { viewModel.readingPreferences.style.wordSpacing },
                    set: { viewModel.readingPreferences.style.wordSpacing = $0 }
                ),
                range: 0...1.0,
                step: 0.05,
                format: "%.2f"
            )

            sliderRow(
                title: AppLocalization.string("reader.settings.spacing.paragraph"),
                value: binding(
                    get: { viewModel.readingPreferences.style.paragraphSpacing },
                    set: { viewModel.readingPreferences.style.paragraphSpacing = $0 }
                ),
                range: 0...3.0,
                step: 0.1,
                format: "%.1f"
            )
        }
    }

    private var marginSection: some View {
        Section {
            sliderRow(
                title: AppLocalization.string("reader.appearance.side_margin"),
                value: binding(
                    get: { viewModel.readingPreferences.style.sideMargin },
                    set: { viewModel.readingPreferences.style.sideMargin = $0 }
                ),
                range: 0...12,
                step: 0.25,
                format: "%.2f"
            )

            sliderRow(
                title: AppLocalization.string("reader.settings.margins.top"),
                value: binding(
                    get: { viewModel.readingPreferences.style.topMargin },
                    set: { viewModel.readingPreferences.style.topMargin = $0 }
                ),
                range: 0...140,
                step: 2,
                format: "%.0f pt"
            )

            sliderRow(
                title: AppLocalization.string("reader.settings.margins.bottom"),
                value: binding(
                    get: { viewModel.readingPreferences.style.bottomMargin },
                    set: { viewModel.readingPreferences.style.bottomMargin = $0 }
                ),
                range: 0...140,
                step: 2,
                format: "%.0f pt"
            )
        } header: {
            Text("reader.appearance.layout")
        } footer: {
            Text("reader.appearance.margin_hint")
        }
    }

    private var layoutSection: some View {
        Section(String(localized: "reader.settings.layout.section")) {
            Picker(
                AppLocalization.string("reader.appearance.page_turn"),
                selection: binding(
                    get: { viewModel.readingPreferences.pageTurnMode },
                    set: { viewModel.readingPreferences.pageTurnMode = $0 }
                )
            ) {
                Text("reader.appearance.swipe").tag(PageTurnMode.swipe)
                Text("reader.appearance.tap").tag(PageTurnMode.tap)
                Text("reader.appearance.scroll").tag(PageTurnMode.scroll)
            }

            Picker(
                AppLocalization.string("reader.settings.layout.column_count"),
                selection: binding(
                    get: { viewModel.readingPreferences.style.maxColumnCount },
                    set: { viewModel.readingPreferences.style.maxColumnCount = $0 }
                )
            ) {
                Text(AppLocalization.string("reader.settings.layout.column_count.auto"))
                    .tag(BookStyle.ColumnCount.auto)
                Text(AppLocalization.string("reader.settings.layout.column_count.single"))
                    .tag(BookStyle.ColumnCount.single)
                Text(AppLocalization.string("reader.settings.layout.column_count.double"))
                    .tag(BookStyle.ColumnCount.double)
            }

            sliderRow(
                title: AppLocalization.string("reader.settings.layout.column_threshold"),
                value: binding(
                    get: { viewModel.readingPreferences.style.columnThreshold },
                    set: { viewModel.readingPreferences.style.columnThreshold = $0 }
                ),
                range: 400...1200,
                step: 25,
                format: "%.0f px"
            )
        }
    }

    private var writingDirectionSection: some View {
        Section {
            Picker(
                AppLocalization.string("reader.settings.layout.writing_mode"),
                selection: binding(
                    get: { viewModel.readingPreferences.style.writingMode },
                    set: { viewModel.readingPreferences.style.writingMode = $0 }
                )
            ) {
                Text(AppLocalization.string("reader.settings.layout.writing_mode.auto"))
                    .tag(BookStyle.WritingMode.auto)
                Text(AppLocalization.string("reader.settings.layout.writing_mode.horizontal"))
                    .tag(BookStyle.WritingMode.horizontalTb)
                Text(AppLocalization.string("reader.settings.layout.writing_mode.vertical"))
                    .tag(BookStyle.WritingMode.verticalRl)
            }
        } header: {
            Text(AppLocalization.string("reader.settings.layout.writing_mode"))
        }
    }

    private var readingInfoSection: some View {
        Section(String(localized: "reader.settings.reading_info.section")) {
            readingInfoPicker(
                title: AppLocalization.string("reader.settings.reading_info.top_left"),
                keyPath: \.topLeft
            )
            readingInfoPicker(
                title: AppLocalization.string("reader.settings.reading_info.top_center"),
                keyPath: \.topCenter
            )
            readingInfoPicker(
                title: AppLocalization.string("reader.settings.reading_info.top_right"),
                keyPath: \.topRight
            )
            readingInfoPicker(
                title: AppLocalization.string("reader.settings.reading_info.bottom_left"),
                keyPath: \.bottomLeft
            )
            readingInfoPicker(
                title: AppLocalization.string("reader.settings.reading_info.bottom_center"),
                keyPath: \.bottomCenter
            )
            readingInfoPicker(
                title: AppLocalization.string("reader.settings.reading_info.bottom_right"),
                keyPath: \.bottomRight
            )

            Button {
                viewModel.readingPreferences.style.readingInfo = .default
                persist()
            } label: {
                Text(AppLocalization.string("reader.settings.reading_info.reset"))
                    .foregroundStyle(Morandi.accent)
            }
        }
    }

    // MARK: - W7.1 Immersion section

    private var immersionSection: some View {
        Section(String(localized: "reader.settings.immersion.section")) {
            let current = viewModel.readingPreferences.style.autoHideChromeSeconds
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("reader.settings.immersion.auto_hide_seconds"))
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)

                Text(AppLocalization.format(
                    "reader.settings.immersion.auto_hide_seconds.hint_format",
                    locale: .autoupdatingCurrent,
                    current
                ))
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
                .monospacedDigit()

                Slider(
                    value: binding(
                        get: { viewModel.readingPreferences.style.autoHideChromeSeconds },
                        set: { viewModel.readingPreferences.style.autoHideChromeSeconds = $0 }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(Morandi.accent)
            }
        }
    }

    private func readingInfoPicker(
        title: String,
        keyPath: WritableKeyPath<ReadingInfoLayout, ReadingInfoField>
    ) -> some View {
        Picker(
            title,
            selection: binding(
                get: { viewModel.readingPreferences.style.readingInfo[keyPath: keyPath] },
                set: { viewModel.readingPreferences.style.readingInfo[keyPath: keyPath] = $0 }
            )
        ) {
            ForEach(ReadingInfoField.allCases, id: \.rawValue) { field in
                Text(EPUBReaderSettingsView.readingInfoFieldLabel(field))
                    .tag(field)
            }
        }
    }

    static func readingInfoFieldLabel(_ field: ReadingInfoField) -> String {
        switch field {
        case .nothing:
            return AppLocalization.string("reader.settings.reading_info.field.nothing")
        case .chapterTitle:
            return AppLocalization.string("reader.settings.reading_info.field.chapter")
        case .pageNumber:
            return AppLocalization.string("reader.settings.reading_info.field.page_number")
        case .progressPercentage:
            return AppLocalization.string("reader.settings.reading_info.field.progress")
        case .readingTime:
            return AppLocalization.string("reader.settings.reading_info.field.reading_time")
        case .batteryLevel:
            return AppLocalization.string("reader.settings.reading_info.field.battery")
        case .clock:
            return AppLocalization.string("reader.settings.reading_info.field.clock")
        }
    }

    private var themeSection: some View {
        Section(String(localized: "settings.theme")) {
            let activeKind = ThemeSwatchPreset.active(for: viewModel.readingPreferences.theme)?.kind
            ThemeSwatchPickerRow(
                activeKind: activeKind,
                onSelect: { preset in
                    viewModel.readingPreferences.theme = preset.theme
                    selectedThemePreset = EPUBReaderThemePreset.resolve(from: preset.theme)
                    persist()
                }
            )
            .listRowBackground(Morandi.background)

            ColorPicker(
                AppLocalization.string("reader.appearance.background"),
                selection: colorBinding(
                    get: { viewModel.readingPreferences.theme.backgroundColor },
                    set: { viewModel.readingPreferences.theme.backgroundColor = $0 }
                )
            )

            ColorPicker(
                AppLocalization.string("reader.appearance.text"),
                selection: colorBinding(
                    get: { viewModel.readingPreferences.theme.textColor },
                    set: { viewModel.readingPreferences.theme.textColor = $0 }
                )
            )
        }
    }

    @ViewBuilder
    private var fulltextTranslationSection: some View {
        if let controller = fulltextTranslationController {
            Section(String(localized: "reader.translation.fulltext.section.title")) {
                Toggle(
                    String(localized: "reader.translation.fulltext.enable"),
                    isOn: Binding(
                        get: { controller.runtime.isEnabled },
                        set: { newValue in
                            Task { @MainActor in
                                await controller.runtime.setEnabled(newValue)
                                await controller.onEnabledChanged(newValue)
                            }
                        }
                    )
                )
                .tint(Morandi.accent)

                Picker(
                    String(localized: "reader.translation.fulltext.target_language"),
                    selection: Binding(
                        get: { controller.runtime.targetLanguage },
                        set: { newValue in
                            Task { @MainActor in
                                await controller.runtime.setTargetLanguage(newValue)
                                await controller.onTargetLanguageChanged()
                            }
                        }
                    )
                ) {
                    ForEach(["zh-Hans", "zh-Hant", "en", "ja"], id: \.self) { code in
                        Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                    }
                }

                if controller.runtime.isEnabled, controller.runtime.totalCount > 0 {
                    fulltextTranslationStatusRows(runtime: controller.runtime)
                }

                if controller.runtime.hasFailures {
                    Button(role: .destructive) {
                        controller.runtime.retryFailedParagraphs()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(String(localized: "reader.translation.fulltext.retry_failed"))
                        }
                    }
                    .accessibilityIdentifier("reader.translation.fulltext.retry_failed")
                }

                concurrencyRow(runtime: controller.runtime)

                Button(role: .destructive) {
                    showClearCacheConfirmation = true
                } label: {
                    Text(String(localized: "reader.translation.fulltext.clear_cache"))
                }
                .confirmationDialog(
                    String(localized: "reader.translation.fulltext.clear_cache.confirm.title"),
                    isPresented: $showClearCacheConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "common.confirm"), role: .destructive) {
                        Task { await controller.cache.purge() }
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "reader.translation.fulltext.clear_cache.confirm.message"))
                }
            }
        }
    }

    @ViewBuilder
    private func fulltextTranslationStatusRows(runtime: FulltextTranslationRuntime) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            let inFlight = runtime.inFlightCount
            let total = runtime.totalCount
            let progressText = AppLocalization.format(
                "reader.translation.fulltext.status.progress_format",
                inFlight,
                total
            )
            Text(progressText)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)

            let readyText = AppLocalization.format(
                "reader.translation.fulltext.status.ready_format",
                runtime.readyCount
            )
            Text(readyText)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)

            if runtime.failedCount > 0 {
                let failedText = AppLocalization.format(
                    "reader.translation.fulltext.status.failed_format",
                    runtime.failedCount
                )
                Text(failedText)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("reader.translation.fulltext.status.failed")
            }
        }
    }

    @ViewBuilder
    private func concurrencyRow(runtime: FulltextTranslationRuntime) -> some View {
        let binding = Binding<Double>(
            get: { Double(runtime.maxConcurrency) },
            set: { runtime.setMaxConcurrency(Int($0)) }
        )
        let label = AppLocalization.string("reader.translation.fulltext.concurrency")
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("\(label): \(runtime.maxConcurrency)")
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.primaryText)
            Slider(value: binding, in: 1...8, step: 1)
                .tint(Morandi.accent)
                .accessibilityIdentifier("reader.translation.fulltext.concurrency.slider")
        }
    }

    private var fontFamilies: [String] {
        var result = BookStyle.preferredFontFamilies()
        var seen = Set(result)
        for custom in customFonts {
            if seen.insert(custom.displayName).inserted {
                result.append(custom.displayName)
            }
        }
        return result
    }

    @ViewBuilder
    private var customFontsSection: some View {
        Section {
            NavigationLink {
                CustomFontPicker(
                    viewModel: CustomFontPickerViewModel(registry: CustomFontRegistryProvider.shared)
                )
                .task { await reloadCustomFonts() }
            } label: {
                HStack {
                    Text("reader.fonts.custom.section_title")
                    Spacer()
                    Text("\(customFonts.count)")
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
    }

    private func reloadCustomFonts() async {
        customFonts = await CustomFontRegistryProvider.shared.list()
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("\(title): \(String(format: format, value.wrappedValue))")
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.primaryText)

            Slider(value: value, in: range, step: step)
                .tint(Morandi.accent)
        }
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: get,
            set: { newValue in
                set(newValue)
                syncBehaviorFlags()
                persist()
            }
        )
    }

    private func colorBinding(
        get: @escaping () -> String,
        set: @escaping (String) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { Color(hex: normalizeHex(get())) },
            set: { color in
                set(hexString(from: color))
                selectedThemePreset = .custom
                persist()
            }
        )
    }

    private func syncBehaviorFlags() {
        viewModel.readingPreferences.isScrollMode = viewModel.readingPreferences.pageTurnMode == .scroll
        selectedThemePreset = EPUBReaderThemePreset.resolve(from: viewModel.readingPreferences.theme)
    }

    private func persist() {
        Task {
            await viewModel.save()
        }
    }

    private func normalizeHex(_ rawHex: String) -> String {
        let trimmed = rawHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        switch trimmed.count {
        case 8:
            return trimmed
        case 6:
            return "FF\(trimmed)"
        default:
            return "FFFBFBF3"
        }
    }

    private func hexString(from color: Color) -> String {
#if canImport(UIKit)
        let platformColor = PlatformColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "FFFBFBF3"
        }
        return String(
            format: "%02X%02X%02X%02X",
            Int(alpha * 255),
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
#elseif canImport(AppKit)
        let platformColor = PlatformColor(color)
        let resolved = platformColor.usingColorSpace(.deviceRGB) ?? .white
        return String(
            format: "%02X%02X%02X%02X",
            Int(resolved.alphaComponent * 255),
            Int(resolved.redComponent * 255),
            Int(resolved.greenComponent * 255),
            Int(resolved.blueComponent * 255)
        )
#else
        return "FFFBFBF3"
#endif
    }
}

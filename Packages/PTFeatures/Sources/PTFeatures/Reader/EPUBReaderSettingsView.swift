import SwiftUI
import Observation
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
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .sepia: "Sepia"
        case .custom: "Custom"
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
        return .custom
    }
}

public struct EPUBReaderSettingsView: View {
    @Bindable public var viewModel: EPUBReaderPreferencesViewModel

    private let onDone: () -> Void

    @State private var selectedThemePreset: EPUBReaderThemePreset

    public init(
        viewModel: EPUBReaderPreferencesViewModel,
        onDone: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onDone = onDone
        _selectedThemePreset = State(initialValue: EPUBReaderThemePreset.resolve(from: viewModel.readingPreferences.theme))
    }

    public var body: some View {
        NavigationStack {
            Form {
                typographySection
                spacingSection
                layoutSection
                themeSection
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle("Reader Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                        .foregroundStyle(Morandi.accent)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
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

    private var typographySection: some View {
        Section("Typography") {
            sliderRow(
                title: "Font Size",
                value: binding(
                    get: { viewModel.readingPreferences.style.fontSize },
                    set: { viewModel.readingPreferences.style.fontSize = $0 }
                ),
                range: 0.8...3.0,
                step: 0.1,
                format: "%.1f"
            )

            Picker(
                "Font Family",
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
                "Text Alignment",
                selection: binding(
                    get: { viewModel.readingPreferences.textAlignment },
                    set: { viewModel.readingPreferences.textAlignment = $0 }
                )
            ) {
                Text("Left").tag(PTReader.TextAlignment.left)
                Text("Center").tag(PTReader.TextAlignment.center)
                Text("Right").tag(PTReader.TextAlignment.right)
                Text("Justify").tag(PTReader.TextAlignment.justify)
            }
        }
    }

    private var spacingSection: some View {
        Section("Spacing") {
            sliderRow(
                title: "Line Height",
                value: binding(
                    get: { viewModel.readingPreferences.style.lineHeight },
                    set: { viewModel.readingPreferences.style.lineHeight = $0 }
                ),
                range: 1.0...2.0,
                step: 0.05,
                format: "%.2f"
            )

            sliderRow(
                title: "Letter Spacing",
                value: binding(
                    get: { viewModel.readingPreferences.style.letterSpacing },
                    set: { viewModel.readingPreferences.style.letterSpacing = $0 }
                ),
                range: 0...1.0,
                step: 0.05,
                format: "%.2f"
            )

            sliderRow(
                title: "Word Spacing",
                value: binding(
                    get: { viewModel.readingPreferences.style.wordSpacing },
                    set: { viewModel.readingPreferences.style.wordSpacing = $0 }
                ),
                range: 0...1.0,
                step: 0.05,
                format: "%.2f"
            )

            sliderRow(
                title: "Paragraph Spacing",
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

    private var layoutSection: some View {
        Section {
            Picker(
                "Page Turn",
                selection: binding(
                    get: { viewModel.readingPreferences.pageTurnMode },
                    set: { viewModel.readingPreferences.pageTurnMode = $0 }
                )
            ) {
                Text("Swipe").tag(PageTurnMode.swipe)
                Text("Tap").tag(PageTurnMode.tap)
                Text("Scroll").tag(PageTurnMode.scroll)
            }

            sliderRow(
                title: "Side Margin",
                value: binding(
                    get: { viewModel.readingPreferences.style.sideMargin },
                    set: { viewModel.readingPreferences.style.sideMargin = $0 }
                ),
                range: 0...12,
                step: 0.25,
                format: "%.2f"
            )

            sliderRow(
                title: "Top Margin",
                value: binding(
                    get: { viewModel.readingPreferences.style.topMargin },
                    set: { viewModel.readingPreferences.style.topMargin = $0 }
                ),
                range: 0...140,
                step: 2,
                format: "%.0f pt"
            )

            sliderRow(
                title: "Bottom Margin",
                value: binding(
                    get: { viewModel.readingPreferences.style.bottomMargin },
                    set: { viewModel.readingPreferences.style.bottomMargin = $0 }
                ),
                range: 0...140,
                step: 2,
                format: "%.0f pt"
            )
        } header: {
            Text("Layout")
        } footer: {
            Text("Top and bottom margins are applied as reader chrome insets. Center alignment may fall back to leading in the EPUB engine.")
        }
    }

    private var themeSection: some View {
        Section("Theme") {
            Picker("Preset", selection: $selectedThemePreset) {
                ForEach(EPUBReaderThemePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .onChange(of: selectedThemePreset) { _, newValue in
                guard newValue != .custom else { return }
                viewModel.readingPreferences.theme = newValue.theme
                persist()
            }

            ColorPicker(
                "Background",
                selection: colorBinding(
                    get: { viewModel.readingPreferences.theme.backgroundColor },
                    set: { viewModel.readingPreferences.theme.backgroundColor = $0 }
                )
            )

            ColorPicker(
                "Text",
                selection: colorBinding(
                    get: { viewModel.readingPreferences.theme.textColor },
                    set: { viewModel.readingPreferences.theme.textColor = $0 }
                )
            )
        }
    }

    private var fontFamilies: [String] {
        [
            "Arial",
            "Georgia",
            "Palatino",
            "Iowan Old Style",
            "Source Han Serif SC"
        ]
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

import SwiftUI
import PTCore
import PTUI

/// Logical description of a built-in reader theme swatch. Decoupled from
/// the SwiftUI view so it can be unit-tested and shared between EPUB and
/// PDF reader settings.
public struct ThemeSwatchPreset: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case light
        case sepia
        case dark
        case night
    }

    public let kind: Kind
    public let theme: ReadTheme
    public let titleKey: String

    public var id: String { kind.rawValue }

    public init(kind: Kind, theme: ReadTheme, titleKey: String) {
        self.kind = kind
        self.theme = theme
        self.titleKey = titleKey
    }

    /// Display order used by the horizontal swatch row: light → sepia →
    /// dark → night. Night sits at the end because it is the most
    /// specialised / immersive preset.
    public static let allPresets: [ThemeSwatchPreset] = [
        ThemeSwatchPreset(kind: .light, theme: .defaultLight, titleKey: "reader.appearance.theme_light"),
        ThemeSwatchPreset(kind: .sepia, theme: .defaultSepia, titleKey: "reader.appearance.theme_sepia"),
        ThemeSwatchPreset(kind: .dark, theme: .defaultDark, titleKey: "reader.appearance.theme_dark"),
        ThemeSwatchPreset(kind: .night, theme: .defaultNight, titleKey: "reader.theme.night"),
    ]

    /// Returns the preset whose built-in theme matches `theme` by value.
    /// Custom / user-edited themes resolve to `nil`, which callers should
    /// render as "no active swatch" (no border).
    public static func active(for theme: ReadTheme) -> ThemeSwatchPreset? {
        allPresets.first { preset in
            preset.theme.backgroundColor == theme.backgroundColor
                && preset.theme.textColor == theme.textColor
                && preset.theme.backgroundImagePath == theme.backgroundImagePath
        }
    }
}

/// Horizontal row of visual theme swatch cards used in reader settings.
/// Each card previews the theme's background + text colour with a small
/// "Aa" sample. Tapping a swatch applies the associated preset.
struct ThemeSwatchPickerRow: View {
    let activeKind: ThemeSwatchPreset.Kind?
    let onSelect: (ThemeSwatchPreset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(ThemeSwatchPreset.allPresets) { preset in
                    swatchCard(for: preset)
                }
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }

    @ViewBuilder
    private func swatchCard(for preset: ThemeSwatchPreset) -> some View {
        let isActive = preset.kind == activeKind
        Button {
            onSelect(preset)
        } label: {
            VStack(spacing: AppSpacing.xxs) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: preset.theme.backgroundColor))
                    Text("reader.appearance.aa_label")
                        .font(.title2)
                        .foregroundStyle(Color(hex: preset.theme.textColor))
                }
                .frame(width: 56, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Morandi.accent, lineWidth: isActive ? 2.5 : 0)
                )

                Text(LocalizedStringKey(preset.titleKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(preset.titleKey)))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

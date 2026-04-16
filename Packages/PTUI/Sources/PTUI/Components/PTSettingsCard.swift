import SwiftUI

/// A styled card for settings rows with an icon, title, subtitle, and optional trailing accessory.
/// Mirrors the Apple Settings app card style using the Morandi palette.
public struct PTSettingsCard<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let trailing: Trailing

    public init(
        icon: String,
        iconColor: Color = Morandi.primaryText,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(AppTypography.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }

            Spacer()

            trailing
        }
        .padding(AppSpacing.lg)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .ptShadow(level: 1)
    }
}

// MARK: - Test Hooks

extension PTSettingsCard {
    struct TestHooks {
        let icon: String
        let iconColor: Color
        let hasSubtitle: Bool
    }

    var testHooks: TestHooks {
        TestHooks(icon: icon, iconColor: iconColor, hasSubtitle: subtitle != nil)
    }
}

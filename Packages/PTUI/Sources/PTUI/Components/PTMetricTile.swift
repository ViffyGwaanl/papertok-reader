import SwiftUI

/// A small tile showing a number + label, used in dashboards (usage stats, reading stats).
/// Morandi background, large number, small label below.
public struct PTMetricTile: View {
    let value: String
    let label: LocalizedStringKey
    let color: Color

    public init(value: String, label: LocalizedStringKey, color: Color = Morandi.accent) {
        self.value = value
        self.label = label
        self.color = color
    }

    public var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(value)
                .font(AppTypography.title)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .ptShadow(level: 1)
    }
}

// MARK: - Test Hooks

extension PTMetricTile {
    struct TestHooks {
        let value: String
    }

    var testHooks: TestHooks {
        TestHooks(value: value)
    }
}

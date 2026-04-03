import SwiftUI

public struct PTButton: View {
    public enum Style { case primary, secondary, destructive, ghost }
    let title: String; let style: Style; let action: () -> Void

    public init(_ title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title; self.style = style; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title).font(AppTypography.headline)
                .frame(maxWidth: style == .ghost ? nil : .infinity)
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: .white; case .secondary: Morandi.accent
        case .destructive: .white; case .ghost: Morandi.accent
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: Morandi.accent; case .secondary: Morandi.accent.opacity(0.12)
        case .destructive: Morandi.destructive; case .ghost: .clear
        }
    }
}

import SwiftUI

public struct PTCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content.padding(AppSpacing.lg)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius, y: 2)
    }
}

public struct PTSectionHeaderModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content.font(AppTypography.subheadline)
            .foregroundStyle(Morandi.secondaryText)
            .textCase(.uppercase).tracking(0.5)
    }
}

extension View {
    public func ptCard() -> some View { modifier(PTCardModifier()) }
    public func ptSectionHeader() -> some View { modifier(PTSectionHeaderModifier()) }
    public func ptDivider() -> some View {
        self.overlay(alignment: .bottom) { Morandi.divider.frame(height: 0.5) }
    }
}

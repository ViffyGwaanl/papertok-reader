import SwiftUI

public struct PTChip: View {
    let title: String; let isSelected: Bool; let action: () -> Void

    public init(_ title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.isSelected = isSelected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title).font(AppTypography.subheadline)
                .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : Morandi.secondaryText)
        .background(isSelected ? Morandi.accent : Morandi.divider.opacity(0.5), in: Capsule())
    }
}

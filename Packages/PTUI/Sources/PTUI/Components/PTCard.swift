import SwiftUI

public struct PTCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(AppSpacing.lg)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius, y: 2)
    }
}

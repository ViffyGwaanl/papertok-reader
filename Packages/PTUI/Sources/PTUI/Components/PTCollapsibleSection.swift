import SwiftUI

/// A section with a header that toggles expanded/collapsed state with animated disclosure.
public struct PTCollapsibleSection<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    let content: Content

    public init(
        title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(Morandi.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, AppSpacing.md)
                .padding(.horizontal, AppSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .ptShadow(level: 1)
    }
}

// MARK: - Test Hooks

extension PTCollapsibleSection {
    struct TestHooks {
        let isExpanded: Bool
    }

    var testHooks: TestHooks {
        TestHooks(isExpanded: isExpanded)
    }
}

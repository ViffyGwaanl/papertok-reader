import SwiftUI

/// A styled sheet/dialog container with Morandi background, rounded corners, and standard
/// cancel/confirm button bar. Reusable as the root of any sheet.
public struct PTDialogShell<Content: View>: View {
    let title: LocalizedStringKey
    let onCancel: () -> Void
    let onConfirm: (() -> Void)?
    let confirmLabel: LocalizedStringKey
    let content: Content

    public init(
        title: LocalizedStringKey,
        onCancel: @escaping () -> Void,
        onConfirm: (() -> Void)? = nil,
        confirmLabel: LocalizedStringKey = "common.confirm",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.confirmLabel = confirmLabel
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Title bar
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)

            Divider().overlay(Morandi.divider)

            // Content area
            content
                .padding(AppSpacing.lg)

            Divider().overlay(Morandi.divider)

            // Button bar
            HStack(spacing: AppSpacing.md) {
                Button {
                    onCancel()
                } label: {
                    Text("common.cancel")
                        .font(AppTypography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Morandi.secondaryText)

                if let onConfirm {
                    Divider().frame(height: 44)
                    Button {
                        onConfirm()
                    } label: {
                        Text(confirmLabel)
                            .font(AppTypography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Morandi.accent)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .ptShadow(level: 2)
        .padding(AppSpacing.xl)
    }
}

// MARK: - Test Hooks

extension PTDialogShell {
    struct TestHooks {
        let hasConfirm: Bool
    }

    var testHooks: TestHooks {
        TestHooks(hasConfirm: onConfirm != nil)
    }
}

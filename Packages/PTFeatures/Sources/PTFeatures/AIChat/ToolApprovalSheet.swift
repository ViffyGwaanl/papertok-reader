import SwiftUI
import PTAIServices
import PTUI

/// Modal sheet asking user to approve or deny a dangerous tool call.
///
/// Shown for tools with riskLevel == .dangerous (calendar writes, reminders writes, shortcuts).
struct ToolApprovalSheet: View {
    let toolName: String
    let arguments: String
    let onApprove: () -> Void
    let onDeny: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Label(String(localized: "ai.tool_call_approval"), systemImage: "exclamationmark.triangle.fill")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.clay)
                .padding(.top, AppSpacing.sm)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("ai.tool_name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Morandi.secondaryText)
                Text(AIToolPresentation.displayName(for: toolName))
                    .font(AppTypography.mono)
                    .foregroundStyle(Morandi.primaryText)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Morandi.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("ai.mcp.arguments")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Morandi.secondaryText)
                ScrollView {
                    Text(arguments)
                        .font(.caption.monospaced())
                        .foregroundStyle(Morandi.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(AppSpacing.sm)
                .background(Morandi.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
            }

            Text("ai.tool_write_warning")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)

            HStack(spacing: AppSpacing.md) {
                Button {
                    onDeny()
                    dismiss()
                } label: {
                    Text("common.deny")
                        .font(AppTypography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                }
                .background(Morandi.destructive.opacity(0.15))
                .foregroundStyle(Morandi.destructive)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))

                Button {
                    onApprove()
                    dismiss()
                } label: {
                    Text("common.allow")
                        .font(AppTypography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                }
                .background(Morandi.sage.opacity(0.15))
                .foregroundStyle(Morandi.sage)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
            }
        }
        .padding(AppSpacing.xl)
        .background(Morandi.background)
        .presentationDetents([.medium])
    }
}

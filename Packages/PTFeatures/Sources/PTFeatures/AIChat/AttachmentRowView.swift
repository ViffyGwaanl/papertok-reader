import SwiftUI
import PTUI

/// Horizontal row showing attached files/images with remove button.
///
/// Displayed above the chat input when user attaches files before sending.
struct AttachmentRowView: View {
    let attachments: [AIChatViewModel.Attachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(attachments) { attachment in
                        attachmentChip(attachment)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }

    private func attachmentChip(_ attachment: AIChatViewModel.Attachment) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: attachment.type == .image ? "photo" : "doc")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.accent)

            Text(attachment.name)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.primaryText)
                .lineLimit(1)

            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            Capsule()
                .fill(Morandi.cardBackground)
                .strokeBorder(Morandi.divider, lineWidth: 0.5)
        )
    }
}

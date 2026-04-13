import SwiftUI
import PTUI
#if os(iOS)
import UIKit
#endif

/// Horizontal strip of 80x80 attachment thumbnails with circular remove buttons.
struct AttachmentThumbnailStrip: View {
    let attachments: [AIChatViewModel.Attachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(attachments) { att in
                    AttachmentThumbnail(attachment: att, onRemove: { onRemove(att.id) })
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 96)
    }
}

struct AttachmentThumbnail: View {
    let attachment: AIChatViewModel.Attachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch attachment.type {
                case .image:
                    #if os(iOS)
                    if let img = UIImage(data: attachment.data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        fileIcon
                    }
                    #else
                    if let img = NSImage(data: attachment.data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        fileIcon
                    }
                    #endif
                case .file:
                    fileIcon
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Morandi.divider, lineWidth: 0.5)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
        }
    }

    private var fileIcon: some View {
        VStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .font(.system(size: 28))
                .foregroundStyle(Morandi.accent)
            Text(attachment.name)
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
        }
        .frame(width: 80, height: 80)
        .background(Morandi.elevatedBackground)
    }
}

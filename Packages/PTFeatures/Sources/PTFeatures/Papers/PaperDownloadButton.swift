import SwiftUI
import PTNetworking
import PTUI

/// Download button showing idle, progress, and completion states for a paper's PDF.
public struct PaperDownloadButton: View {
    let detail: PaperTokDetail
    @Binding var progress: Double? // nil = idle, 0.0-1.0 = downloading, 1.0 = done
    let onDownload: () -> Void
    let onCancel: () -> Void

    public var body: some View {
        Group {
            if let p = progress {
                if p >= 1.0 {
                    Label("Imported", systemImage: "checkmark.circle.fill")
                        .font(AppTypography.subheadline.weight(.medium))
                        .foregroundStyle(Morandi.sage)
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView(value: p)
                            .tint(Morandi.accent)
                            .frame(width: 80)
                        Text("\(Int(p * 100))%")
                            .font(AppTypography.caption.monospacedDigit())
                            .foregroundStyle(Morandi.secondaryText)
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(Morandi.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: AppSpacing.sm) {
                    if detail.pdfUrl != nil {
                        Button(action: onDownload) {
                            Label("Download PDF", systemImage: "arrow.down.circle")
                                .font(AppTypography.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Morandi.accent)
                    }

                    if let urlString = detail.url, URL(string: urlString) != nil {
                        Link(destination: URL(string: urlString)!) {
                            Label("View Original", systemImage: "safari")
                                .font(AppTypography.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(Morandi.secondaryText)
                    }
                }
            }
        }
    }
}

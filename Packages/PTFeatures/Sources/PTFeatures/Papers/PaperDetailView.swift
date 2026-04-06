import SwiftUI
import PTNetworking
import PTUI

/// Bottom sheet showing full paper detail: images, title, abstract, and download button.
struct PaperDetailView: View {
    let paperId: Int
    let isLiked: Bool
    let onToggleLike: () -> Void

    @State private var detail: PaperTokDetail?
    @State private var isLoading = true
    @State private var downloadProgress: Double?
    @Environment(\.dismiss) private var dismiss

    private let api = PaperTokAPI()

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("Loading...")
                        .tint(Morandi.accent)
                        .padding(AppSpacing.xxxl)
                        .frame(maxWidth: .infinity)
                } else if let detail {
                    detailContent(detail)
                } else {
                    ContentUnavailableView(
                        "Failed to load",
                        systemImage: "exclamationmark.triangle"
                    )
                    .padding(AppSpacing.xxxl)
                }
            }
            .background(Morandi.background)
            .navigationTitle("Paper Detail")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Morandi.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onToggleLike) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? Morandi.accent : Morandi.secondaryText)
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .task { await loadDetail() }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(_ detail: PaperTokDetail) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Image carousel
            if !detail.carouselImages.isEmpty {
                TabView {
                    ForEach(detail.carouselImages, id: \.self) { imageURL in
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Morandi.divider
                        }
                        .frame(maxHeight: 200)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page)
                #endif
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            }

            // Title
            let displayTitle = detail.displayTitle ?? detail.title
            Text(displayTitle)
                .font(AppTypography.title3.weight(.semibold))
                .foregroundStyle(Morandi.primaryText)

            // One-liner
            if let oneLiner = detail.oneLiner, !oneLiner.isEmpty {
                Text(oneLiner)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.secondaryText)
            }

            // Abstract / explanation
            if let explain = detail.contentExplain, !explain.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Abstract")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(Morandi.secondaryText)
                    Text(explain)
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                }
                .padding(AppSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Morandi.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
            }

            // Download button
            PaperDownloadButton(
                detail: detail,
                progress: $downloadProgress,
                onDownload: { Task { await startDownload(detail) } },
                onCancel: { downloadProgress = nil }
            )
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Network

    private func loadDetail() async {
        isLoading = true
        detail = try? await api.fetchPaperDetail(id: paperId, language: "zh")
        isLoading = false
    }

    private func startDownload(_ detail: PaperTokDetail) async {
        guard let urlString = detail.pdfUrl, let url = URL(string: urlString) else { return }
        downloadProgress = 0.0
        do {
            let (_, _) = try await URLSession.shared.download(from: url)
            // TODO: Phase 12 -- import downloaded file to bookshelf via BookService
            downloadProgress = 1.0
        } catch {
            downloadProgress = nil
        }
    }
}

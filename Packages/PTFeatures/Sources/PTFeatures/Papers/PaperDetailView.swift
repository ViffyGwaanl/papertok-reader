import SwiftUI
import PTCore
import PTNetworking
import PTUI

struct PaperDetailDataLoader {
    let api: any PaperTokAPIProtocol

    func load(paperId: Int, language: String) async -> PaperTokDetail? {
        try? await api.fetchPaperDetail(id: paperId, language: language)
    }
}

/// Bottom sheet showing full paper detail: images, title, abstract, and download button.
struct PaperDetailView: View {
    let database: AppDatabase
    let paperId: Int
    let language: String
    let isLiked: Bool
    let onToggleLike: () -> Void
    let api: any PaperTokAPIProtocol

    @State private var detail: PaperTokDetail?
    @State private var isLoading = true
    @State private var downloadStatus: PaperDownloadStatus = .idle(plan: nil)
    @State private var activeDownloadID: UUID?
    @State private var downloadTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(
        database: AppDatabase,
        paperId: Int,
        language: String,
        isLiked: Bool,
        onToggleLike: @escaping () -> Void,
        api: any PaperTokAPIProtocol = PaperTokAPI()
    ) {
        self.database = database
        self.paperId = paperId
        self.language = language
        self.isLiked = isLiked
        self.onToggleLike = onToggleLike
        self.api = api
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView(String(localized: "common.loading_ellipsis"))
                        .tint(Morandi.accent)
                        .padding(AppSpacing.xxxl)
                        .frame(maxWidth: .infinity)
                } else if let detail {
                    detailContent(detail)
                } else {
                    ContentUnavailableView(
                        String(localized: "common.failed_to_load"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .padding(AppSpacing.xxxl)
                }
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "papers.paper_detail"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) { dismiss() }
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
        .onDisappear {
            downloadTask?.cancel()
            downloadTask = nil
            activeDownloadID = nil
        }
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

            detailMetadata(detail)
            detailNarrative(detail)

            // Download button
            PaperDownloadButton(
                detail: detail,
                status: downloadStatus,
                onDownload: { beginDownload(detail) },
                onRetry: { beginDownload(detail) },
                onCancel: { cancelDownload(detail) }
            )
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Network

    private func loadDetail() async {
        isLoading = true
        detail = await PaperDetailDataLoader(api: api).load(paperId: paperId, language: language)
        if let detail {
            downloadStatus = .idle(plan: PaperDownloadPlan(detail: detail))
        } else {
            downloadStatus = .failed(message: String(localized: "errors.papers.detail_unavailable"), plan: nil)
        }
        isLoading = false
    }

    private func beginDownload(_ detail: PaperTokDetail) {
        downloadTask?.cancel()
        let downloadID = UUID()
        activeDownloadID = downloadID
        downloadTask = Task {
            await startDownload(detail, downloadID: downloadID)
        }
    }

    private func cancelDownload(_ detail: PaperTokDetail) {
        activeDownloadID = nil
        downloadTask?.cancel()
        downloadTask = nil
        downloadStatus = .idle(plan: PaperDownloadPlan(detail: detail))
    }

    private func startDownload(_ detail: PaperTokDetail, downloadID: UUID) async {
        guard let plan = PaperDownloadPlan(detail: detail) else {
            downloadStatus = .failed(message: String(localized: "errors.papers.no_downloadable_file"), plan: nil)
            return
        }

        guard activeDownloadID == downloadID else { return }
        downloadStatus = .downloading(
            plan: plan,
            phase: .downloading,
            progress: .init(receivedBytes: 0, totalBytes: nil)
        )
        do {
            try await PaperDownloadWorker(
                importer: BookImportService(database: database)
            ).run(plan: plan) { status in
                await MainActor.run {
                    guard activeDownloadID == downloadID else { return }
                    downloadStatus = status
                }
            }
        } catch is CancellationError {
            guard activeDownloadID == downloadID else { return }
            downloadStatus = .idle(plan: plan)
        } catch {
            guard activeDownloadID == downloadID else { return }
            downloadStatus = .failed(message: error.localizedDescription, plan: plan)
        }

        if activeDownloadID == downloadID {
            activeDownloadID = nil
            downloadTask = nil
        }
    }

    @ViewBuilder
    private func detailMetadata(_ detail: PaperTokDetail) -> some View {
        let metadataItems = metadataItems(for: detail)
        if metadataItems.isEmpty == false {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("bookshelf.metadata")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(Morandi.secondaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: AppSpacing.sm)], spacing: AppSpacing.sm) {
                    ForEach(metadataItems, id: \.label) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label.uppercased())
                                .font(AppTypography.caption2.weight(.semibold))
                                .foregroundStyle(Morandi.tertiaryText)
                            Text(item.value)
                                .font(AppTypography.subheadline)
                                .foregroundStyle(Morandi.primaryText)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                        .background(Morandi.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailNarrative(_ detail: PaperTokDetail) -> some View {
        if let explain = detail.preferredExplanation(language: language) {
            detailTextSection(title: String(localized: "papers.explanation"), content: explain)
        }

        if let dialogue = detail.preferredDialogue(language: language) {
            detailTextSection(title: String(localized: "papers.dialogue"), content: dialogue)
        }
    }

    private func detailTextSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(Morandi.secondaryText)
            Text(content)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
    }

    private func metadataItems(for detail: PaperTokDetail) -> [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        if let day = detail.day, day.isEmpty == false {
            items.append((String(localized: "papers.metadata.date"), day))
        }
        if let source = detail.source, source.isEmpty == false {
            items.append((String(localized: "papers.metadata.source"), source))
        }
        if let externalId = detail.externalId, externalId.isEmpty == false {
            items.append((String(localized: "papers.metadata.external_id"), externalId))
        }
        if let updatedAt = detail.updatedAt {
            items.append((String(localized: "papers.metadata.updated"), updatedAt.formatted(date: .abbreviated, time: .omitted)))
        }

        return items
    }
}

import SwiftUI
import PTCore
import PTNetworking
import PTUI

/// Main Papers tab view -- vertical paged card feed of academic papers.
public struct PapersView: View {
    let database: AppDatabase
    @State private var viewModel = PapersViewModel()
    @State private var selectedCard: PaperTokCard?
    @State private var currentIndex = 0

    public init(database: AppDatabase) {
        self.database = database
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PapersFilterBar(
                    searchQuery: $viewModel.searchQuery,
                    likedOnly: $viewModel.likedOnly,
                    dayFilter: Binding(
                        get: { viewModel.dayFilter },
                        set: { newValue in Task { await viewModel.applyDayFilter(newValue) } }
                    ),
                    language: Binding(
                        get: { viewModel.language },
                        set: { newValue in Task { await viewModel.applyLanguage(newValue) } }
                    ),
                    customDate: Binding(
                        get: { viewModel.customDate },
                        set: { newValue in
                            guard let newValue else { return }
                            Task { await viewModel.applyCustomDate(newValue) }
                        }
                    ),
                    onRefresh: { Task { await viewModel.loadMore(reset: true) } }
                )
                .padding(.horizontal, AppSpacing.lg)

                if viewModel.visibleCards.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    cardFeed
                }
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "papers.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task { await viewModel.loadMore(reset: true) }
        .sheet(item: $selectedCard) { card in
            PaperDetailView(
                database: database,
                paperId: card.id,
                language: viewModel.language,
                isLiked: viewModel.isLiked(card),
                onToggleLike: { viewModel.toggleLike(card) }
            )
        }
    }

    // MARK: - Card Feed

    private var cardFeed: some View {
        GeometryReader { geo in
            TabView(selection: $currentIndex) {
                ForEach(viewModel.visibleCards.indices, id: \.self) { i in
                    let card = viewModel.visibleCards[i]
                    PaperCardView(
                        card: card,
                        isLiked: viewModel.isLiked(card),
                        onLike: { viewModel.toggleLike(card) },
                        onTap: { selectedCard = card }
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .tag(i)
                    .onAppear {
                        if i >= viewModel.visibleCards.count - 3 {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }

                if viewModel.isLoading {
                    VStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .tint(Morandi.accent)
                        Text("common.loading")
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    .tag(viewModel.visibleCards.count)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: geo.size.height)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(Morandi.tertiaryText)
            Text(viewModel.error != nil ? "Failed to Load" : "No Papers")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.secondaryText)
            if let error = viewModel.error {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)
            }
            Button(String(localized: "common.retry")) { Task { await viewModel.loadMore(reset: true) } }
                .buttonStyle(.bordered)
                .tint(Morandi.accent)
            Spacer()
        }
    }
}

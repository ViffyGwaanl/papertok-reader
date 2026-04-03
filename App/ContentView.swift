import SwiftUI
import PTFeatures

/// Main tab navigation view using AppTab and Morandi design system.
struct MainTabView: View {
    let database: AppDatabase
    @State private var selectedTab: AppTab = .bookshelf

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.defaultOrder) { tab in
                tab.destination(database: database)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tint(Morandi.accent)
    }
}

// MARK: - Tab Destinations

extension AppTab {
    @ViewBuilder
    func destination(database: AppDatabase) -> some View {
        switch self {
        case .papers:
            PapersPlaceholderView()
        case .bookshelf:
            BookshelfScreen(database: database)
        case .notes:
            NotesPlaceholderView()
        case .statistics:
            StatisticsPlaceholderView()
        case .ai:
            AIChatPlaceholderView()
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

// MARK: - Bookshelf Screen (first real screen)

struct BookshelfScreen: View {
    @State private var viewModel: BookshelfViewModel

    init(database: AppDatabase) {
        _viewModel = State(initialValue: BookshelfViewModel(database: database))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.books.isEmpty {
                    ContentUnavailableView(
                        "No Books Yet",
                        systemImage: "books.vertical",
                        description: Text("Import EPUB or PDF files to get started.")
                    )
                } else {
                    List(viewModel.books) { book in
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(book.title)
                                    .font(AppTypography.headline)
                                    .foregroundStyle(Morandi.primaryText)
                                if !book.author.isEmpty {
                                    Text(book.author)
                                        .font(AppTypography.subheadline)
                                        .foregroundStyle(Morandi.secondaryText)
                                }
                            }
                            Spacer()
                            Text("\(Int(book.readingPercentage * 100))%")
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.accent)
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }
                }
            }
            .navigationTitle("Bookshelf")
            .searchable(text: $viewModel.searchQuery, prompt: "Search books")
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.loadBooks() }
            }
            .task {
                await viewModel.loadBooks()
            }
        }
    }
}

// MARK: - Placeholder Views (to be implemented)

struct PapersPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Papers", systemImage: "doc.text.magnifyingglass", description: Text("Academic paper feed coming soon."))
                .navigationTitle("Papers")
        }
    }
}

struct NotesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Notes", systemImage: "note.text", description: Text("Your reading notes will appear here."))
                .navigationTitle("Notes")
        }
    }
}

struct StatisticsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Statistics", systemImage: "chart.bar", description: Text("Reading statistics coming soon."))
                .navigationTitle("Statistics")
        }
    }
}

struct AIChatPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("AI Assistant", systemImage: "sparkles", description: Text("AI-powered reading assistant coming soon."))
                .navigationTitle("AI")
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Settings", systemImage: "gearshape", description: Text("App settings coming soon."))
                .navigationTitle("Settings")
        }
    }
}

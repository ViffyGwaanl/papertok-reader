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
            PapersView()
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

// MARK: - Bookshelf Screen

struct BookshelfScreen: View {
    let database: AppDatabase
    @State private var viewModel: BookshelfViewModel
    @State private var showImporter = false
    @State private var showImportError = false

    init(database: AppDatabase) {
        self.database = database
        _viewModel = State(initialValue: BookshelfViewModel(database: database))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(Morandi.accent)
                } else if viewModel.books.isEmpty {
                    ContentUnavailableView(
                        "No Books Yet",
                        systemImage: "books.vertical",
                        description: Text("Tap + to import a PDF file.")
                    )
                } else {
                    bookList
                }
            }
            .background(Morandi.background)
            .navigationTitle("Bookshelf")
            .searchable(text: $viewModel.searchQuery, prompt: "Search books")
            .toolbar { toolbarItems }
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.loadBooks() }
            }
            .task { await viewModel.loadBooks() }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    await viewModel.importBook(url: url)
                    if viewModel.importError != nil { showImportError = true }
                }
            }
            .alert(
                "Import Failed",
                isPresented: $showImportError,
                presenting: viewModel.importError
            ) { _ in
                Button("OK") { viewModel.importError = nil }
            } message: { error in
                Text(error.errorDescription ?? "Unknown error")
            }
            .overlay {
                if viewModel.isImporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: AppSpacing.md) {
                            ProgressView()
                                .tint(Morandi.accent)
                            Text("Importing…")
                                .font(AppTypography.subheadline)
                                .foregroundStyle(Morandi.secondaryText)
                        }
                        .padding(AppSpacing.xl)
                        .background(Morandi.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    }
                }
            }
        }
    }

    // MARK: - Book list

    private var bookList: some View {
        List(viewModel.books) { book in
            NavigationLink {
                PDFReaderView(book: book, database: database)
                    .navigationBarBackButtonHidden(true)
            } label: {
                bookRow(book)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if let id = book.id {
                        Task { await viewModel.deleteBook(id: id) }
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .listRowBackground(Morandi.background)
        }
        .listStyle(.plain)
        .background(Morandi.background)
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .fill(Morandi.sand.opacity(0.6))
                .frame(width: 44, height: 60)
                .overlay(
                    Image(systemName: "doc.text")
                        .foregroundStyle(Morandi.warmGray)
                )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(book.title)
                    .font(AppTypography.headline)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(1)
                }
                if book.readingPercentage > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Morandi.divider
                                .frame(height: 3)
                                .clipShape(Capsule())
                            Morandi.accent
                                .frame(width: geo.size.width * book.readingPercentage, height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            Text("\(Int(book.readingPercentage * 100))%")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.accent)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Morandi.accent)
            }
            .disabled(viewModel.isImporting)
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

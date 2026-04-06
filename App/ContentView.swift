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
            NotesScreen(database: database)
        case .statistics:
            StatisticsScreen(database: database)
        case .ai:
            AIChatPlaceholderView()
        case .settings:
            SettingsScreen()
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

// MARK: - Notes Screen

struct NotesScreen: View {
    let database: AppDatabase
    @State private var viewModel: NotesViewModel

    init(database: AppDatabase) {
        self.database = database
        _viewModel = State(initialValue: NotesViewModel(database: database))
    }

    /// Group notes by book title (using bookId as key fallback).
    private var groupedNotes: [(bookId: Int64, notes: [BookNote])] {
        let filtered = viewModel.notes
        let grouped = Dictionary(grouping: filtered) { $0.bookId }
        return grouped
            .map { (bookId: $0.key, notes: $0.value) }
            .sorted { ($0.notes.first?.createTime ?? .distantPast) > ($1.notes.first?.createTime ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(Morandi.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Morandi.background)
                } else if viewModel.notes.isEmpty {
                    ContentUnavailableView(
                        viewModel.searchQuery.isEmpty ? "No Notes Yet" : "No Results",
                        systemImage: viewModel.searchQuery.isEmpty ? "note.text" : "magnifyingglass",
                        description: Text(viewModel.searchQuery.isEmpty
                            ? "Highlight text while reading to create notes."
                            : "No notes match your search.")
                    )
                    .background(Morandi.background)
                } else {
                    notesList
                }
            }
            .background(Morandi.background)
            .navigationTitle("Notes")
            .searchable(text: $viewModel.searchQuery, prompt: "Search notes")
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.loadNotes() }
            }
            .task { await viewModel.loadNotes() }
        }
    }

    private var notesList: some View {
        List {
            ForEach(groupedNotes, id: \.bookId) { group in
                Section {
                    ForEach(group.notes) { note in
                        noteRow(note)
                            .listRowBackground(Morandi.background)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let id = note.id {
                                        Task { await viewModel.deleteNote(id: id) }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Morandi.destructive)
                            }
                    }
                } header: {
                    Text("Book #\(group.bookId)")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .listStyle(.plain)
        .background(Morandi.background)
    }

    private func noteRow(_ note: BookNote) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Color indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(highlightColor(for: note.color))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(note.content)
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(3)

                if !note.chapter.isEmpty {
                    Text(note.chapter)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(1)
                }

                if let readerNote = note.readerNote, !readerNote.isEmpty {
                    Text(readerNote)
                        .font(AppTypography.footnote)
                        .foregroundStyle(Morandi.accent)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func highlightColor(for colorName: String) -> Color {
        switch colorName.lowercased() {
        case "yellow": return Morandi.highlightYellow
        case "red": return Morandi.highlightRed
        case "blue": return Morandi.highlightBlue
        case "green": return Morandi.highlightGreen
        case "purple": return Morandi.highlightPurple
        default: return Morandi.accent
        }
    }
}

// MARK: - Statistics Screen

struct StatisticsScreen: View {
    let database: AppDatabase
    @State private var viewModel: StatisticsViewModel

    init(database: AppDatabase) {
        self.database = database
        _viewModel = State(initialValue: StatisticsViewModel(database: database))
    }

    private let heatmapColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Generate the 91-day date list for the heatmap, aligned to start on Monday.
    private var heatmapDates: [String] {
        let calendar = Calendar(identifier: .iso8601)
        let today = Date()
        // Go back 90 days
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: today) else { return [] }
        // Align to the previous Monday
        let weekday = calendar.component(.weekday, from: startDate)
        // ISO: Monday = 2, Sunday = 1
        let daysToSubtract = (weekday == 1) ? 6 : weekday - 2
        guard let alignedStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: startDate) else { return [] }

        var dates: [String] = []
        var current = alignedStart
        while current <= today {
            dates.append(DateFormatting.dateOnly.string(from: current))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        return dates
    }

    private var maxMinutes: Int {
        max(viewModel.dailyReadingData.values.max() ?? 1, 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Stat cards
                    statCardsSection

                    // Heatmap
                    heatmapSection
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle("Statistics")
            .task { await viewModel.loadStats() }
        }
    }

    // MARK: - Stat Cards

    private var statCardsSection: some View {
        HStack(spacing: AppSpacing.md) {
            statCard(title: "Reading Time", value: viewModel.formattedReadingTime, icon: "clock")
            statCard(title: "Books", value: "\(viewModel.totalBooks)", icon: "books.vertical")
            statCard(title: "Notes", value: "\(viewModel.totalNotes)", icon: "note.text")
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppTypography.title2)
                .foregroundStyle(Morandi.accent)

            Text(value)
                .font(AppTypography.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Morandi.primaryText)
                .monospacedDigit()

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius)
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Reading Activity")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            HStack(alignment: .top, spacing: AppSpacing.sm) {
                // Weekday labels
                VStack(spacing: 3) {
                    ForEach(Self.weekdayLabels, id: \.self) { label in
                        Text(label)
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.secondaryText)
                            .frame(height: 14)
                    }
                }

                // Grid
                LazyVGrid(columns: heatmapColumns, spacing: 3) {
                    ForEach(heatmapDates, id: \.self) { date in
                        let minutes = viewModel.dailyReadingData[date] ?? 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatmapColor(minutes: minutes))
                            .frame(height: 14)
                            .help("\(date): \(minutes)m")
                    }
                }
            }

            // Legend
            heatmapLegend
        }
        .padding(AppSpacing.lg)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius)
    }

    private func heatmapColor(minutes: Int) -> Color {
        guard minutes > 0 else {
            return Morandi.divider
        }
        let intensity = min(Double(minutes) / Double(maxMinutes), 1.0)
        let clamped = max(intensity, 0.2)
        return Morandi.accent.opacity(clamped)
    }

    private var heatmapLegend: some View {
        HStack(spacing: AppSpacing.xs) {
            Text("Less")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.secondaryText)

            ForEach([0.0, 0.2, 0.4, 0.7, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? Morandi.divider : Morandi.accent.opacity(max(level, 0.2)))
                    .frame(width: 14, height: 14)
            }

            Text("More")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.secondaryText)
        }
    }
}

// MARK: - Settings Screen

struct SettingsScreen: View {
    @State private var viewModel = SettingsViewModel()

    private let themeModes = ["system", "light", "dark"]
    private let pageTurnModes = ["swipe", "scroll"]

    var body: some View {
        NavigationStack {
            Form {
                // Appearance
                Section {
                    Picker("Theme", selection: $viewModel.themeMode) {
                        ForEach(themeModes, id: \.self) { mode in
                            Text(mode.capitalized).tag(mode)
                        }
                    }
                    .foregroundStyle(Morandi.primaryText)

                    Toggle("OLED Dark Mode", isOn: $viewModel.isOLEDDarkMode)
                        .tint(Morandi.accent)
                        .foregroundStyle(Morandi.primaryText)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Accent Color")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(Morandi.primaryText)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: AppSpacing.sm) {
                            ForEach(Array(Morandi.accentPresets.enumerated()), id: \.offset) { index, preset in
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if viewModel.accentColorIndex == index {
                                            Circle()
                                                .strokeBorder(Morandi.primaryText, lineWidth: 2.5)
                                        }
                                    }
                                    .onTapGesture {
                                        viewModel.accentColorIndex = index
                                        viewModel.save()
                                    }
                                    .accessibilityLabel(preset.name)
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                } header: {
                    Text("Appearance")
                }

                // Reading
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Default Font Size: \(Int(viewModel.defaultFontSize))")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(Morandi.primaryText)
                        Slider(value: $viewModel.defaultFontSize, in: 12...32, step: 1)
                            .tint(Morandi.accent)
                    }

                    Picker("Page Turn Mode", selection: $viewModel.pageTurnMode) {
                        ForEach(pageTurnModes, id: \.self) { mode in
                            Text(mode.capitalized).tag(mode)
                        }
                    }
                    .foregroundStyle(Morandi.primaryText)
                } header: {
                    Text("Reading")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(Morandi.secondaryText)
                    }

                    Link(destination: URL(string: "https://github.com/ArcticFoxPro/PaperTok")!) {
                        HStack {
                            Text("Open Source")
                                .foregroundStyle(Morandi.primaryText)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.accent)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle("Settings")
            .onChange(of: viewModel.themeMode) { _, _ in viewModel.save() }
            .onChange(of: viewModel.isOLEDDarkMode) { _, _ in viewModel.save() }
            .onChange(of: viewModel.defaultFontSize) { _, _ in viewModel.save() }
            .onChange(of: viewModel.pageTurnMode) { _, _ in viewModel.save() }
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


import SwiftUI
import UniformTypeIdentifiers
import PTCore
import PTFeatures
import PTAIServices
#if canImport(ReadiumShared)
import ReadiumShared
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Main tab navigation view using AppTab and Morandi design system.
struct MainTabView: View {
    let database: AppDatabase
    let calendarService: any CalendarServiceProtocol
    let remindersService: any RemindersServiceProtocol

    @State private var navigation = RootNavigationCoordinator()
    @State private var readerSessionStore: ReaderSessionContextStore
    @State private var aiChatViewModel: AIChatViewModel

    init(
        database: AppDatabase,
        calendarService: any CalendarServiceProtocol,
        remindersService: any RemindersServiceProtocol
    ) {
        self.database = database
        self.calendarService = calendarService
        self.remindersService = remindersService
        let readerSessionStore = ReaderSessionContextStore()
        _readerSessionStore = State(initialValue: readerSessionStore)

        let toolContext: ToolContext
        do {
            toolContext = try AppAIToolContextFactory.make(
                database: database,
                calendarService: calendarService,
                remindersService: remindersService,
                readerSessionStore: readerSessionStore
            )
        } catch {
            assertionFailure("Failed to prepare AI tool context: \(error.localizedDescription)")
            toolContext = ToolContext(
                database: database,
                calendarService: calendarService,
                remindersService: remindersService,
                readerSessionStore: readerSessionStore
            )
        }

        let runtime = AIChatViewModel.Runtime(
            providers: AIChatViewModel.Runtime.default.providers,
            toolRegistry: .default,
            toolContext: toolContext
        )
        _aiChatViewModel = State(initialValue: AIChatViewModel(runtime: runtime))
    }

    var body: some View {
        Group {
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadSplitLayout
            } else {
                iPhoneTabLayout
            }
#else
            iPadSplitLayout
#endif
        }
        .tint(Morandi.accent)
        .handleDeepLinks(navigation: navigation)
    }

    private var iPhoneTabLayout: some View {
        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.defaultOrder) { tab in
                destination(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
    }

    private var iPadSplitLayout: some View {
        NavigationSplitView {
            List(selection: $navigation.optionalSelectedTab) {
                ForEach(AppTab.defaultOrder) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .navigationTitle("PaperTok")
            .listStyle(.sidebar)
        } detail: {
            destination(for: navigation.selectedTab)
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .papers:
            PapersView(database: database)
        case .bookshelf:
            BookshelfScreen(
                database: database,
                openRequest: $navigation.pendingBookRequest,
                sharedInboxImportRequest: $navigation.sharedInboxImportRequest,
                readerSessionStore: readerSessionStore,
                aiChatViewModel: aiChatViewModel
            )
        case .notes:
            NotesScreen(database: database)
        case .statistics:
            StatisticsScreen(database: database)
        case .ai:
            NavigationStack {
                AIChatView(viewModel: aiChatViewModel)
                    .task(id: navigation.pendingAIRequest?.id) {
                        await handlePendingAIRequestIfNeeded()
                    }
            }
        case .settings:
            SettingsScreen()
        }
    }

    private func handlePendingAIRequestIfNeeded() async {
        guard let pendingAIRequest = navigation.pendingAIRequest else { return }
        navigation.pendingAIRequest = nil

        if let shareEventID = pendingAIRequest.shareEventID {
            guard let event = SharedInbox.loadEvent(id: shareEventID) else {
                aiChatViewModel.errorMessage = String(localized: "share.error.content_unavailable")
                return
            }

            guard event.route == .aiChat || event.route == .ask else {
                aiChatViewModel.errorMessage = String(localized: "share.error.route_requires_bookshelf")
                return
            }

            aiChatViewModel.clearAttachments()
            for item in event.fileItems where item.kind == .image {
                let url = SharedInbox.fileURL(for: item, eventID: event.id)
                if let data = try? Data(contentsOf: url) {
                    aiChatViewModel.addAttachment(.init(type: .image, name: item.filename, data: data))
                }
            }

            let sharedText = composeSharedAIMessage(event: event)
            let prompt = pendingAIRequest.message ?? sharedText
            let didSend = await aiChatViewModel.sendMessage(prompt)
            guard didSend else { return }

            SharedInbox.consume(eventID: event.id)
            await IntentsDonationService.donateAskAI(question: prompt)
            return
        }

        guard let message = pendingAIRequest.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              message.isEmpty == false else {
            return
        }

        let didSend = await aiChatViewModel.sendMessage(message)
        guard didSend else { return }
        await IntentsDonationService.donateAskAI(question: message)
    }

    private func composeSharedAIMessage(event: SharedInboxEvent) -> String {
        let segments = (event.text + event.urls).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        if segments.isEmpty == false {
            return segments.joined(separator: "\n\n")
        }
        if event.fileItems.contains(where: { $0.kind == .image }) {
            return String(localized: "share.ai_prompt.image_analysis")
        }
        return String(localized: "share.ai_prompt.content_analysis")
    }
}

// MARK: - Bookshelf Screen

struct BookshelfScreen: View {
    let database: AppDatabase
    let readerSessionStore: ReaderSessionContextStore?
    let aiChatViewModel: AIChatViewModel

    @Binding private var openRequest: BookshelfOpenRequest?
    @Binding private var sharedInboxImportRequest: SharedInboxImportRequest?
    @AppStorage("bookshelf.displayMode") private var displayModeRawValue = BookshelfDisplayMode.grid.rawValue
    @State private var viewModel: BookshelfViewModel
    @State private var navigationBook: Book?
    @State private var showImporter = false
    @State private var showImportError = false
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var presentedSheet: BookshelfSheet?
    @State private var showBatchMoveSheet = false

    private enum BookshelfDisplayMode: String {
        case grid
        case list

        var title: String {
            switch self {
            case .grid: "Grid"
            case .list: "List"
            }
        }

        var icon: String {
            switch self {
            case .grid: "square.grid.2x2"
            case .list: "list.bullet"
            }
        }
    }

    private enum BookshelfSheet: Identifiable {
        case manageTags
        case manageGroups
        case editBook(Book)

        var id: String {
            switch self {
            case .manageTags:
                "manage-tags"
            case .manageGroups:
                "manage-groups"
            case .editBook(let book):
                "edit-book-\(book.id ?? -1)"
            }
        }
    }

    init(
        database: AppDatabase,
        openRequest: Binding<BookshelfOpenRequest?> = .constant(nil),
        sharedInboxImportRequest: Binding<SharedInboxImportRequest?> = .constant(nil),
        readerSessionStore: ReaderSessionContextStore? = nil,
        aiChatViewModel: AIChatViewModel
    ) {
        self.database = database
        self.readerSessionStore = readerSessionStore
        self.aiChatViewModel = aiChatViewModel
        self._openRequest = openRequest
        self._sharedInboxImportRequest = sharedInboxImportRequest
        _viewModel = State(initialValue: BookshelfViewModel(database: database))
    }

    var body: some View {
        NavigationStack {
            bookshelfContent
        }
    }

    private var displayMode: BookshelfDisplayMode {
        get { BookshelfDisplayMode(rawValue: displayModeRawValue) ?? .grid }
        nonmutating set { displayModeRawValue = newValue.rawValue }
    }

    // MARK: - Book list

    private var bookList: some View {
        List(viewModel.books) { book in
            NavigationLink {
                readerDestination(for: book)
            } label: {
                bookRow(book)
            }
            .simultaneousGesture(TapGesture().onEnded {
                Task {
                    await IntentsDonationService.donateOpenBook(title: book.title)
                }
            })
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    handleDelete(book)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    navigationBook = book
                } label: {
                    Label("Open", systemImage: "book")
                }

                Button {
                    presentedSheet = .editBook(book)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                bookshelfMoveGroupMenu(for: book)
                bookshelfTagMenu(for: book)

                ShareLink(item: URL(fileURLWithPath: book.filePath)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    handleDelete(book)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .listRowBackground(Morandi.background)
        }
        .listStyle(.plain)
        .background(Morandi.background)
    }

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: AppSpacing.lg, alignment: .top)],
                spacing: AppSpacing.lg
            ) {
                ForEach(viewModel.books) { book in
                    if viewModel.isEditMode {
                        bookGridCard(book)
                            .overlay(alignment: .topLeading) {
                                editModeCheckmark(for: book)
                            }
                            .onTapGesture {
                                if let id = book.id {
                                    viewModel.toggleBookSelection(id)
                                }
                            }
                    } else {
                    NavigationLink {
                        readerDestination(for: book)
                    } label: {
                        bookGridCard(book)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        Task {
                            await IntentsDonationService.donateOpenBook(title: book.title)
                        }
                    })
                    .contextMenu {
                        Button {
                            navigationBook = book
                        } label: {
                            Label("Open", systemImage: "book")
                        }

                        Button {
                            presentedSheet = .editBook(book)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        bookshelfMoveGroupMenu(for: book)
                        bookshelfTagMenu(for: book)

                        ShareLink(item: URL(fileURLWithPath: book.filePath)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            handleDelete(book)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
        .background(Morandi.background)
    }

    @ViewBuilder
    private func editModeCheckmark(for book: Book) -> some View {
        let isSelected = book.id.map { viewModel.selectedBookIDs.contains($0) } ?? false
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Morandi.accent : Morandi.tertiaryText)
            .padding(AppSpacing.sm)
    }

    @ViewBuilder
    private var bookshelfCollection: some View {
        switch displayMode {
        case .grid:
            bookGrid
        case .list:
            bookList
        }
    }

    private var bookshelfContent: some View {
        let base = VStack(spacing: 0) {
            if viewModel.isEditMode {
                editModeBanner
            }
            bookshelfFilters
            bookshelfStateView
        }
        .background(Morandi.background)
        .navigationTitle("Bookshelf")
        .searchable(text: $viewModel.searchQuery, prompt: "Search books")
        .toolbar { toolbarItems }
        .navigationDestination(isPresented: navigationPresentation) {
            if let navigationBook {
                readerDestination(for: navigationBook)
            }
        }

        return attachImportPresentation(to: attachLifecycleHandlers(to: base))
    }

    private var editModeBanner: some View {
        HStack(spacing: AppSpacing.md) {
            Text("\(viewModel.selectedBookIDs.count) selected")
                .font(AppTypography.subheadline.weight(.medium))
                .foregroundStyle(Morandi.primaryText)

            Spacer()

            Button {
                viewModel.selectAllBooks()
            } label: {
                Text("Select All")
                    .font(AppTypography.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Morandi.accent)

            Menu {
                Button {
                    showBatchMoveSheet = true
                } label: {
                    Label("Move to Group", systemImage: "folder")
                }

                Button(role: .destructive) {
                    Task {
                        await viewModel.batchDeleteSelectedBooks()
                        viewModel.toggleEditMode()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Morandi.accent)
            }
            .disabled(viewModel.selectedBookIDs.isEmpty)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(Morandi.cardBackground)
    }

    @ViewBuilder
    private var bookshelfStateView: some View {
        if viewModel.isLoading {
            ProgressView()
                .tint(Morandi.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.books.isEmpty {
            ContentUnavailableView(
                "No Books Yet",
                systemImage: "books.vertical",
                description: Text("Tap + to import a PDF or EPUB file.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            bookshelfCollection
        }
    }

    private var bookshelfFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    presentedSheet = .manageTags
                } label: {
                    Label("Tags", systemImage: "slider.horizontal.3")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(Morandi.primaryText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(Morandi.cardBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(BookshelfViewModel.ReadingStatusFilter.allCases, id: \.self) { filter in
                    PTChip(filter.title, isSelected: viewModel.selectedStatusFilters.contains(filter)) {
                        viewModel.toggleStatusFilter(filter)
                        Task { await viewModel.loadBooks() }
                    }
                }

                Divider()
                    .frame(height: 18)

                PTChip("No Tag", isSelected: viewModel.includeNoTagFilter) {
                    viewModel.toggleNoTagFilter()
                    Task { await viewModel.loadBooks() }
                }

                ForEach(viewModel.tags) { tag in
                    if let tagID = tag.id {
                        PTChip(tag.name, isSelected: viewModel.selectedTagIDs.contains(tagID)) {
                            viewModel.toggleTagFilter(tagID)
                            Task { await viewModel.loadBooks() }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
        .background(Morandi.background)
    }

    private var importOverlay: some View {
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

    private var navigationPresentation: Binding<Bool> {
        Binding(
            get: { navigationBook != nil },
            set: { isPresented in
                if isPresented == false {
                    navigationBook = nil
                }
            }
        )
    }

    private func attachLifecycleHandlers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.loadBooks() }
            }
            .onDisappear {
                undoDismissTask?.cancel()
            }
            .task {
                await viewModel.loadBooks()
                await viewModel.loadTags()
                await viewModel.loadGroups()
                await handleOpenRequestIfNeeded()
            }
            .onChange(of: openRequest) { _, _ in
                Task { await handleOpenRequestIfNeeded() }
            }
            .onChange(of: sharedInboxImportRequest) { _, _ in
                Task { await handleExternalImportRequestIfNeeded() }
            }
    }

    private func attachImportPresentation<Content: View>(to content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf, .epub],
                allowsMultipleSelection: false,
                onCompletion: handleImportSelection
            )
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .manageTags:
                    BookshelfTagManagerSheet(viewModel: viewModel)
                case .manageGroups:
                    BookshelfGroupManagerSheet(viewModel: viewModel)
                case .editBook(let book):
                    BookshelfBookEditorSheet(viewModel: viewModel, book: book)
                }
            }
            .sheet(isPresented: $showBatchMoveSheet) {
                BookshelfBatchMoveSheet(viewModel: viewModel, onDone: {
                    showBatchMoveSheet = false
                    viewModel.toggleEditMode()
                })
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
                    importOverlay
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let pendingUndoBook = viewModel.pendingUndoBook {
                    undoBanner(for: pendingUndoBook)
                }
            }
    }

    @ViewBuilder
    private func readerDestination(for book: Book) -> some View {
        if book.filePath.lowercased().hasSuffix(".epub") {
#if canImport(ReadiumShared)
            EPUBBookshelfReaderView(
                book: book,
                database: database,
                readerSessionStore: readerSessionStore,
                aiChatViewModel: aiChatViewModel
            )
                .navigationBarBackButtonHidden(true)
#else
            ContentUnavailableView(
                "EPUB Reader Not Yet Available",
                systemImage: "book.closed",
                description: Text("The standalone macOS target is compiling ahead of full EPUB reader parity. PDF reading and the shared app shell remain in scope for later waves.")
            )
#endif
        } else {
            PDFReaderView(
                book: book,
                database: database,
                aiChatViewModel: aiChatViewModel,
                readerSessionStore: readerSessionStore
            )
                .navigationBarBackButtonHidden(true)
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: AppSpacing.md) {
            bookRowCover(for: book)

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
        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.isEditMode {
                editModeToolbarItems
            } else {
                normalToolbarItems
            }
        }
    }

    @ViewBuilder
    private var normalToolbarItems: some View {
        Menu {
            Section("View") {
                ForEach([BookshelfDisplayMode.grid, .list], id: \.rawValue) { mode in
                    Button {
                        displayMode = mode
                    } label: {
                        Label(mode.title, systemImage: displayMode == mode ? "checkmark" : mode.icon)
                    }
                }
            }

            Section("Sort") {
                ForEach(Array(BookshelfViewModel.SortOrder.allCases), id: \.rawValue) { sortOrder in
                    Button {
                        viewModel.sortOrder = sortOrder
                        Task { await viewModel.loadBooks() }
                    } label: {
                        Label(sortLabel(for: sortOrder), systemImage: viewModel.sortOrder == sortOrder ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            }

            Section("Manage") {
                Button {
                    presentedSheet = .manageTags
                } label: {
                    Label("Manage Tags", systemImage: "tag")
                }

                Button {
                    presentedSheet = .manageGroups
                } label: {
                    Label("Manage Groups", systemImage: "folder.badge.gearshape")
                }
            }

            Divider()

            Button {
                viewModel.toggleEditMode()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(Morandi.accent)
        }

        Button {
            showImporter = true
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(Morandi.accent)
        }
        .disabled(viewModel.isImporting)
    }

    @ViewBuilder
    private var editModeToolbarItems: some View {
        Button("Done") {
            viewModel.toggleEditMode()
        }
        .fontWeight(.semibold)
    }

    private func sortLabel(for sortOrder: BookshelfViewModel.SortOrder) -> String {
        switch sortOrder {
        case .dateDesc: "Date Added ↓"
        case .dateAsc: "Date Added ↑"
        case .titleAsc: "Title A-Z"
        case .titleDesc: "Title Z-A"
        case .authorAsc: "Author A-Z"
        }
    }

    private func bookGridCard(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            bookCover(for: book)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(book.title)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if book.author.isEmpty == false {
                    Text(book.author)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(1)
                }

                readingProgressBar(for: book)

                Text("\(Int(book.readingPercentage * 100))%")
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.accent)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
    }

    @ViewBuilder
    private func bookCover(for book: Book) -> some View {
        let cover = bookshelfCoverImage(for: book)

        ZStack {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.sand.opacity(0.35))

            if let cover {
                cover
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: book.filePath.lowercased().hasSuffix(".epub") ? "book.closed" : "doc.richtext")
                        .font(.system(size: 24, weight: .semibold))
                    Text(book.filePath.lowercased().hasSuffix(".epub") ? "EPUB" : "PDF")
                        .font(AppTypography.caption.weight(.semibold))
                }
                .foregroundStyle(Morandi.warmGray)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 2.1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }

    @ViewBuilder
    private func bookRowCover(for book: Book) -> some View {
        let cover = bookshelfCoverImage(for: book)
        ZStack {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .fill(Morandi.sand.opacity(0.6))
            if let cover {
                cover
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: book.filePath.lowercased().hasSuffix(".epub") ? "book.closed" : "doc.text")
                    .foregroundStyle(Morandi.warmGray)
            }
        }
        .frame(width: 44, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
    }

    private func readingProgressBar(for book: Book) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Morandi.divider
                    .frame(height: 4)
                    .clipShape(Capsule())
                Morandi.accent
                    .frame(width: geo.size.width * book.readingPercentage, height: 4)
                    .clipShape(Capsule())
            }
        }
        .frame(height: 4)
    }

    private func bookshelfCoverImage(for book: Book) -> Image? {
        guard let url = bookshelfCoverURL(for: book) else { return nil }

#if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
#elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
#else
        return nil
#endif
    }

    private func bookshelfCoverURL(for book: Book) -> URL? {
        guard book.coverPath.isEmpty == false else { return nil }
        if book.coverPath.hasPrefix("/") {
            return URL(fileURLWithPath: book.coverPath)
        }
        let libraryRoot = URL(fileURLWithPath: book.filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return libraryRoot
            .appendingPathComponent("Covers", isDirectory: true)
            .appendingPathComponent(book.coverPath)
    }

    private func undoBanner(for book: Book) -> some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Book deleted")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                Text(book.title)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button("Undo") {
                undoDismissTask?.cancel()
                Task { await viewModel.undoLastDelete() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.accent)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.sm)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }

    private func handleDelete(_ book: Book) {
        guard let id = book.id else { return }
        undoDismissTask?.cancel()

        Task {
            await viewModel.deleteBook(id: id)
            guard viewModel.pendingUndoBook != nil else { return }

            undoDismissTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    viewModel.clearPendingUndo()
                }
            }
        }
    }

    @ViewBuilder
    private func bookshelfTagMenu(for book: Book) -> some View {
        Menu("Tags") {
            if viewModel.tags.isEmpty {
                Button("No tags yet") { }
                    .disabled(true)
            } else {
                ForEach(viewModel.tags) { tag in
                    if let tagID = tag.id, let bookID = book.id {
                        let isAssigned = viewModel.tagIDs(forBookId: bookID).contains(tagID)
                        Button {
                            Task {
                                if isAssigned {
                                    try? await viewModel.detachTag(tagId: tagID, fromBookId: bookID)
                                } else {
                                    try? await viewModel.assignTag(tagId: tagID, toBookId: bookID)
                                }
                            }
                        } label: {
                            Label(tag.name, systemImage: isAssigned ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }

            Divider()

            Button("Manage Tags…") {
                presentedSheet = .manageTags
            }
        }
    }

    @ViewBuilder
    private func bookshelfMoveGroupMenu(for book: Book) -> some View {
        Menu("Move to Group") {
            if let bookID = book.id {
                Button {
                    Task { try? await viewModel.moveBook(id: bookID, toGroupId: nil) }
                } label: {
                    Label("No Group", systemImage: book.groupId == 0 ? "checkmark" : "folder")
                }

                if viewModel.groups.isEmpty {
                    Button("No groups yet") { }
                        .disabled(true)
                } else {
                    ForEach(viewModel.groups) { group in
                        if let groupID = group.id {
                            Button {
                                Task { try? await viewModel.moveBook(id: bookID, toGroupId: groupID) }
                            } label: {
                                Label(groupMenuTitle(for: group), systemImage: book.groupId == groupID ? "checkmark" : "folder")
                            }
                        }
                    }
                }

                Divider()

                Button("Manage Groups…") {
                    presentedSheet = .manageGroups
                }
            }
        }
    }

    private func groupMenuTitle(for group: TbGroup) -> String {
        if let parentID = group.parentId,
           let parent = viewModel.groups.first(where: { $0.id == parentID }) {
            return "\(parent.name) / \(group.name)"
        }
        return group.name
    }

    private func handleOpenRequestIfNeeded() async {
        guard let openRequest else { return }
        defer { self.openRequest = nil }

        let bookDAO = BookDAO(database: database)

        if let bookID = openRequest.bookID.flatMap(Int64.init),
           let book = try? await bookDAO.fetchById(bookID) {
            navigationBook = book
            await IntentsDonationService.donateOpenBook(title: book.title)
            return
        }

        guard let title = openRequest.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false,
              let matches = try? await bookDAO.search(query: title) else {
            return
        }

        let book = matches.first {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        } ?? matches.first
        navigationBook = book
        if let book {
            await IntentsDonationService.donateOpenBook(title: book.title)
        }
    }

    private func handleExternalImportRequestIfNeeded() async {
        guard let request = sharedInboxImportRequest else { return }
        defer { sharedInboxImportRequest = nil }

        let result = await SharedInboxImportProcessor(importBook: { url in
            await viewModel.importBook(url: url)
            return await viewModel.importError
        }).process(eventID: request.eventID)

        showImportError = result.shouldShowError
        await viewModel.loadBooks()
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            await viewModel.importBook(url: url)
            if viewModel.importError != nil {
                showImportError = true
            }
        }
    }
}

private struct BookshelfBookEditorSheet: View {
    let viewModel: BookshelfViewModel
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String
    @State private var errorMessage: String?

    init(viewModel: BookshelfViewModel, book: Book) {
        self.viewModel = viewModel
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                } header: {
                    Text("Metadata")
                }

                Section {
                    Text(book.filePath)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .textSelection(.enabled)
                } header: {
                    Text("File")
                }
            }
            .navigationTitle("Edit Book")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(trimmedTitle.isEmpty || book.id == nil)
                }
            }
        }
        .alert("Edit Failed", isPresented: isShowingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() async {
        guard let bookID = book.id else { return }
        do {
            try await viewModel.updateBookMetadata(id: bookID, title: title, author: author)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookshelfTagManagerSheet: View {
    let viewModel: BookshelfViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var editingTagID: Int64?
    @State private var draftName = ""
    @State private var draftColorHex = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        viewModel.toggleNoTagFilter()
                        Task { await viewModel.loadBooks() }
                    } label: {
                        HStack {
                            Text("No Tag")
                            Spacer()
                            if viewModel.includeNoTagFilter {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Morandi.accent)
                            }
                        }
                    }
                    .foregroundStyle(Morandi.primaryText)

                    if viewModel.tags.isEmpty {
                        Text("No tags yet.")
                            .foregroundStyle(Morandi.secondaryText)
                    } else {
                        ForEach(viewModel.tags) { tag in
                            if let tagID = tag.id {
                                Button {
                                    viewModel.toggleTagFilter(tagID)
                                    Task { await viewModel.loadBooks() }
                                } label: {
                                    HStack(spacing: AppSpacing.sm) {
                                        tagColorSwatch(tag.colorHex)
                                        Text(tag.name)
                                        Spacer()
                                        if viewModel.selectedTagIDs.contains(tagID) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Morandi.accent)
                                        }
                                    }
                                }
                                .foregroundStyle(Morandi.primaryText)
                                .contextMenu {
                                    Button("Edit") {
                                        beginEditing(tag)
                                    }
                                    Button("Delete", role: .destructive) {
                                        Task { await deleteTag(tag) }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Filters")
                }

                Section {
                    TextField("Tag name", text: $draftName)
#if os(iOS)
                    TextField("Color hex", text: $draftColorHex)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
#else
                    TextField("Color hex", text: $draftColorHex)
#endif

                    Button(editingTagID == nil ? "Create Tag" : "Save Changes") {
                        Task { await saveTag() }
                    }
                    .disabled(trimmedDraftName.isEmpty)

                    if editingTagID != nil {
                        Button("Cancel Editing", role: .cancel) {
                            resetEditor()
                        }
                    }
                } header: {
                    Text(editingTagID == nil ? "Create Tag" : "Edit Tag")
                }

                Section {
                    if viewModel.tags.isEmpty {
                        Text("Create your first tag above.")
                            .foregroundStyle(Morandi.secondaryText)
                    } else {
                        ForEach(viewModel.tags) { tag in
                            HStack(spacing: AppSpacing.sm) {
                                tagColorSwatch(tag.colorHex)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name)
                                        .foregroundStyle(Morandi.primaryText)
                                    if let colorHex = normalizedHex(tag.colorHex) {
                                        Text(colorHex)
                                            .font(AppTypography.caption)
                                            .foregroundStyle(Morandi.secondaryText)
                                    }
                                }
                                Spacer()
                                Button("Edit") {
                                    beginEditing(tag)
                                }
                                .font(AppTypography.caption.weight(.semibold))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Existing Tags")
                }
            }
            .navigationTitle("Tags")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadTags()
            }
        }
        .alert("Tag Error", isPresented: isShowingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var trimmedDraftName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    errorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func tagColorSwatch(_ colorHex: String?) -> some View {
        Circle()
            .fill(tagColor(for: colorHex))
            .frame(width: 12, height: 12)
    }

    private func tagColor(for colorHex: String?) -> Color {
        guard let normalizedHex = normalizedHex(colorHex) else {
            return Morandi.warmGray
        }
        return Color(hex: normalizedHex)
    }

    private func normalizedHex(_ colorHex: String?) -> String? {
        guard let colorHex else { return nil }
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func beginEditing(_ tag: Tag) {
        editingTagID = tag.id
        draftName = tag.name
        draftColorHex = tag.colorHex ?? ""
    }

    private func resetEditor() {
        editingTagID = nil
        draftName = ""
        draftColorHex = ""
    }

    private func saveTag() async {
        do {
            if let tagID = editingTagID {
                _ = try await viewModel.updateTag(id: tagID, name: draftName, colorHex: draftColorHex)
            } else {
                _ = try await viewModel.createTag(name: draftName, colorHex: draftColorHex)
            }
            resetEditor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTag(_ tag: Tag) async {
        guard let tagID = tag.id else { return }
        do {
            try await viewModel.deleteTag(id: tagID)
            if editingTagID == tagID {
                resetEditor()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookshelfGroupManagerSheet: View {
    let viewModel: BookshelfViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var editingGroupID: Int64?
    @State private var draftName = ""
    @State private var selectedParentGroupID: Int64?
    @State private var errorMessage: String?

    private struct GroupRow: Identifiable {
        let group: TbGroup
        let depth: Int

        var id: Int64 {
            group.id ?? Int64(depth)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $draftName)

                    if editingGroupID == nil {
                        Menu {
                            Button("Root Group") {
                                selectedParentGroupID = nil
                            }

                            if flattenedGroups.isEmpty == false {
                                Divider()
                                ForEach(flattenedGroups) { row in
                                    if let groupID = row.group.id {
                                        Button(parentLabel(for: row)) {
                                            selectedParentGroupID = groupID
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Parent")
                                Spacer()
                                Text(selectedParentTitle)
                                    .foregroundStyle(Morandi.secondaryText)
                            }
                        }
                    }

                    Button(editingGroupID == nil ? "Create Group" : "Save Changes") {
                        Task { await saveGroup() }
                    }
                    .disabled(trimmedDraftName.isEmpty)

                    if editingGroupID != nil {
                        Button("Cancel Editing", role: .cancel) {
                            resetEditor()
                        }
                    }
                } header: {
                    Text(editingGroupID == nil ? "Create Group" : "Rename Group")
                }

                Section {
                    if flattenedGroups.isEmpty {
                        Text("No groups yet.")
                            .foregroundStyle(Morandi.secondaryText)
                    } else {
                        ForEach(flattenedGroups) { row in
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Morandi.accent)
                                Text(row.group.name)
                                    .padding(.leading, CGFloat(row.depth) * 14)
                                Spacer()
                                Menu {
                                    Button("Rename") {
                                        beginRenaming(row.group)
                                    }

                                    Button("Add Child") {
                                        beginCreatingChild(of: row.group)
                                    }

                                    Button("Dissolve Group", role: .destructive) {
                                        Task { await dissolveGroup(row.group) }
                                    }

                                    Button("Delete Group", role: .destructive) {
                                        Task { await deleteGroup(row.group) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(Morandi.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Groups")
                } footer: {
                    Text("Move books between groups from each book's context menu.")
                }
            }
            .navigationTitle("Groups")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadGroups()
            }
        }
        .alert("Group Error", isPresented: isShowingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var trimmedDraftName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    errorMessage = nil
                }
            }
        )
    }

    private var flattenedGroups: [GroupRow] {
        makeFlattenedGroups(parentID: nil, depth: 0)
    }

    private var selectedParentTitle: String {
        guard let selectedParentGroupID,
              let row = flattenedGroups.first(where: { $0.group.id == selectedParentGroupID }) else {
            return "Root Group"
        }
        return parentLabel(for: row)
    }

    private func parentLabel(for row: GroupRow) -> String {
        let prefix = row.depth == 0 ? "" : String(repeating: "· ", count: row.depth)
        return prefix + row.group.name
    }

    private func makeFlattenedGroups(parentID: Int64?, depth: Int) -> [GroupRow] {
        let normalizedParentID = parentID ?? 0
        let groups = viewModel.groups
            .filter { ($0.parentId ?? 0) == normalizedParentID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return groups.flatMap { group in
            let current = GroupRow(group: group, depth: depth)
            let children = makeFlattenedGroups(parentID: group.id, depth: depth + 1)
            return [current] + children
        }
    }

    private func resetEditor() {
        editingGroupID = nil
        draftName = ""
        selectedParentGroupID = nil
    }

    private func beginRenaming(_ group: TbGroup) {
        editingGroupID = group.id
        draftName = group.name
        selectedParentGroupID = group.parentId
    }

    private func beginCreatingChild(of group: TbGroup) {
        editingGroupID = nil
        draftName = ""
        selectedParentGroupID = group.id
    }

    private func saveGroup() async {
        do {
            if let groupID = editingGroupID {
                _ = try await viewModel.renameGroup(id: groupID, to: draftName)
            } else {
                _ = try await viewModel.createGroup(name: draftName, parentId: selectedParentGroupID)
            }
            resetEditor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dissolveGroup(_ group: TbGroup) async {
        guard let groupID = group.id else { return }
        do {
            try await viewModel.dissolveGroup(id: groupID)
            if editingGroupID == groupID {
                resetEditor()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteGroup(_ group: TbGroup) async {
        guard let groupID = group.id else { return }
        do {
            try await viewModel.deleteGroup(id: groupID)
            if editingGroupID == groupID {
                resetEditor()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BookshelfBatchMoveSheet: View {
    let viewModel: BookshelfViewModel
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    Task {
                        await viewModel.batchMoveSelectedBooks(toGroupId: nil)
                        onDone()
                    }
                } label: {
                    Label("No Group (Root)", systemImage: "folder")
                }

                ForEach(viewModel.groups) { group in
                    if let groupID = group.id {
                        Button {
                            Task {
                                await viewModel.batchMoveSelectedBooks(toGroupId: groupID)
                                onDone()
                            }
                        } label: {
                            Label(group.name, systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle("Move \(viewModel.selectedBookIDs.count) Books")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#if canImport(ReadiumShared)
struct EPUBBookshelfReaderView: View {
    let book: Book
    let database: AppDatabase
    let readerSessionStore: ReaderSessionContextStore?
    let aiChatViewModel: AIChatViewModel

    @State private var publication: Publication?
    @State private var coordinator = EPUBNavigatorCoordinator()
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isAIPanelPresented = false
    @State private var readerControlsViewModel: EPUBReaderControlsViewModel?
    @State private var annotationsViewModel: EPUBReaderAnnotationsViewModel?
    @State private var preferencesViewModel: EPUBReaderPreferencesViewModel?
    @State private var annotationDraft: EPUBReaderAnnotationDraft?
    @State private var imageExperienceController = ReaderImageExperienceController()
    @State private var annotationErrorMessage: String?
    @State private var isReaderSettingsPresented = false
    @State private var readingSessionRecorder: ReadingSessionRecorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(
        book: Book,
        database: AppDatabase,
        readerSessionStore: ReaderSessionContextStore?,
        aiChatViewModel: AIChatViewModel
    ) {
        self.book = book
        self.database = database
        self.readerSessionStore = readerSessionStore
        self.aiChatViewModel = aiChatViewModel
        _readingSessionRecorder = State(initialValue: ReadingSessionRecorder(bookId: book.id, database: database))
    }

    private var initialLocator: Locator? {
        EPUBAnnotationBridge.locator(fromStoredString: book.lastReadPosition)
    }

    private let annotationDecorationGroup = "annotations"

    var body: some View {
        ReaderAIPanelHost(
            book: book,
            aiChatViewModel: aiChatViewModel,
            isPresented: $isAIPanelPresented
        ) {
            readerContent
        }
        .navigationTitle(book.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar { toolbarContent }
        .sheet(isPresented: tocSheetBinding) { tocSheet }
        .sheet(isPresented: searchSheetBinding) { searchSheet }
        .sheet(isPresented: annotationEditorPresentedBinding) { annotationEditorSheet }
        .sheet(isPresented: readerSettingsPresentedBinding) { readerSettingsSheet }
        .fullScreenCover(item: presentedImageBinding) { asset in
            ReaderImageViewer(
                asset: asset,
                bookTitle: book.title,
                chapterTitle: coordinator.currentChapterTitle,
                onClose: {
                    imageExperienceController.dismiss()
                },
                onAnalyze: handlePresentedImageAnalysis
            )
        }
        .task { await loadPublication() }
        .onDisappear {
            coordinator.onLocatorChange = nil
            coordinator.onSelectionChange = nil
            coordinator.onDecorationActivated = nil
            coordinator.onImageActivate = nil
            readerSessionStore?.clear()
            Task {
                await saveProgress()
                await endReadingSession()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isAIPanelPresented == false {
                ReaderAIMinimizedBar(aiChatViewModel: aiChatViewModel) {
                    isAIPanelPresented = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { await handleScenePhaseChange(newPhase) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PaperTokToggleAI"))) { _ in
            isAIPanelPresented.toggle()
        }
        .alert("Annotation Error", isPresented: annotationErrorPresentedBinding) {
            Button("OK") {
                annotationErrorMessage = nil
            }
        } message: {
            Text(annotationErrorMessage ?? "")
        }
        .alert("Reader Settings Error", isPresented: readerSettingsErrorPresentedBinding) {
            Button("OK") {
                preferencesViewModel?.clearError()
            }
        } message: {
            Text(preferencesViewModel?.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        ZStack {
            Morandi.background.ignoresSafeArea()

            if isLoading {
                ProgressView("Opening…")
                    .tint(Morandi.accent)
            } else if let publication {
                EPUBReaderView(
                    publication: publication,
                    coordinator: coordinator,
                    initialLocator: initialLocator,
                    readingPreferences: preferencesSnapshot
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    "Cannot Open",
                    systemImage: "book.closed",
                    description: Text(loadError ?? "The EPUB could not be opened.")
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                Task { await saveProgress() }
                dismiss()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "chevron.left")
#if os(iOS)
                    Text("Library")
#endif
                }
                .foregroundStyle(Morandi.accent)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                isAIPanelPresented = true
            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel("Open AI Panel")

            Button {
                readerControlsViewModel?.showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel("Search Book")
            .disabled(readerControlsViewModel == nil)

            Button {
                isReaderSettingsPresented = true
            } label: {
                Image(systemName: "textformat.size")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel("Open Reader Settings")
            .disabled(preferencesViewModel == nil)

            Button {
                presentBookmarkDraft()
            } label: {
                Image(systemName: "bookmark")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel("Add Bookmark")
            .disabled((coordinator.currentLocator ?? initialLocator) == nil)

            Button {
                readerControlsViewModel?.showTOC = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel("Open Contents")
            .disabled(readerControlsViewModel == nil)
        }

        ToolbarItem(placement: .status) {
            Text("\(Int((coordinator.readingProgress * 100).rounded()))%")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
                .monospacedDigit()
        }
    }

    private func loadPublication() async {
        guard publication == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let openedPublication = try await EPUBPublicationOpener().open(at: URL(fileURLWithPath: book.filePath))
            publication = openedPublication
            let controlsViewModel = EPUBReaderControlsViewModel(bridge: EPUBContentBridge(publication: openedPublication))
            await controlsViewModel.loadTableOfContents()
            readerControlsViewModel = controlsViewModel
            if let bookID = book.id {
                let annotationsViewModel = EPUBReaderAnnotationsViewModel(bookId: bookID, database: database)
                await annotationsViewModel.loadAnnotations()
                self.annotationsViewModel = annotationsViewModel
                let preferencesViewModel = EPUBReaderPreferencesViewModel(bookId: bookID, database: database)
                await preferencesViewModel.load()
                self.preferencesViewModel = preferencesViewModel
                coordinator.onSelectionChange = { locator, selectedText, _ in
                    presentAnnotationDraft(locator: locator, selectedText: selectedText, type: .highlight)
                }
                coordinator.observeDecorationInteractions(inGroup: annotationDecorationGroup) { event in
                    presentAnnotationEditor(decorationID: event.decoration.id)
                }
                coordinator.onImageActivate = { asset in
                    imageExperienceController.present(asset)
                }
                applyAnnotationDecorations(using: annotationsViewModel)
            } else {
                annotationsViewModel = nil
                preferencesViewModel = nil
                coordinator.onImageActivate = nil
            }
            let activeCoordinator = coordinator
            coordinator.onLocatorChange = { locator in
                publishReaderSession(
                    publication: openedPublication,
                    locator: locator,
                    progress: activeCoordinator.readingProgress
                )
            }
            publishReaderSession(
                publication: openedPublication,
                locator: coordinator.currentLocator ?? initialLocator,
                progress: coordinator.readingProgress
            )
            await readingSessionRecorder.resume()
            loadError = nil
        } catch {
            readerControlsViewModel = nil
            annotationsViewModel = nil
            preferencesViewModel = nil
            readerSessionStore?.clear()
            loadError = error.localizedDescription
        }
    }

    private func saveProgress() async {
        guard let bookID = book.id,
              var savedBook = try? await BookDAO(database: database).fetchById(bookID) else {
            return
        }

        if let locator = coordinator.currentLocator {
            savedBook.lastReadPosition = EPUBAnnotationBridge.storedString(from: locator)
        }
        savedBook.readingPercentage = coordinator.readingProgress
        savedBook.updateTime = Date()
        _ = try? await BookDAO(database: database).save(savedBook)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await readingSessionRecorder.resume()
        case .inactive:
            await readingSessionRecorder.pause()
        case .background:
            await saveProgress()
            await endReadingSession()
        @unknown default:
            await readingSessionRecorder.pause()
        }
    }

    private func endReadingSession() async {
        _ = try? await readingSessionRecorder.flush()
    }

    private func publishReaderSession(
        publication: Publication,
        locator: Locator?,
        progress: Double
    ) {
        guard let readerSessionStore else { return }
        let bridge = ReaderSessionToolBridgeAdapter(bridge: EPUBContentBridge(publication: publication))
        readerSessionStore.update(
            ReaderSessionSnapshot(
                bookId: book.id,
                readingProgress: progress,
                chapterTitle: locator?.title ?? coordinator.currentChapterTitle,
                locationHref: locator?.href.string ?? initialLocator?.href.string,
                contentBridgeProvider: { bridge }
            )
        )
    }

    private var tocSheetBinding: Binding<Bool> {
        Binding(
            get: { readerControlsViewModel?.showTOC ?? false },
            set: { newValue in readerControlsViewModel?.showTOC = newValue }
        )
    }

    private var searchSheetBinding: Binding<Bool> {
        Binding(
            get: { readerControlsViewModel?.showSearch ?? false },
            set: { newValue in readerControlsViewModel?.showSearch = newValue }
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { readerControlsViewModel?.searchQuery ?? "" },
            set: { newValue in readerControlsViewModel?.searchQuery = newValue }
        )
    }

    private var presentedImageBinding: Binding<ReaderImageAsset?> {
        Binding(
            get: { imageExperienceController.presentedImage },
            set: { newValue in
                if let newValue {
                    imageExperienceController.present(newValue)
                } else {
                    imageExperienceController.dismiss()
                }
            }
        )
    }

    private var tocSheet: some View {
        NavigationStack {
            Group {
                if let readerControlsViewModel {
                    if readerControlsViewModel.isLoadingTOC {
                        ProgressView("Loading contents…")
                            .tint(Morandi.accent)
                    } else if let tocErrorMessage = readerControlsViewModel.tocErrorMessage {
                        ContentUnavailableView(
                            "Couldn’t Load Contents",
                            systemImage: "exclamationmark.triangle",
                            description: Text(tocErrorMessage)
                        )
                    } else if readerControlsViewModel.tocEntries.isEmpty {
                        ContentUnavailableView(
                            "No Contents",
                            systemImage: "list.bullet.indent",
                            description: Text("This EPUB does not expose a table of contents.")
                        )
                    } else {
                        List(readerControlsViewModel.tocEntries) { entry in
                            Button {
                                navigateToEPUBLocation(href: entry.href)
                                readerControlsViewModel.showTOC = false
                            } label: {
                                HStack(spacing: AppSpacing.xs) {
                                    if entry.level > 0 {
                                        Spacer().frame(width: CGFloat(entry.level) * AppSpacing.lg)
                                    }
                                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                        Text(entry.title)
                                            .font(entry.level == 0 ? AppTypography.headline : AppTypography.body)
                                            .foregroundStyle(
                                                entry.level == 0 ? Morandi.primaryText : Morandi.secondaryText
                                            )
                                        if entry.childCount > 0 {
                                            Text("\(entry.childCount) sub-sections")
                                                .font(AppTypography.caption)
                                                .foregroundStyle(Morandi.secondaryText)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .listRowBackground(Morandi.background)
                        }
                        .listStyle(.plain)
                    }
                } else {
                    ProgressView("Preparing reader controls…")
                        .tint(Morandi.accent)
                }
            }
            .background(Morandi.background)
            .navigationTitle("Contents")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        readerControlsViewModel?.showTOC = false
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var searchSheet: some View {
        NavigationStack {
            Group {
                if let readerControlsViewModel {
                    if readerControlsViewModel.searchQuery.isEmpty {
                        ContentUnavailableView(
                            "Search This Book",
                            systemImage: "magnifyingglass",
                            description: Text("Enter a phrase to search across the EPUB contents.")
                        )
                    } else if readerControlsViewModel.isSearching {
                        ProgressView("Searching…")
                            .tint(Morandi.accent)
                    } else if let searchErrorMessage = readerControlsViewModel.searchErrorMessage {
                        ContentUnavailableView(
                            "Search Failed",
                            systemImage: "exclamationmark.magnifyingglass",
                            description: Text(searchErrorMessage)
                        )
                    } else if readerControlsViewModel.searchResults.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("No matches were found for “\(readerControlsViewModel.searchQuery)”.")
                        )
                    } else {
                        List(readerControlsViewModel.searchResults) { result in
                            Button {
                                navigateToEPUBSearchResult(result)
                                readerControlsViewModel.showSearch = false
                            } label: {
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(result.chapterTitle)
                                        .font(AppTypography.headline)
                                        .foregroundStyle(Morandi.primaryText)

                                    (
                                        Text(result.textBefore)
                                            .foregroundStyle(Morandi.secondaryText)
                                        + Text(result.text)
                                            .foregroundStyle(Morandi.accent)
                                            .bold()
                                        + Text(result.textAfter)
                                            .foregroundStyle(Morandi.secondaryText)
                                    )
                                    .font(AppTypography.body)
                                    .lineLimit(4)

                                    if result.progression > 0 {
                                        Text("\(Int((result.progression * 100).rounded()))% into chapter")
                                            .font(AppTypography.caption)
                                            .foregroundStyle(Morandi.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .listRowBackground(Morandi.background)
                        }
                        .listStyle(.plain)
                    }
                } else {
                    ProgressView("Preparing search…")
                        .tint(Morandi.accent)
                }
            }
            .background(Morandi.background)
            .navigationTitle("Search")
            .searchable(text: searchQueryBinding, prompt: "Search in this book")
            .onSubmit(of: .search) {
                Task { await readerControlsViewModel?.performSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Search") {
                        Task { await readerControlsViewModel?.performSearch() }
                    }
                    .foregroundStyle(Morandi.accent)
                    .disabled((readerControlsViewModel?.searchQuery.isEmpty ?? true) || (readerControlsViewModel?.isSearching ?? false))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        readerControlsViewModel?.showSearch = false
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func navigateToEPUBLocation(href: String, progression: Double = 0) {
        guard let resolvedHref = AnyURL(path: href) else { return }
        let normalizedProgression = progression > 0 ? min(max(progression, 0), 1) : nil
        coordinator.navigate(
            to: Locator(
                href: resolvedHref,
                mediaType: .xhtml,
                locations: Locator.Locations(progression: normalizedProgression)
            )
        )
    }

    private func navigateToEPUBSearchResult(_ result: ContentSearchResult) {
        if let locatorString = result.locatorString,
           let locator = EPUBAnnotationBridge.locator(fromStoredString: locatorString) {
            coordinator.navigate(to: locator)
            return
        }

        navigateToEPUBLocation(href: result.chapterHref, progression: result.progression)
    }

    private var annotationEditorPresentedBinding: Binding<Bool> {
        Binding(
            get: { annotationDraft != nil },
            set: { isPresented in
                guard isPresented == false else { return }
                annotationDraft = nil
                coordinator.clearSelection()
            }
        )
    }

    private var annotationErrorPresentedBinding: Binding<Bool> {
        Binding(
            get: { annotationErrorMessage?.isEmpty == false },
            set: { isPresented in
                if isPresented == false {
                    annotationErrorMessage = nil
                }
            }
        )
    }

    private var readerSettingsPresentedBinding: Binding<Bool> {
        Binding(
            get: { isReaderSettingsPresented && preferencesViewModel != nil },
            set: { isPresented in
                if isPresented == false {
                    isReaderSettingsPresented = false
                }
            }
        )
    }

    private var readerSettingsErrorPresentedBinding: Binding<Bool> {
        Binding(
            get: { preferencesViewModel?.errorMessage?.isEmpty == false },
            set: { isPresented in
                if isPresented == false {
                    preferencesViewModel?.clearError()
                }
            }
        )
    }

    private var annotationDraftBinding: Binding<EPUBReaderAnnotationDraft> {
        Binding(
            get: {
                annotationDraft ?? EPUBReaderAnnotationDraft(
                    locatorString: "",
                    selectedText: "",
                    chapterTitle: ""
                )
            },
            set: { annotationDraft = $0 }
        )
    }

    private var annotationEditorSheet: some View {
        EPUBReaderAnnotationEditorView(
            draft: annotationDraftBinding,
            onSave: {
                Task { await saveAnnotationDraft() }
            },
            onDelete: annotationDraft?.noteID == nil ? nil : {
                Task { await deleteCurrentAnnotation() }
            },
            onCancel: {
                annotationDraft = nil
                coordinator.clearSelection()
            }
        )
    }

    @ViewBuilder
    private var readerSettingsSheet: some View {
        if let preferencesViewModel {
            EPUBReaderSettingsView(viewModel: preferencesViewModel) {
                isReaderSettingsPresented = false
            }
        }
    }

    private var preferencesSnapshot: EPUBReadingPreferencesSnapshot {
        if let preferencesViewModel {
            return EPUBReadingPreferencesSnapshot(readingPreferences: preferencesViewModel.readingPreferences)
        }
        return EPUBReadingPreferencesSnapshot(readingPreferences: ReadingPreferences())
    }

    private func presentAnnotationDraft(locator: Locator, selectedText: String, type: NoteType) {
        let chapterTitle = locator.title ?? coordinator.currentChapterTitle
        annotationDraft = EPUBReaderAnnotationDraft(
            locatorString: EPUBAnnotationBridge.storedString(from: locator),
            selectedText: selectedText,
            chapterTitle: chapterTitle,
            type: type,
            color: .yellow
        )
    }

    private func presentBookmarkDraft() {
        guard let locator = coordinator.currentLocator ?? initialLocator else {
            return
        }

        presentAnnotationDraft(locator: locator, selectedText: "", type: .bookmark)
    }

    private func presentAnnotationEditor(decorationID: String) {
        guard let note = annotationsViewModel?.note(matchingDecorationID: decorationID) else {
            return
        }

        annotationDraft = EPUBReaderAnnotationDraft(note: note)
    }

    private func saveAnnotationDraft() async {
        guard let annotationDraft,
              let annotationsViewModel else {
            return
        }

        let savedNote: BookNote?
        if let noteID = annotationDraft.noteID {
            savedNote = await annotationsViewModel.updateAnnotation(
                id: noteID,
                type: annotationDraft.type,
                color: annotationDraft.color,
                readerNote: annotationDraft.readerNote
            )
        } else {
            savedNote = await annotationsViewModel.createAnnotation(
                selectedText: annotationDraft.selectedText,
                locatorString: annotationDraft.locatorString,
                chapterTitle: annotationDraft.chapterTitle,
                type: annotationDraft.type,
                color: annotationDraft.color,
                readerNote: annotationDraft.readerNote
            )
        }

        guard savedNote != nil else {
            annotationErrorMessage = annotationsViewModel.errorMessage ?? "The annotation could not be saved."
            return
        }

        applyAnnotationDecorations(using: annotationsViewModel)
        self.annotationDraft = nil
        coordinator.clearSelection()
    }

    private func deleteCurrentAnnotation() async {
        guard let noteID = annotationDraft?.noteID,
              let annotationsViewModel else {
            return
        }

        await annotationsViewModel.deleteAnnotation(id: noteID)
        guard annotationsViewModel.errorMessage == nil else {
            annotationErrorMessage = annotationsViewModel.errorMessage ?? "The annotation could not be deleted."
            return
        }

        applyAnnotationDecorations(using: annotationsViewModel)
        annotationDraft = nil
        coordinator.clearSelection()
    }

    private func handlePresentedImageAnalysis() {
        guard let request = imageExperienceController.prepareAnalysis(
            bookTitle: book.title,
            chapterTitle: coordinator.currentChapterTitle
        ) else {
            return
        }

        aiChatViewModel.addAttachment(
            .init(
                type: .image,
                name: request.image.filename,
                data: request.image.data
            )
        )
        isAIPanelPresented = true
        Task {
            _ = await aiChatViewModel.sendMessage(request.prompt)
        }
    }

    private func applyAnnotationDecorations(using annotationsViewModel: EPUBReaderAnnotationsViewModel?) {
        let decorations = annotationsViewModel?.notes.compactMap(EPUBAnnotationBridge.decoration(from:)) ?? []
        coordinator.applyDecorations(decorations, in: annotationDecorationGroup)
    }
}
#endif

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
    @State private var exportFeedbackMessage = ""
    @State private var isExportFeedbackPresented = false
    @State private var editingNote: BookNote?

    init(database: AppDatabase) {
        self.database = database
        _viewModel = State(initialValue: NotesViewModel(database: database))
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
                        notesEmptyTitle,
                        systemImage: notesEmptyIcon,
                        description: Text(notesEmptyDescription)
                    )
                    .background(Morandi.background)
                } else {
                    notesList
                }
            }
            .background(Morandi.background)
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    notesSortMenu
                    if viewModel.notes.isEmpty == false {
                        exportMenu
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search notes")
            .onChange(of: viewModel.searchQuery) { _, _ in
                Task { await viewModel.loadNotes() }
            }
            .task { await viewModel.loadNotes() }
            .alert("Notes Exported", isPresented: $isExportFeedbackPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportFeedbackMessage)
            }
            .sheet(item: $editingNote) { note in
                NoteEditSheet(note: note) { updatedNote in
                    Task { await viewModel.updateNote(updatedNote) }
                }
            }
        }
    }

    private var notesEmptyTitle: String {
        if !viewModel.searchQuery.isEmpty { return "No Results" }
        if viewModel.filterType != .all { return "No \(viewModel.filterType.displayName)" }
        return "No Notes Yet"
    }

    private var notesEmptyIcon: String {
        if !viewModel.searchQuery.isEmpty { return "magnifyingglass" }
        return viewModel.filterType.systemImage
    }

    private var notesEmptyDescription: String {
        if !viewModel.searchQuery.isEmpty { return "No notes match your search." }
        if viewModel.filterType != .all { return "No \(viewModel.filterType.displayName.lowercased()) found." }
        return "Highlight text while reading to create notes."
    }

    // MARK: - Filter & Sort

    private var notesFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(NotesFilterType.allCases) { filterType in
                    Button {
                        viewModel.filterType = filterType
                    } label: {
                        Label(filterType.displayName, systemImage: filterType.systemImage)
                            .font(AppTypography.footnote.weight(viewModel.filterType == filterType ? .semibold : .regular))
                            .foregroundStyle(viewModel.filterType == filterType ? Morandi.accent : Morandi.secondaryText)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                Capsule()
                                    .fill(viewModel.filterType == filterType ? Morandi.accent.opacity(0.12) : Morandi.cardBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
        }
    }

    @ViewBuilder
    private var notesSortMenu: some View {
        Menu {
            Section("Sort") {
                ForEach(NotesSortOrder.allCases) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        if viewModel.sortOrder == order {
                            Label(order.displayName, systemImage: "checkmark")
                        } else {
                            Text(order.displayName)
                        }
                    }
                }
            }

            Section("Filter") {
                ForEach(NotesFilterType.allCases) { filterType in
                    Button {
                        viewModel.filterType = filterType
                    } label: {
                        if viewModel.filterType == filterType {
                            Label(filterType.displayName, systemImage: "checkmark")
                        } else {
                            Label(filterType.displayName, systemImage: filterType.systemImage)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(Morandi.accent)
                .symbolVariant(viewModel.filterType != .all || viewModel.sortOrder != .dateDescending ? .fill : .none)
        }
        .accessibilityLabel("Filter and Sort")
    }

    private var notesList: some View {
        List {
            Section {
                HStack(spacing: AppSpacing.md) {
                    summaryCard(title: "Total Notes", value: "\(viewModel.summary.totalNotes)", systemImage: "note.text")
                    summaryCard(title: "Books", value: "\(viewModel.summary.booksWithNotes)", systemImage: "books.vertical")
                }
                .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: 0, bottom: AppSpacing.sm, trailing: 0))
                .listRowBackground(Morandi.background)
            }

            Section {
                notesFilterBar
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Morandi.background)
            }

            ForEach(viewModel.groupedNotes) { group in
                Section {
                    ForEach(group.notes) { note in
                        noteRow(note)
                            .listRowBackground(Morandi.background)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingNote = note
                            }
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
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingNote = note
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Morandi.accent)
                            }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(group.bookTitle)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(Morandi.primaryText)
                        Text("\(group.notes.count) note\(group.notes.count == 1 ? "" : "s")")
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Morandi.background)
    }

    private func noteRow(_ note: BookNote) -> some View {
        HStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: 2)
                .fill(highlightColor(for: note.color))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label(note.displayType, systemImage: noteTypeSystemImage(for: note))
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)

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
                    Text(markdownAttributedString(readerNote))
                        .font(AppTypography.footnote)
                        .foregroundStyle(Morandi.accent)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func highlightColor(for colorName: String) -> Color {
        Color(hex: NoteColorResolver.normalizedHex(for: colorName))
    }

    @ViewBuilder
    private var exportMenu: some View {
        Menu {
            ForEach(NotesExportFormat.allCases) { format in
                ShareLink(
                    item: viewModel.export(format: format),
                    preview: SharePreview("PaperTok Notes \(format.displayName)", image: Image(systemName: "square.and.arrow.up"))
                ) {
                    Label("Share \(format.displayName)", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyToPasteboard(viewModel.export(format: format))
                    exportFeedbackMessage = "\(format.displayName) copied to clipboard."
                    isExportFeedbackPresented = true
                } label: {
                    Label("Copy \(format.displayName)", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Morandi.accent)
        }
        .accessibilityLabel("Export Notes")
    }

    private func summaryCard(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(Morandi.accent)
            Text(value)
                .font(AppTypography.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Morandi.primaryText)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }

    private func noteTypeSystemImage(for note: BookNote) -> String {
        switch note.type.lowercased() {
        case "bookmark": return "bookmark.fill"
        case "note": return "text.bubble.fill"
        default: return "highlighter"
        }
    }

    private func markdownAttributedString(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

    private func copyToPasteboard(_ text: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}

// MARK: - Note Edit Sheet

private struct NoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editedNote: BookNote
    private let onSave: (BookNote) -> Void

    init(note: BookNote, onSave: @escaping (BookNote) -> Void) {
        _editedNote = State(initialValue: note)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Text(editedNote.content)
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                }

                if !editedNote.chapter.isEmpty {
                    Section("Chapter") {
                        Text(editedNote.chapter)
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                }

                Section("Note") {
                    TextEditor(text: noteEditReaderNoteBinding)
                        .frame(minHeight: 120)
                        .font(AppTypography.body)
                }

                Section("Type") {
                    Picker("Type", selection: $editedNote.type) {
                        Text("Highlight").tag("highlight")
                        Text("Bookmark").tag("bookmark")
                        Text("Note").tag("note")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle("Edit Note")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Morandi.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editedNote.updateTime = Date()
                        onSave(editedNote)
                        dismiss()
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var noteEditReaderNoteBinding: Binding<String> {
        Binding(
            get: { editedNote.readerNote ?? "" },
            set: { editedNote.readerNote = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Statistics Screen

struct StatisticsScreen: View {
    let database: AppDatabase
    @State private var viewModel: StatisticsViewModel
    @State private var isCustomizeTilesPresented = false

    init(database: AppDatabase) {
        self.database = database
        _viewModel = State(initialValue: StatisticsViewModel(database: database))
    }

    private let heatmapColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let dashboardColumns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 2)
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
        max(heatmapDates.map { viewModel.dailyReadingData[$0] ?? 0 }.max() ?? 1, 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    dashboardSection
                    periodSummarySection
                    heatmapSection
                    trendSection
                    completionSection
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCustomizeTilesPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Morandi.accent)
                    }
                    .accessibilityLabel("Customize Dashboard")
                }
            }
            .task { await viewModel.loadStats() }
            .sheet(isPresented: $isCustomizeTilesPresented) {
                StatisticsTileCustomizationSheet(tiles: viewModel.visibleTiles) { tiles in
                    viewModel.saveVisibleTiles(tiles)
                }
            }
        }
    }

    private var dashboardSection: some View {
        LazyVGrid(columns: dashboardColumns, spacing: AppSpacing.md) {
            ForEach(viewModel.visibleTiles) { tile in
                dashboardTile(for: tile)
                    .gridCellColumns(tile == .dailyHighlight ? 2 : 1)
            }
        }
    }

    @ViewBuilder
    private func dashboardTile(for tile: StatisticsDashboardTile) -> some View {
        switch tile {
        case .readingTime:
            statCard(title: tile.title, value: viewModel.formattedReadingTime, icon: "clock")
        case .totalBooks:
            statCard(title: tile.title, value: "\(viewModel.totalBooks)", icon: "books.vertical")
        case .totalNotes:
            statCard(title: tile.title, value: "\(viewModel.totalNotes)", icon: "note.text")
        case .currentStreak:
            statCard(title: tile.title, value: "\(viewModel.currentStreakDays)d", icon: "flame.fill")
        case .longestStreak:
            statCard(title: tile.title, value: "\(viewModel.longestStreakDays)d", icon: "flame")
        case .dailyHighlight:
            dailyHighlightCard
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

    private var periodSummarySection: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                periodSummaryCard(title: "This Week", summary: viewModel.weeklySummary)
                periodSummaryCard(title: "This Month", summary: viewModel.monthlySummary)
            }
        }
    }

    private func periodSummaryCard(title: String, summary: StatisticsPeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(summary.formattedTotal)
                    .font(AppTypography.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Morandi.accent)
                    .monospacedDigit()

                Text("total")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.dailyAverageMinutes)m")
                        .font(AppTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Morandi.primaryText)
                        .monospacedDigit()
                    Text("avg/day")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.activeDays)")
                        .font(AppTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Morandi.primaryText)
                        .monospacedDigit()
                    Text("active days")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius)
    }

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

    private var dailyHighlightCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Label("Daily Highlight", systemImage: "sparkles.rectangle.stack")
                    .font(AppTypography.headline)
                    .foregroundStyle(Morandi.primaryText)

                Spacer()

                Button {
                    Task { await viewModel.loadStats() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Morandi.accent)
                }
                .buttonStyle(.plain)
            }

            if let highlight = viewModel.dailyHighlight {
                Text(highlight.bookTitle)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.secondaryText)

                Text(highlight.note.content)
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(4)

                if let readerNote = highlight.note.readerNote, readerNote.isEmpty == false {
                    Text(readerNote)
                        .font(AppTypography.footnote)
                        .foregroundStyle(Morandi.accent)
                        .lineLimit(2)
                }
            } else {
                Text("Create more highlights while reading to surface a daily quote here.")
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Reading Trends")
                    .font(AppTypography.headline)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Picker("Range", selection: $viewModel.trendRange) {
                    ForEach(StatisticsTrendRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            VStack(spacing: AppSpacing.sm) {
                ForEach(viewModel.trendPoints) { point in
                    HStack(spacing: AppSpacing.md) {
                        Text(point.label)
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.secondaryText)
                            .frame(width: 40, alignment: .leading)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Morandi.divider)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Morandi.accent.opacity(0.85))
                                    .frame(width: max(barWidth(for: point.minutes, totalWidth: geometry.size.width), point.minutes > 0 ? 6 : 0))
                            }
                        }
                        .frame(height: 10)

                        Text("\(point.minutes)m")
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.primaryText)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .frame(height: 18)
                }
            }

            Divider()
                .overlay(Morandi.divider)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("By Book")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)

                if viewModel.perBookTrendBreakdowns.isEmpty {
                    Text("Books with reading activity in the selected range will appear here.")
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.secondaryText)
                } else {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(viewModel.perBookTrendBreakdowns) { breakdown in
                            perBookTrendCard(breakdown)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius)
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Nearly Finished")
                .font(AppTypography.headline)
                .foregroundStyle(Morandi.primaryText)

            if viewModel.nearlyFinishedBooks.isEmpty {
                Text("Books between 60% and 93% completion will appear here.")
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.secondaryText)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(viewModel.nearlyFinishedBooks, id: \.id) { book in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack {
                                Text(book.title)
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(Morandi.primaryText)
                                Spacer()
                                Text("\(Int((book.readingPercentage * 100).rounded()))%")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(Morandi.secondaryText)
                                    .monospacedDigit()
                            }

                            ProgressView(value: book.readingPercentage)
                                .tint(Morandi.accent)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius)
    }

    private func barWidth(for minutes: Int, totalWidth: CGFloat) -> CGFloat {
        let maximum = CGFloat(max(viewModel.trendPoints.map(\.minutes).max() ?? 1, 1))
        return totalWidth * (CGFloat(minutes) / maximum)
    }

    private func perBookTrendCard(_ breakdown: StatisticsBookTrendBreakdown) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(breakdown.bookTitle)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(1)

                Spacer()

                Text("\(breakdown.totalMinutes)m")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .monospacedDigit()
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(breakdown.points) { point in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Morandi.accent.opacity(point.minutes > 0 ? 0.85 : 0.18))
                        .frame(maxWidth: .infinity)
                        .frame(height: perBookTrendBarHeight(point.minutes, in: breakdown))
                        .help("\(point.label): \(point.minutes)m")
                }
            }
            .frame(height: 36, alignment: .bottom)
        }
        .padding(AppSpacing.md)
        .background(Morandi.background)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }

    private func perBookTrendBarHeight(_ minutes: Int, in breakdown: StatisticsBookTrendBreakdown) -> CGFloat {
        let maximum = max(breakdown.points.map(\.minutes).max() ?? 1, 1)
        guard minutes > 0 else { return 6 }
        return max(8, 28 * CGFloat(minutes) / CGFloat(maximum))
    }
}

private struct StatisticsTileCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tiles: [StatisticsDashboardTile]

    let onSave: ([StatisticsDashboardTile]) -> Void

    init(
        tiles: [StatisticsDashboardTile],
        onSave: @escaping ([StatisticsDashboardTile]) -> Void
    ) {
        self.onSave = onSave
        _tiles = State(initialValue: tiles)
    }

    private var hiddenTiles: [StatisticsDashboardTile] {
        StatisticsDashboardTile.allCases.filter { tiles.contains($0) == false }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Visible Tiles") {
                    ForEach(tiles) { tile in
                        HStack {
                            Text(tile.title)
                            Spacer()
                            Button("Hide") {
                                withAnimation {
                                    tiles.removeAll { $0 == tile }
                                }
                            }
                            .foregroundStyle(Morandi.destructive)
                        }
                    }
                    .onMove { source, destination in
                        tiles.move(fromOffsets: source, toOffset: destination)
                    }
                }

                if hiddenTiles.isEmpty == false {
                    Section("Hidden Tiles") {
                        ForEach(hiddenTiles) { tile in
                            Button {
                                withAnimation {
                                    tiles.append(tile)
                                }
                            } label: {
                                Label(tile.title, systemImage: "plus.circle")
                            }
                            .foregroundStyle(Morandi.accent)
                        }
                    }
                }
            }
            .navigationTitle("Dashboard Tiles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(tiles)
                        dismiss()
                    }
                }
#if os(iOS)
                ToolbarItem(placement: .automatic) {
                    EditButton()
                }
#endif
            }
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

// AIChatPlaceholderView removed — replaced by AIChatView (Phase 9)

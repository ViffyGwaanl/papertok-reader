import PDFKit
import PTCore
import PTReader
import PTUI
import SwiftUI

// MARK: - PDFKit platform wrapper

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for PDFKit's PDFView on iOS.
struct NativePDFView: UIViewRepresentable {
    let document: PDFDocument
    let renderedAnnotations: [PDFRenderedAnnotation]
    let selectionResetToken: Int
    let onSelectionChange: (PDFSelectionSnapshot) -> Void
    let onAnnotationTap: (Int64) -> Void
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = UIColor(Morandi.background)
        pdfView.document = document
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(tapRecognizer)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        let targetIndex = max(0, min(currentPage, document.pageCount - 1))
        if let page = document.page(at: targetIndex),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onAnnotationTap = onAnnotationTap
        context.coordinator.syncRenderedAnnotations(renderedAnnotations, on: pdfView)
        if context.coordinator.lastSelectionResetToken != selectionResetToken {
            context.coordinator.lastSelectionResetToken = selectionResetToken
            pdfView.clearSelection()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPage: $currentPage,
            document: document,
            onSelectionChange: onSelectionChange,
            onAnnotationTap: onAnnotationTap
        )
    }

    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        let document: PDFDocument
        var onSelectionChange: (PDFSelectionSnapshot) -> Void
        var onAnnotationTap: (Int64) -> Void
        var lastSelectionResetToken: Int = 0

        private var appliedAnnotationsByPage: [Int: [PDFAnnotation]] = [:]
        private var suppressNextSelectionChange = false

        init(
            currentPage: Binding<Int>,
            document: PDFDocument,
            onSelectionChange: @escaping (PDFSelectionSnapshot) -> Void,
            onAnnotationTap: @escaping (Int64) -> Void
        ) {
            self._currentPage = currentPage
            self.document = document
            self.onSelectionChange = onSelectionChange
            self.onAnnotationTap = onAnnotationTap
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            DispatchQueue.main.async { self.currentPage = index }
        }

        @objc func selectionChanged(_ notification: Notification) {
            if suppressNextSelectionChange {
                suppressNextSelectionChange = false
                return
            }

            guard let pdfView = notification.object as? PDFView,
                  let selection = pdfView.currentSelection,
                  let snapshot = PDFAnnotationBridge.selectionSnapshot(from: selection, in: document) else {
                return
            }

            DispatchQueue.main.async {
                self.onSelectionChange(snapshot)
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let pdfView = recognizer.view as? PDFView else {
                return
            }

            let location = recognizer.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else {
                return
            }

            let pagePoint = pdfView.convert(location, to: page)
            guard let annotation = page.annotation(at: pagePoint),
                  let noteID = noteID(from: annotation) else {
                return
            }

            suppressNextSelectionChange = true
            DispatchQueue.main.async {
                self.onAnnotationTap(noteID)
            }
        }

        func syncRenderedAnnotations(_ renderedAnnotations: [PDFRenderedAnnotation], on pdfView: PDFView) {
            for (pageIndex, annotations) in appliedAnnotationsByPage {
                guard let page = document.page(at: pageIndex) else { continue }
                for annotation in annotations {
                    page.removeAnnotation(annotation)
                }
            }

            var nextAppliedAnnotationsByPage: [Int: [PDFAnnotation]] = [:]
            for renderedAnnotation in renderedAnnotations {
                guard let page = document.page(at: renderedAnnotation.pageIndex) else { continue }
                let annotation = PDFAnnotation(
                    bounds: renderedAnnotation.bounds,
                    forType: renderedAnnotation.type == .bookmark ? .text : .highlight,
                    withProperties: nil
                )
                annotation.color = color(from: renderedAnnotation.colorHex) ?? .systemYellow
                if let noteID = renderedAnnotation.noteID {
                    annotation.userName = String(noteID)
                }
                annotation.contents = renderedAnnotation.readerNote ?? (renderedAnnotation.type == .bookmark ? "Bookmark" : nil)
                page.addAnnotation(annotation)
                nextAppliedAnnotationsByPage[renderedAnnotation.pageIndex, default: []].append(annotation)
            }

            appliedAnnotationsByPage = nextAppliedAnnotationsByPage
            pdfView.setNeedsDisplay()
        }

        private func color(from hex: String) -> UIColor? {
            let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard clean.count == 6 || clean.count == 8 else { return nil }
            var rgbValue: UInt64 = 0
            Scanner(string: clean).scanHexInt64(&rgbValue)
            if clean.count == 8 {
                return UIColor(
                    red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
                    green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
                    blue: CGFloat(rgbValue & 0xFF) / 255.0,
                    alpha: CGFloat((rgbValue >> 24) & 0xFF) / 255.0
                )
            }
            return UIColor(
                red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgbValue & 0xFF) / 255.0,
                alpha: 1.0
            )
        }

        private func noteID(from annotation: PDFAnnotation) -> Int64? {
            guard let userName = annotation.userName else {
                return nil
            }
            return Int64(userName)
        }
    }
}

#elseif canImport(AppKit)
import AppKit

/// SwiftUI wrapper for PDFKit's PDFView on macOS.
struct NativePDFView: NSViewRepresentable {
    let document: PDFDocument
    let renderedAnnotations: [PDFRenderedAnnotation]
    let selectionResetToken: Int
    let onSelectionChange: (PDFSelectionSnapshot) -> Void
    let onAnnotationTap: (Int64) -> Void
    @Binding var currentPage: Int

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.document = document
        pdfView.backgroundColor = NSColor(Morandi.background)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        pdfView.addGestureRecognizer(clickRecognizer)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        let targetIndex = max(0, min(currentPage, document.pageCount - 1))
        if let page = document.page(at: targetIndex),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onAnnotationTap = onAnnotationTap
        context.coordinator.syncRenderedAnnotations(renderedAnnotations, on: pdfView)
        if context.coordinator.lastSelectionResetToken != selectionResetToken {
            context.coordinator.lastSelectionResetToken = selectionResetToken
            pdfView.clearSelection()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentPage: $currentPage,
            document: document,
            onSelectionChange: onSelectionChange,
            onAnnotationTap: onAnnotationTap
        )
    }

    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        let document: PDFDocument
        var onSelectionChange: (PDFSelectionSnapshot) -> Void
        var onAnnotationTap: (Int64) -> Void
        var lastSelectionResetToken: Int = 0

        private var appliedAnnotationsByPage: [Int: [PDFAnnotation]] = [:]
        private var suppressNextSelectionChange = false

        init(
            currentPage: Binding<Int>,
            document: PDFDocument,
            onSelectionChange: @escaping (PDFSelectionSnapshot) -> Void,
            onAnnotationTap: @escaping (Int64) -> Void
        ) {
            self._currentPage = currentPage
            self.document = document
            self.onSelectionChange = onSelectionChange
            self.onAnnotationTap = onAnnotationTap
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            DispatchQueue.main.async { self.currentPage = index }
        }

        @objc func selectionChanged(_ notification: Notification) {
            if suppressNextSelectionChange {
                suppressNextSelectionChange = false
                return
            }

            guard let pdfView = notification.object as? PDFView,
                  let selection = pdfView.currentSelection,
                  let snapshot = PDFAnnotationBridge.selectionSnapshot(from: selection, in: document) else {
                return
            }

            DispatchQueue.main.async {
                self.onSelectionChange(snapshot)
            }
        }

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended,
                  let pdfView = recognizer.view as? PDFView else {
                return
            }

            let location = recognizer.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else {
                return
            }

            let pagePoint = pdfView.convert(location, to: page)
            guard let annotation = page.annotation(at: pagePoint),
                  let noteID = noteID(from: annotation) else {
                return
            }

            suppressNextSelectionChange = true
            DispatchQueue.main.async {
                self.onAnnotationTap(noteID)
            }
        }

        func syncRenderedAnnotations(_ renderedAnnotations: [PDFRenderedAnnotation], on pdfView: PDFView) {
            for (pageIndex, annotations) in appliedAnnotationsByPage {
                guard let page = document.page(at: pageIndex) else { continue }
                for annotation in annotations {
                    page.removeAnnotation(annotation)
                }
            }

            var nextAppliedAnnotationsByPage: [Int: [PDFAnnotation]] = [:]
            for renderedAnnotation in renderedAnnotations {
                guard let page = document.page(at: renderedAnnotation.pageIndex) else { continue }
                let annotation = PDFAnnotation(
                    bounds: renderedAnnotation.bounds,
                    forType: renderedAnnotation.type == .bookmark ? .text : .highlight,
                    withProperties: nil
                )
                annotation.color = color(from: renderedAnnotation.colorHex) ?? .systemYellow
                if let noteID = renderedAnnotation.noteID {
                    annotation.userName = String(noteID)
                }
                annotation.contents = renderedAnnotation.readerNote ?? (renderedAnnotation.type == .bookmark ? "Bookmark" : nil)
                page.addAnnotation(annotation)
                nextAppliedAnnotationsByPage[renderedAnnotation.pageIndex, default: []].append(annotation)
            }

            appliedAnnotationsByPage = nextAppliedAnnotationsByPage
            pdfView.needsDisplay = true
        }

        private func color(from hex: String) -> NSColor? {
            let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard clean.count == 6 || clean.count == 8 else { return nil }
            var rgbValue: UInt64 = 0
            Scanner(string: clean).scanHexInt64(&rgbValue)
            if clean.count == 8 {
                return NSColor(
                    red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
                    green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
                    blue: CGFloat(rgbValue & 0xFF) / 255.0,
                    alpha: CGFloat((rgbValue >> 24) & 0xFF) / 255.0
                )
            }
            return NSColor(
                red: CGFloat((rgbValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgbValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgbValue & 0xFF) / 255.0,
                alpha: 1.0
            )
        }

        private func noteID(from annotation: PDFAnnotation) -> Int64? {
            guard let userName = annotation.userName else {
                return nil
            }
            return Int64(userName)
        }
    }
}
#endif

// MARK: - Full reader view

/// Full-screen PDF reader with toolbar, TOC sheet, and reading progress.
public struct PDFReaderView: View {
    @State private var viewModel: ReaderViewModel
    @State private var isAIPanelPresented = false
    @State private var readerControlsViewModel: PDFReaderControlsViewModel?
    @State private var annotationsViewModel: PDFReaderAnnotationsViewModel?
    @State private var annotationDraft: EPUBReaderAnnotationDraft?
    @State private var annotationErrorMessage: String?
    @State private var selectionResetToken = 0
    @State private var isFullScreen = false
    @State private var showPageSlider = true
    @State private var aiQuickActionText: String?
    @State private var aiQuickActionChapter: String = ""
    @State private var currentSearchResultIndex: Int = 0
    @State private var contextMenuCoordinator: ContextMenuCoordinator?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let aiChatViewModel: AIChatViewModel
    private let database: AppDatabase

    public init(
        book: Book,
        database: AppDatabase,
        aiChatViewModel: AIChatViewModel,
        readerSessionStore: ReaderSessionContextStore? = nil
    ) {
        self.database = database
        self.aiChatViewModel = aiChatViewModel
        _viewModel = State(
            initialValue: ReaderViewModel(
                book: book,
                database: database,
                readerSessionStore: readerSessionStore
            )
        )
    }

    public var body: some View {
        ReaderAIPanelHost(
            book: viewModel.book,
            aiChatViewModel: aiChatViewModel,
            isPresented: $isAIPanelPresented
        ) {
            readerContent
        }
        .navigationTitle(viewModel.book.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isFullScreen)
#endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showTOC) { tocSheet }
        .sheet(isPresented: searchSheetBinding) { searchSheet }
        .sheet(isPresented: annotationEditorPresentedBinding) { annotationEditorSheet }
        .sheet(isPresented: aiQuickActionsPresentedBinding) { aiQuickActionsSheet }
        .sheet(item: contextMenuSheetBinding) { sheet in
            contextMenuSheetContent(sheet)
        }
        .overlay(alignment: .center) {
            if let coordinator = contextMenuCoordinator, coordinator.isMenuVisible {
                ReaderContextMenuView(coordinator: coordinator) {
                    coordinator.dismiss()
                    selectionResetToken += 1
                }
                .transition(.scale.combined(with: .opacity))
                .zIndex(100)
            }
        }
        .task { await loadReader() }
        .onDisappear {
            Task {
                await viewModel.saveProgress()
                await viewModel.endReadingSession()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if isAIPanelPresented == false {
                    ReaderAIMinimizedBar(aiChatViewModel: aiChatViewModel) {
                        isAIPanelPresented = true
                    }
                }
                if showPageSlider && !isFullScreen && viewModel.pageCount > 1 {
                    ReaderPageSlider(
                        currentPage: $viewModel.currentPage,
                        pageCount: viewModel.pageCount,
                        onPageChange: { page in viewModel.goToPage(page) }
                    )
                }
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isFullScreen.toggle()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                if newPhase == .background {
                    await viewModel.saveProgress()
                }
                await viewModel.handleScenePhaseChange(newPhase)
            }
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
    }

    // MARK: - Toolbar

    private var readerContent: some View {
        ZStack {
            Morandi.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("Opening…")
                    .tint(Morandi.accent)

            } else if let doc = viewModel.pdfDocument {
                NativePDFView(
                    document: doc,
                    renderedAnnotations: annotationsViewModel?.renderedAnnotations ?? [],
                    selectionResetToken: selectionResetToken,
                    onSelectionChange: presentAnnotationDraft(selection:),
                    onAnnotationTap: presentAnnotationDraft(noteID:),
                    currentPage: $viewModel.currentPage
                )
                .ignoresSafeArea(edges: .bottom)

            } else {
                ContentUnavailableView(
                    "Cannot Open",
                    systemImage: "doc.text.slash",
                    description: Text("The file could not be opened.")
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                Task { await viewModel.saveProgress() }
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFullScreen.toggle()
                }
            } label: {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(isFullScreen ? "Exit Full Screen" : "Full Screen")

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
                presentBookmarkDraft()
            } label: {
                Image(systemName: "bookmark")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel("Add Bookmark")
            .disabled(viewModel.pdfDocument == nil)

            Button {
                viewModel.showTOC = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Morandi.accent)
            }
        }

        ToolbarItem(placement: .status) {
            if viewModel.pageCount > 0 {
                Text("\(viewModel.currentPage + 1) / \(viewModel.pageCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    private func loadReader() async {
        await viewModel.loadDocument()

        guard let bridge = viewModel.contentBridge else {
            readerControlsViewModel = nil
            return
        }

        if readerControlsViewModel == nil {
            readerControlsViewModel = PDFReaderControlsViewModel(bridge: bridge)
        }

        if contextMenuCoordinator == nil, let bookID = viewModel.book.id {
            contextMenuCoordinator = ContextMenuCoordinator(
                bookId: bookID,
                bookTitle: viewModel.book.title,
                bookAuthor: viewModel.book.author,
                database: database,
                onSendToAI: { [aiChatViewModel] prompt in
                    _ = await aiChatViewModel.sendMessage(prompt)
                }
            )
        }

        if annotationsViewModel == nil,
           let bookID = viewModel.book.id,
           let document = viewModel.pdfDocument {
            let annotationsViewModel = PDFReaderAnnotationsViewModel(
                bookId: bookID,
                database: database,
                document: document
            )
            await annotationsViewModel.loadAnnotations()
            self.annotationsViewModel = annotationsViewModel
        }
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

    private var annotationEditorPresentedBinding: Binding<Bool> {
        Binding(
            get: { annotationDraft != nil },
            set: { isPresented in
                guard isPresented == false else { return }
                annotationDraft = nil
                selectionResetToken += 1
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

    // MARK: - TOC Sheet

    private var tocSheet: some View {
        NavigationStack {
            Group {
                if viewModel.tocEntries.isEmpty {
                    ContentUnavailableView(
                        "No Contents",
                        systemImage: "list.bullet.indent",
                        description: Text("This PDF has no table of contents.")
                    )
                } else {
                    List(viewModel.tocEntries) { entry in
                        Button {
                            viewModel.goToChapter(href: entry.href)
                            viewModel.showTOC = false
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                if entry.level > 0 {
                                    Spacer().frame(width: CGFloat(entry.level) * AppSpacing.lg)
                                }
                                Text(entry.title)
                                    .font(entry.level == 0 ? AppTypography.headline : AppTypography.body)
                                    .foregroundStyle(
                                        entry.level == 0 ? Morandi.primaryText : Morandi.secondaryText
                                    )
                                Spacer()
                            }
                        }
                        .listRowBackground(Morandi.background)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Morandi.background)
            .navigationTitle("Contents")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { viewModel.showTOC = false }
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
                            "Search This PDF",
                            systemImage: "magnifyingglass",
                            description: Text("Enter a phrase to search across the PDF contents.")
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
                                navigateToSearchResult(result)
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

                                    Text("Match at \(Int((result.progression * 100).rounded()))% of document")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(Morandi.secondaryText)
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
            .searchable(text: searchQueryBinding, prompt: "Search in this PDF")
            .onSubmit(of: .search) {
                Task { await readerControlsViewModel?.performSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: AppSpacing.sm) {
                        if let controls = readerControlsViewModel,
                           !controls.searchResults.isEmpty {
                            Text("\(currentSearchResultIndex + 1)/\(controls.searchResults.count)")
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.secondaryText)
                                .monospacedDigit()

                            Button {
                                navigateToPreviousSearchResult()
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(currentSearchResultIndex <= 0)
                            .foregroundStyle(Morandi.accent)

                            Button {
                                navigateToNextSearchResult()
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(currentSearchResultIndex >= (controls.searchResults.count - 1))
                            .foregroundStyle(Morandi.accent)
                        }

                        Button("Search") {
                            currentSearchResultIndex = 0
                            Task { await readerControlsViewModel?.performSearch() }
                        }
                        .foregroundStyle(Morandi.accent)
                        .disabled((readerControlsViewModel?.searchQuery.isEmpty ?? true) || (readerControlsViewModel?.isSearching ?? false))
                    }
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
                selectionResetToken += 1
            }
        )
    }

    private func navigateToSearchResult(_ result: ContentSearchResult) {
        guard let range = PDFChapter.parsePageRange(from: result.chapterHref) else { return }
        viewModel.goToPage(range.startPage)
    }

    private func presentAnnotationDraft(selection: PDFSelectionSnapshot) {
        // Store selection context for AI quick actions
        aiQuickActionText = selection.selectedText
        aiQuickActionChapter = selection.pageLabel

        // Show context menu if coordinator is available
        contextMenuCoordinator?.showMenu(
            text: selection.selectedText,
            locator: selection.anchorString,
            chapter: selection.pageLabel
        )

        annotationDraft = EPUBReaderAnnotationDraft(
            locatorString: selection.anchorString,
            selectedText: selection.selectedText,
            chapterTitle: selection.pageLabel,
            type: .highlight,
            color: .yellow
        )
    }

    private func presentBookmarkDraft() {
        let pageIndex = viewModel.currentPage
        let pageLabel = viewModel.pdfDocument?.page(at: pageIndex)?.label ?? "Page \(pageIndex + 1)"
        annotationDraft = EPUBReaderAnnotationDraft(
            locatorString: PDFAnnotationBridge.storedString(from: .bookmark(pageIndex: pageIndex, pageLabel: pageLabel)),
            selectedText: "",
            chapterTitle: pageLabel,
            type: .bookmark,
            color: .yellow
        )
    }

    private func presentAnnotationDraft(noteID: Int64) {
        annotationDraft = annotationsViewModel?.annotationDraft(noteID: noteID)
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

        self.annotationDraft = nil
        selectionResetToken += 1
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

        annotationDraft = nil
        selectionResetToken += 1
    }

    // MARK: - AI Quick Actions

    private var aiQuickActionsPresentedBinding: Binding<Bool> {
        Binding(
            get: { aiQuickActionText != nil && annotationDraft == nil },
            set: { isPresented in
                if !isPresented { aiQuickActionText = nil }
            }
        )
    }

    private var aiQuickActionsSheet: some View {
        ReaderAIQuickActionsSheet(
            selectedText: aiQuickActionText ?? "",
            chapterTitle: aiQuickActionChapter,
            bookTitle: viewModel.book.title,
            onAction: { action in
                let prompt = action.prompt(
                    selectedText: aiQuickActionText ?? "",
                    bookTitle: viewModel.book.title,
                    chapterTitle: aiQuickActionChapter
                )
                aiQuickActionText = nil
                isAIPanelPresented = true
                Task {
                    await aiChatViewModel.sendMessage(prompt)
                }
            },
            onDismiss: {
                aiQuickActionText = nil
            }
        )
    }

    // MARK: - Context Menu Sheet

    private var contextMenuSheetBinding: Binding<ContextMenuCoordinator.ActiveSheet?> {
        Binding(
            get: { contextMenuCoordinator?.activeSheet },
            set: { newValue in contextMenuCoordinator?.activeSheet = newValue }
        )
    }

    @ViewBuilder
    private func contextMenuSheetContent(_ sheet: ContextMenuCoordinator.ActiveSheet) -> some View {
        if let coordinator = contextMenuCoordinator {
            switch sheet {
            case .translation:
                TranslationMenuSheet(
                    selectedText: coordinator.selectedText,
                    translationService: coordinator.translationService,
                    onDismiss: { coordinator.activeSheet = nil }
                )
            case .excerpt:
                ExcerptMenuSheet(
                    selectedText: coordinator.selectedText,
                    bookTitle: viewModel.book.title,
                    author: viewModel.book.author,
                    chapterTitle: coordinator.chapterTitle,
                    onSaveToNotes: {
                        Task { await coordinator.saveExcerptToNotes() }
                    },
                    onDismiss: { coordinator.activeSheet = nil }
                )
            case .note:
                NoteEditorSheet(
                    selectedText: coordinator.selectedText,
                    chapterTitle: coordinator.chapterTitle,
                    onSave: { color, noteText in
                        Task { await coordinator.saveNote(color: color, noteText: noteText) }
                    },
                    onDismiss: { coordinator.activeSheet = nil }
                )
            case .noteEdit(let noteID):
                NoteEditorSheet(
                    selectedText: coordinator.selectedText,
                    chapterTitle: coordinator.chapterTitle,
                    existingNoteID: noteID,
                    onSave: { color, noteText in
                        Task { await coordinator.saveNote(color: color, noteText: noteText, existingID: noteID) }
                    },
                    onDelete: {
                        Task { await coordinator.deleteNote(id: noteID) }
                    },
                    onDismiss: { coordinator.activeSheet = nil }
                )
            }
        }
    }

    // MARK: - Search Result Navigation

    private func navigateToNextSearchResult() {
        guard let controls = readerControlsViewModel,
              !controls.searchResults.isEmpty else { return }
        currentSearchResultIndex = min(currentSearchResultIndex + 1, controls.searchResults.count - 1)
        navigateToSearchResult(controls.searchResults[currentSearchResultIndex])
    }

    private func navigateToPreviousSearchResult() {
        guard let controls = readerControlsViewModel,
              !controls.searchResults.isEmpty else { return }
        currentSearchResultIndex = max(currentSearchResultIndex - 1, 0)
        navigateToSearchResult(controls.searchResults[currentSearchResultIndex])
    }
}

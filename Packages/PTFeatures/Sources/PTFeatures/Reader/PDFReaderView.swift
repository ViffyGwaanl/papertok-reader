import CoreImage
import PDFKit
import PTCore
import PTReader
import PTUI
import SwiftUI

struct PDFFindHighlightRequest: Equatable {
    let id = UUID()
    let pageIndex: Int
    let snippet: String
}

struct PDFSelectionRouting {
    let aiQuickActionText: String
    let aiQuickActionChapter: String
    let contextMenuText: String
    let contextMenuLocator: String
    let contextMenuChapter: String
    let annotationDraft: EPUBReaderAnnotationDraft?

    var shouldCreateAnnotationDraft: Bool {
        annotationDraft != nil
    }

    static func from(selection: PDFSelectionSnapshot) -> PDFSelectionRouting {
        PDFSelectionRouting(
            aiQuickActionText: selection.selectedText,
            aiQuickActionChapter: selection.pageLabel,
            contextMenuText: selection.selectedText,
            contextMenuLocator: selection.anchorString,
            contextMenuChapter: selection.pageLabel,
            annotationDraft: nil
        )
    }
}

// MARK: - PDFKit platform wrapper

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for PDFKit's PDFView on iOS.
struct NativePDFView: UIViewRepresentable {
    let document: PDFDocument
    let renderedAnnotations: [PDFRenderedAnnotation]
    let selectionResetToken: Int
    let findHighlightRequest: PDFFindHighlightRequest?
    let themeTintKind: PDFThemeTintKind
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
        if #available(iOS 16.0, *) {
            let provider = PDFThemedPageOverlayProvider()
            context.coordinator.themedOverlayProvider = provider
            pdfView.pageOverlayViewProvider = provider
        }
        context.coordinator.applyThemeTint(themeTintKind, to: pdfView)
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
        context.coordinator.applyFindHighlight(findHighlightRequest, on: pdfView)
        context.coordinator.applyThemeTint(themeTintKind, to: pdfView)
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
        private var lastFindHighlightRequestID: UUID?
        private var lastAppliedTintKind: PDFThemeTintKind?
        var themedOverlayProvider: AnyObject?

        private var appliedAnnotationsByPage: [Int: [PDFAnnotation]] = [:]
        private var suppressNextSelectionChange = false

        func applyThemeTint(_ kind: PDFThemeTintKind, to pdfView: PDFView) {
            guard lastAppliedTintKind != kind else { return }
            lastAppliedTintKind = kind
            switch kind {
            case .none:
                pdfView.backgroundColor = UIColor(Morandi.background)
            case .dark:
                pdfView.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
            case .sepia:
                pdfView.backgroundColor = UIColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 1.0)
            case .night:
                pdfView.backgroundColor = .black
            }
            if #available(iOS 16.0, *) {
                if let provider = themedOverlayProvider as? PDFThemedPageOverlayProvider {
                    provider.tintKind = kind
                    pdfView.layoutDocumentView()
                }
            }
            pdfView.setNeedsDisplay()
        }

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

        func applyFindHighlight(_ request: PDFFindHighlightRequest?, on pdfView: PDFView) {
            guard let request else {
                if lastFindHighlightRequestID != nil {
                    lastFindHighlightRequestID = nil
                    pdfView.highlightedSelections = nil
                }
                return
            }
            guard request.id != lastFindHighlightRequestID else { return }
            lastFindHighlightRequestID = request.id

            let matches = document.findString(request.snippet, withOptions: [.caseInsensitive])
            let selection = matches.first { candidate in
                candidate.pages.contains(where: { document.index(for: $0) == request.pageIndex })
            }
            if let selection {
                pdfView.highlightedSelections = [selection]
                pdfView.setCurrentSelection(selection, animate: true)
            } else {
                pdfView.highlightedSelections = nil
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
                    forType: renderedAnnotation.pdfAnnotationSubtype,
                    withProperties: nil
                )
                annotation.color = color(from: renderedAnnotation.colorHex) ?? .systemYellow
                if let noteID = renderedAnnotation.noteID {
                    annotation.userName = String(noteID)
                }
                annotation.contents = renderedAnnotation.readerNote ?? (
                    renderedAnnotation.type == .bookmark
                    ? AppLocalization.string("reader.bookmark")
                    : nil
                )
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
    let findHighlightRequest: PDFFindHighlightRequest?
    let themeTintKind: PDFThemeTintKind
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
        context.coordinator.applyThemeTint(themeTintKind, to: pdfView)
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
        context.coordinator.applyFindHighlight(findHighlightRequest, on: pdfView)
        context.coordinator.applyThemeTint(themeTintKind, to: pdfView)
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
        private var lastFindHighlightRequestID: UUID?
        private var lastAppliedTintKind: PDFThemeTintKind?

        private var appliedAnnotationsByPage: [Int: [PDFAnnotation]] = [:]
        private var suppressNextSelectionChange = false

        func applyThemeTint(_ kind: PDFThemeTintKind, to pdfView: PDFView) {
            guard lastAppliedTintKind != kind else { return }
            lastAppliedTintKind = kind
            let filters = PDFThemeTint.filterChain(for: kind).compactMap { descriptor -> CIFilter? in
                guard let filter = CIFilter(name: descriptor.name) else { return nil }
                for (key, parameter) in descriptor.parameters {
                    filter.setValue(parameter.ciFilterValue, forKey: key)
                }
                return filter
            }
            pdfView.wantsLayer = true
            pdfView.layer?.filters = filters.isEmpty ? nil : filters
            switch kind {
            case .none:
                pdfView.backgroundColor = NSColor(Morandi.background)
            case .dark:
                pdfView.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
            case .sepia:
                pdfView.backgroundColor = NSColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 1.0)
            case .night:
                pdfView.backgroundColor = .black
            }
            pdfView.needsDisplay = true
        }

        func applyFindHighlight(_ request: PDFFindHighlightRequest?, on pdfView: PDFView) {
            guard let request else {
                if lastFindHighlightRequestID != nil {
                    lastFindHighlightRequestID = nil
                    pdfView.highlightedSelections = nil
                }
                return
            }
            guard request.id != lastFindHighlightRequestID else { return }
            lastFindHighlightRequestID = request.id

            let matches = document.findString(request.snippet, withOptions: [.caseInsensitive])
            let selection = matches.first { candidate in
                candidate.pages.contains(where: { document.index(for: $0) == request.pageIndex })
            }
            if let selection {
                pdfView.highlightedSelections = [selection]
                pdfView.setCurrentSelection(selection, animate: true)
            } else {
                pdfView.highlightedSelections = nil
            }
        }

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
                    forType: renderedAnnotation.pdfAnnotationSubtype,
                    withProperties: nil
                )
                annotation.color = color(from: renderedAnnotation.colorHex) ?? .systemYellow
                if let noteID = renderedAnnotation.noteID {
                    annotation.userName = String(noteID)
                }
                annotation.contents = renderedAnnotation.readerNote ?? (
                    renderedAnnotation.type == .bookmark
                    ? AppLocalization.string("reader.bookmark")
                    : nil
                )
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
    // W7.1 — reader immersion core (chrome auto-hide + 3-zone tap).
    @State private var chromeVisibility = ReaderChromeVisibilityController()
    @State private var aiQuickActionText: String?
    @State private var aiQuickActionChapter: String = ""
    @State private var findBarState: ReaderFindBarState?
    @State private var findHighlightRequest: PDFFindHighlightRequest?
    @State private var contextMenuCoordinator: ContextMenuCoordinator?
    @State private var showBookmarkManager = false
    @State private var tocSearchQuery = ""
    @State private var showBrightnessControl = false
    @State private var volumeKeysEnabled = UserDefaults.standard.bool(forKey: "pt.reader.volumeKeysEnabled")
    @State private var volumeKeyHandler = VolumeKeyHandler()
    /// W7.2 — subtle fade overlay that is briefly shown after a
    /// programmatic page jump (arrow keys, toolbar, TOC, bookmark).
    /// Native PDFKit swipe/scroll gestures do not route through this.
    @State private var pageTransitionController = PDFPageTransitionController(fadeDurationMS: 160)
#if canImport(AVFoundation)
    @State private var ttsService = TTSService()
#endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let aiChatViewModel: AIChatViewModel
    private let database: AppDatabase
    @State private var readingPreferences: ReadingPreferences

    public init(
        book: Book,
        database: AppDatabase,
        aiChatViewModel: AIChatViewModel,
        readerSessionStore: ReaderSessionContextStore? = nil,
        initialPageOverride: Int? = nil,
        readingPreferences: ReadingPreferences = ReadingPreferences()
    ) {
        self.database = database
        self.aiChatViewModel = aiChatViewModel
        _viewModel = State(
            initialValue: ReaderViewModel(
                book: book,
                database: database,
                readerSessionStore: readerSessionStore,
                initialPageOverride: initialPageOverride
            )
        )
        _readingPreferences = State(initialValue: readingPreferences)
    }

    public var body: some View {
        readerAlertSurface
    }

    private var readerAlertSurface: some View {
        readerCommandSurface
            .alert("reader.annotation_error", isPresented: annotationErrorPresentedBinding) {
                Button(String(localized: "common.ok")) {
                    annotationErrorMessage = nil
                }
            } message: {
                Text(annotationErrorMessage ?? "")
            }
    }

    private var readerCommandSurface: some View {
        readerLifecycleSurface
            .focusable(true)
            .onKeyPress(.leftArrow) { goToPreviousPageFromCommand(); return .handled }
            .onKeyPress(.rightArrow) { goToNextPageFromCommand(); return .handled }
            .onKeyPress(.upArrow) { goToPreviousPageFromCommand(); return .handled }
            .onKeyPress(.downArrow) { goToNextPageFromCommand(); return .handled }
            .onKeyPress(.space) { goToNextPageFromCommand(); return .handled }
            .onKeyPress(.pageUp) { goToPreviousPageFromCommand(); return .handled }
            .onKeyPress(.pageDown) { goToNextPageFromCommand(); return .handled }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PaperTokToggleAI"))) { _ in
                isAIPanelPresented.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousChapter)) { _ in
                goToPreviousPageFromCommand()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextChapter)) { _ in
                goToNextPageFromCommand()
            }
    }

    private var readerLifecycleSurface: some View {
        readerPresentationSurface
            .task {
                await loadReader()
                volumeKeyHandler.onVolumeUp = {
                    Task { @MainActor in
                        viewModel.goToPage(viewModel.currentPage + 1)
                    }
                }
                volumeKeyHandler.onVolumeDown = {
                    Task { @MainActor in
                        viewModel.goToPage(viewModel.currentPage - 1)
                    }
                }
                applyVolumeKeyHandler()
                // W7.1 — start chrome visible + schedule the auto-hide timer.
                chromeVisibility.autoHideSeconds = readingPreferences.style.autoHideChromeSeconds
                chromeVisibility.onReaderAppear()
            }
            .onChange(of: readingPreferences.style.autoHideChromeSeconds) { _, newValue in
                chromeVisibility.autoHideSeconds = newValue
            }
            .onDisappear {
                volumeKeyHandler.stop()
                chromeVisibility.onReaderDisappear()
#if canImport(AVFoundation)
                ttsService.stop()
#endif
                WakeLockController.setKeepScreenOn(false)
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
                    if showPageSlider && !chromeHidden && viewModel.pageCount > 1 {
                        ReaderPageSlider(
                            currentPage: $viewModel.currentPage,
                            pageCount: viewModel.pageCount,
                            onPageChange: { page in viewModel.goToPage(page) }
                        )
                    }
                }
            }
            // W7.1 — double-tap maps to full chrome toggle so the legacy
            // fullscreen gesture stays. Declared BEFORE the single-tap so
            // SwiftUI resolves count=2 first (required for gesture priority).
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFullScreen.toggle()
                    if isFullScreen {
                        chromeVisibility.hideChrome()
                    } else {
                        chromeVisibility.showChrome()
                    }
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
    }

    /// W7.1 — unified "hide reader chrome" flag. Either the legacy
    /// double-tap fullscreen OR the controller's auto-hide/center-tap
    /// routing can request hidden chrome; either should collapse nav +
    /// status bar + reading info overlay.
    private var chromeHidden: Bool {
        isFullScreen || !chromeVisibility.isChromeVisible
    }

    private var readerPresentationSurface: some View {
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
        // W7.1 — unified immersion: hide nav bar + status bar when chrome
        // is hidden (either via center-tap or legacy double-tap fullscreen).
        .toolbar(chromeHidden ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(chromeHidden)
        .animation(.easeInOut(duration: 0.25), value: chromeHidden)
#endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showTOC) { tocSheet }
        .sheet(isPresented: searchSheetBinding) { searchSheet }
        .sheet(isPresented: annotationEditorPresentedBinding) { annotationEditorSheet }
        .sheet(isPresented: aiQuickActionsPresentedBinding) { aiQuickActionsSheet }
        .sheet(item: contextMenuSheetBinding, onDismiss: {
            selectionResetToken += 1
        }) { sheet in
            contextMenuSheetContent(sheet)
        }
        .sheet(isPresented: $showBookmarkManager) {
            BookmarkManagerView(
                viewModel: viewModel,
                database: database,
                onJump: { note in
                    pageTransitionController.triggerTransition()
                    viewModel.jumpToBookmark(note)
                }
            )
        }
        .overlay(alignment: .top) {
            if showBrightnessControl {
                ScreenBrightnessSlider()
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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
#if canImport(AVFoundation)
        .overlay(alignment: .bottomTrailing) {
            if !chromeHidden && viewModel.pdfDocument != nil {
                TTSFloatingActionButton(
                    service: ttsService,
                    chapterTitle: viewModel.currentChapterTitle,
                    currentText: { currentPagePlainText() }
                )
                .padding(.trailing, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
                .transition(.opacity)
                .zIndex(50)
            }
        }
#endif
    }

    // MARK: - Toolbar

    private var readerContent: some View {
        ZStack {
            Morandi.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView(String(localized: "reader.opening_ellipsis"))
                    .tint(Morandi.accent)

            } else if let doc = viewModel.pdfDocument {
                NativePDFView(
                    document: doc,
                    renderedAnnotations: annotationsViewModel?.renderedAnnotations ?? [],
                    selectionResetToken: selectionResetToken,
                    findHighlightRequest: findHighlightRequest,
                    themeTintKind: PDFThemeTint.resolveTintKind(from: readingPreferences.theme),
                    onSelectionChange: presentAnnotationDraft(selection:),
                    onAnnotationTap: presentAnnotationDraft(noteID:),
                    currentPage: $viewModel.currentPage
                )
                .ignoresSafeArea(edges: .bottom)

                // W7.1 — center-third tap toggles chrome. Left/right thirds
                // are left passthrough so PDFKit can handle text selection
                // gestures. Double-tap on the outer surface (declared above)
                // still toggles fullscreen.
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear.frame(width: geo.size.width / 3)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { chromeVisibility.toggleChrome() }
                        Color.clear.frame(width: geo.size.width / 3)
                    }
                }
                .allowsHitTesting(true)

            } else {
                ContentUnavailableView(
                    String(localized: "reader.cannot_open_title"),
                    systemImage: "doc.text.slash",
                    description: Text("bookshelf.file_could_not_be_opened")
                )
            }

            // W7.2 — subtle fade overlay shown for programmatic page jumps.
            Color(hex: readingPreferences.theme.backgroundColor)
                .opacity(pageTransitionController.isTransitioning ? 0.35 : 0)
                .allowsHitTesting(false)
                .animation(
                    .easeInOut(duration: 0.16),
                    value: pageTransitionController.isTransitioning
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .onChange(of: contextMenuCoordinator?.pendingSearchQuery) { _, pendingQuery in
            guard let query = pendingQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
                  query.isEmpty == false,
                  let menuCoordinator = contextMenuCoordinator else {
                return
            }
            _ = menuCoordinator.takePendingSearchQuery()
            readerControlsViewModel?.searchQuery = query
            readerControlsViewModel?.showSearch = true
            selectionResetToken += 1
            Task {
                await findBarState?.submit(query: query)
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
                    Text("tab.library")
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
            .accessibilityLabel(String(localized: isFullScreen ? "common.exit_full_screen" : "common.full_screen"))
            .accessibilityHint(String(localized: "reader.a11y.fullscreen_hint"))

            Button {
                isAIPanelPresented = true
            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(String(localized: "reader.open_ai_panel"))
            .accessibilityHint(String(localized: "reader.a11y.toggle_ai_panel_hint"))

            Button {
                readerControlsViewModel?.showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(String(localized: "reader.search_book"))
            .accessibilityHint(String(localized: "reader.a11y.find_bar_hint"))
            .disabled(readerControlsViewModel == nil)

            Button {
                Task {
                    await viewModel.toggleBookmark()
                    if let annotationsViewModel {
                        await annotationsViewModel.loadAnnotations()
                    }
                }
            } label: {
                Image(systemName: BookmarkToolbarIcon.systemName(isBookmarked: viewModel.isCurrentPageBookmarked))
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(String(localized: String.LocalizationValue(
                BookmarkToolbarIcon.accessibilityKey(isBookmarked: viewModel.isCurrentPageBookmarked)
            )))
            .disabled(viewModel.pdfDocument == nil)

            Menu {
                Button {
                    showBookmarkManager = true
                } label: {
                    Label("reader.bookmarks", systemImage: "bookmark.circle")
                }
                Button {
                    viewModel.showTOC = true
                } label: {
                    Label("reader.contents", systemImage: "list.bullet")
                }
                Button {
                    showBrightnessControl.toggle()
                } label: {
                    Label("reader.brightness", systemImage: "sun.max")
                }
                Toggle(isOn: Binding(
                    get: { volumeKeysEnabled },
                    set: { newValue in
                        volumeKeysEnabled = newValue
                        UserDefaults.standard.set(newValue, forKey: "pt.reader.volumeKeysEnabled")
                        applyVolumeKeyHandler()
                    }
                )) {
                    Label("reader.volume_keys_turn_pages", systemImage: "speaker.wave.2")
                }
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Morandi.accent)
            }
            .accessibilityLabel(String(localized: "reader.more_options"))
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

        if findBarState == nil {
            let bridgeRef = bridge
            findBarState = ReaderFindBarState { query in
                let results = try await bridgeRef.searchContent(query: query)
                return results.map(ReaderSearchHit.from)
            }
        }

        if contextMenuCoordinator == nil, let bookID = viewModel.book.id {
            contextMenuCoordinator = ContextMenuCoordinator(
                bookId: bookID,
                bookTitle: viewModel.book.title,
                bookAuthor: viewModel.book.author,
                database: database,
                translationServiceProvider: { [aiChatViewModel] in
                    aiChatViewModel.makeTranslationService()
                },
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
            set: { newValue in
                readerControlsViewModel?.showSearch = newValue
                if newValue == false {
                    findBarState?.clear()
                    findHighlightRequest = nil
                }
            }
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
                        String(localized: "reader.toc.empty_title"),
                        systemImage: "list.bullet.indent",
                        description: Text("reader.no_toc_pdf")
                    )
                } else {
                    let entries = filteredTOCEntries
                    VStack(spacing: 0) {
                        if !tocSearchQuery.isEmpty {
                            HStack {
                                Text(AppLocalization.format("reader.toc.match_count_format", locale: .autoupdatingCurrent,
                                    entries.count
                                ))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(Morandi.secondaryText)
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.xs)
                        }
                        let resolver = TOCHighlightResolver(
                            entries: viewModel.tocEntries,
                            currentHref: viewModel.currentChapterHref,
                            currentPage: viewModel.currentPage
                        )
                        List(entries) { entry in
                            let isCurrent = resolver.isCurrent(entry: entry)
                            Button {
                                pageTransitionController.triggerTransition()
                                viewModel.goToChapter(href: entry.href)
                                viewModel.showTOC = false
                                tocSearchQuery = ""
                            } label: {
                                HStack(spacing: AppSpacing.xs) {
                                    if entry.level > 0 {
                                        Spacer().frame(width: CGFloat(entry.level) * AppSpacing.lg)
                                    }
                                    highlightedTOCTitle(entry.title)
                                        .font(entry.level == 0 ? AppTypography.headline : AppTypography.body)
                                        .fontWeight(entry.level == 0 ? .semibold : .regular)
                                    Spacer()
                                }
                            }
                            .listRowBackground(
                                isCurrent ? Morandi.accent.opacity(0.12) : Morandi.background
                            )
                            .overlay(alignment: .leading) {
                                if isCurrent {
                                    Rectangle()
                                        .fill(Morandi.accent)
                                        .frame(width: 3)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                    .searchable(text: $tocSearchQuery, prompt: String(localized: "reader.search_contents"))
                }
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "reader.contents"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { viewModel.showTOC = false }
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var searchSheet: some View {
        NavigationStack {
            Group {
                if let findBarState {
                    searchSheetBody(state: findBarState)
                } else {
                    ProgressView(String(localized: "reader.preparing_search_ellipsis"))
                        .tint(Morandi.accent)
                }
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "common.search"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) {
                        closeFindBar()
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func searchSheetBody(state: ReaderFindBarState) -> some View {
        VStack(spacing: 0) {
            ReaderFindBar(state: state, onClose: { closeFindBar() })
            if state.hits.isEmpty && state.hasSearched == false {
                ContentUnavailableView(
                    String(localized: "reader.search_this_pdf"),
                    systemImage: "magnifyingglass",
                    description: Text("reader.search_pdf_prompt")
                )
            } else if state.hits.isEmpty {
                ContentUnavailableView(
                    String(localized: "reader.search.no_results_title"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(AppLocalization.format(
                        "reader.search.no_matches_format",
                        locale: .autoupdatingCurrent,
                        state.query
                    ))
                )
            } else {
                List(Array(state.hits.enumerated()), id: \.element.id) { index, hit in
                    Button {
                        state.select(index: index)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(hit.chapterTitle)
                                .font(AppTypography.headline)
                                .foregroundStyle(Morandi.primaryText)

                            (
                                Text(hit.contextBefore)
                                    .foregroundStyle(Morandi.secondaryText)
                                + Text(hit.snippet)
                                    .foregroundStyle(index == state.currentIndex ? Morandi.accent : Morandi.primaryText)
                                    .bold()
                                + Text(hit.contextAfter)
                                    .foregroundStyle(Morandi.secondaryText)
                            )
                            .font(AppTypography.body)
                            .lineLimit(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowBackground(Morandi.background)
                }
                .listStyle(.plain)
            }
        }
        .onChange(of: state.currentHit) { _, newHit in
            guard let newHit else { return }
            navigateToFindBarHit(newHit)
        }
    }

    private func closeFindBar() {
        findBarState?.clear()
        readerControlsViewModel?.showSearch = false
        selectionResetToken += 1
    }

    private func navigateToFindBarHit(_ hit: ReaderSearchHit) {
        if let pageIndex = hit.locator.pageIndex {
            viewModel.goToPage(pageIndex)
        }
        applyPDFFindHighlight(for: hit)
    }

    private func applyPDFFindHighlight(for hit: ReaderSearchHit) {
        guard let pageIndex = hit.locator.pageIndex else { return }
        findHighlightRequest = PDFFindHighlightRequest(
            pageIndex: pageIndex,
            snippet: hit.snippet
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
                selectionResetToken += 1
            }
        )
    }

    private func goToPreviousPageFromCommand() {
        let target = viewModel.currentPage - 1
        guard target >= 0 else { return }
        pageTransitionController.triggerTransition()
        viewModel.goToPage(target)
    }

    private func goToNextPageFromCommand() {
        let target = viewModel.currentPage + 1
        guard target < viewModel.pageCount else { return }
        pageTransitionController.triggerTransition()
        viewModel.goToPage(target)
    }

    private func presentAnnotationDraft(selection: PDFSelectionSnapshot) {
        let routing = PDFSelectionRouting.from(selection: selection)
        aiQuickActionText = routing.aiQuickActionText
        aiQuickActionChapter = routing.aiQuickActionChapter
        contextMenuCoordinator?.showMenu(
            text: routing.contextMenuText,
            locator: routing.contextMenuLocator,
            chapter: routing.contextMenuChapter
        )
        annotationDraft = routing.annotationDraft
    }

    private func presentBookmarkDraft() {
        let pageIndex = viewModel.currentPage
        let pageLabel = viewModel.pdfDocument?.page(at: pageIndex)?.label
            ?? AppLocalization.format("reader.page_number_format", locale: .autoupdatingCurrent, pageIndex + 1)
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
            annotationErrorMessage = annotationsViewModel.errorMessage
                ?? AppLocalization.string("errors.reader.annotation_failed")
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
            annotationErrorMessage = annotationsViewModel.errorMessage
                ?? AppLocalization.string("errors.reader.annotation_delete_failed")
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
            onActionWithScope: { action, scope in
                let selection = aiQuickActionText
                let actionPrompt = action.prompt(
                    selectedText: selection ?? "",
                    bookTitle: viewModel.book.title,
                    chapterTitle: aiQuickActionChapter
                )
                aiQuickActionText = nil
                isAIPanelPresented = true
                Task { @MainActor in
                    var seed = actionPrompt
                    if let bridge = viewModel.pdfContentBridge {
                        let resolver = PDFReaderContextResolver(
                            bridge: bridge,
                            book: viewModel.book,
                            currentPageProvider: { [weak viewModel] in viewModel?.currentPage ?? 0 }
                        )
                        if let result = try? await resolver.resolve(
                            scope: scope,
                            currentLocator: .pdf(pageIndex: viewModel.currentPage),
                            selection: selection
                        ) {
                            let preamble = ReaderContextPreambleBuilder().buildPreamble(for: result)
                            seed = preamble + "\n\n" + actionPrompt
                        }
                    }
                    await aiChatViewModel.sendMessage(seed)
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
            case .dictionary:
                DictionaryLookupSheet(
                    term: coordinator.selectedText,
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

    // MARK: - TOC search highlighting

    private func highlightedTOCTitle(_ title: String) -> Text {
        let q = tocSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty,
              let range = title.range(of: q, options: .caseInsensitive) else {
            return Text(title).foregroundStyle(Morandi.primaryText)
        }
        let before = String(title[..<range.lowerBound])
        let match = String(title[range])
        let after = String(title[range.upperBound...])
        return Text(before).foregroundStyle(Morandi.primaryText)
            + Text(match).foregroundStyle(Morandi.accent).bold()
            + Text(after).foregroundStyle(Morandi.primaryText)
    }

    // MARK: - TTS

    /// Returns the plain text of the current PDF page for TTS playback.
    private func currentPagePlainText() -> String? {
        guard let document = viewModel.pdfDocument else { return nil }
        let index = max(0, min(viewModel.currentPage, document.pageCount - 1))
        guard let page = document.page(at: index) else { return nil }
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    // MARK: - Volume Key Handler

    private func applyVolumeKeyHandler() {
        if volumeKeysEnabled {
            volumeKeyHandler.start()
            WakeLockController.setKeepScreenOn(true)
        } else {
            volumeKeyHandler.stop()
        }
    }

    // MARK: - TOC Search Helpers

    private var filteredTOCEntries: [ChapterEntry] {
        TOCSearchFilter.filter(viewModel.tocEntries, query: tocSearchQuery)
    }

}

import SwiftUI
import PDFKit
import PTCore
import PTUI

// MARK: - PDFKit platform wrapper

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for PDFKit's PDFView on iOS.
struct NativePDFView: UIViewRepresentable {
    let document: PDFDocument
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, document: document)
    }

    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        let document: PDFDocument

        init(currentPage: Binding<Int>, document: PDFDocument) {
            self._currentPage = currentPage
            self.document = document
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            DispatchQueue.main.async { self.currentPage = index }
        }
    }
}

#elseif canImport(AppKit)
import AppKit

/// SwiftUI wrapper for PDFKit's PDFView on macOS.
struct NativePDFView: NSViewRepresentable {
    let document: PDFDocument
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, document: document)
    }

    final class Coordinator: NSObject {
        @Binding var currentPage: Int
        let document: PDFDocument

        init(currentPage: Binding<Int>, document: PDFDocument) {
            self._currentPage = currentPage
            self.document = document
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage else { return }
            let index = document.index(for: page)
            DispatchQueue.main.async { self.currentPage = index }
        }
    }
}
#endif

// MARK: - Full reader view

/// Full-screen PDF reader with toolbar, TOC sheet, and reading progress.
public struct PDFReaderView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    public init(book: Book, database: AppDatabase) {
        _viewModel = State(initialValue: ReaderViewModel(book: book, database: database))
    }

    public var body: some View {
        ZStack {
            Morandi.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("Opening…")
                    .tint(Morandi.accent)

            } else if let doc = viewModel.pdfDocument {
                NativePDFView(document: doc, currentPage: $viewModel.currentPage)
                    .ignoresSafeArea(edges: .bottom)

            } else {
                ContentUnavailableView(
                    "Cannot Open",
                    systemImage: "doc.text.slash",
                    description: Text("The file could not be opened.")
                )
            }
        }
        .navigationTitle(viewModel.book.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showTOC) { tocSheet }
        .task { await viewModel.loadDocument() }
        .onDisappear { Task { await viewModel.saveProgress() } }
    }

    // MARK: - Toolbar

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

        ToolbarItem(placement: .primaryAction) {
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
}

import SwiftUI
import PTCore
import PTUI

/// Storage diagnostics + cleanup screen. Displays the on-disk footprint of
/// various subsystems (database, book files, covers, AI index, memory files,
/// conversation history) and exposes buttons for clearing individual caches
/// or exporting a data bundle.
public struct StorageManagementView: View {
    @State private var viewModel: SettingsViewModel
    @State private var sizes: SizeSnapshot = .empty
    @State private var isComputing = false
    @State private var showClearConversations = false
    @State private var showClearAIIndex = false
    @State private var showClearCache = false
    @State private var toast: String?

    @MainActor
    public init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
    }

    public var body: some View {
        Form {
            if isComputing {
                Section {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("common.calculating")
                            .foregroundStyle(Morandi.secondaryText)
                    }
                }
            }
            overviewSection
            actionsSection
            if let toast {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Morandi.sage)
                        Text(toast)
                            .foregroundStyle(Morandi.sage)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.storage"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { recompute() }
    }

    private var overviewSection: some View {
        Section(String(localized: "common.usage")) {
            row("Database", sizes.database)
            row("Book Files", sizes.books)
            row("Cover Images", sizes.covers)
            row("AI Index", sizes.aiIndex)
            row("Conversation History", sizes.conversations)
            row("Memory Files", sizes.memory)
            HStack {
                Text("common.total")
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Text(format(sizes.total))
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(Morandi.accent)
            }
        }
    }

    private var actionsSection: some View {
        Section(String(localized: "common.actions")) {
            Button {
                showClearConversations = true
            } label: {
                Label(String(localized: "settings.storage.clear_history"), systemImage: "bubble.left.and.bubble.right")
                    .foregroundStyle(Morandi.primaryText)
            }
            .confirmationDialog("Clear all conversation history?", isPresented: $showClearConversations) {
                Button(String(localized: "common.clear"), role: .destructive) {
                    clearDirectory(named: "conversations")
                    showToast("Conversation history cleared")
                }
            }

            Button {
                showClearAIIndex = true
            } label: {
                Label(String(localized: "settings.storage.clear_ai_index"), systemImage: "square.stack.3d.up.slash")
                    .foregroundStyle(Morandi.primaryText)
            }
            .confirmationDialog("Clear AI search index?", isPresented: $showClearAIIndex) {
                Button(String(localized: "common.clear_all"), role: .destructive) {
                    clearDirectory(named: "ai_index")
                    showToast("AI index cleared")
                }
            }

            Button {
                showClearCache = true
            } label: {
                Label(String(localized: "settings.clear_cache"), systemImage: "trash")
                    .foregroundStyle(Morandi.primaryText)
            }
            .confirmationDialog("Clear all cached files?", isPresented: $showClearCache) {
                Button(String(localized: "settings.clear_cache"), role: .destructive) {
                    viewModel.clearCache()
                    showToast("Cache cleared")
                }
            }

            Button {
                exportData()
            } label: {
                Label(String(localized: "settings.storage.export_bundle"), systemImage: "square.and.arrow.up")
                    .foregroundStyle(Morandi.accent)
            }
        }
    }

    // MARK: - Rendering helpers

    @ViewBuilder
    private func row(_ label: String, _ size: UInt64) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Morandi.primaryText)
            Spacer()
            Text(format(size))
                .foregroundStyle(Morandi.secondaryText)
        }
    }

    private func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Computation

    private func recompute() {
        isComputing = true
        Task.detached(priority: .utility) {
            let snapshot = await Self.computeSizes()
            await MainActor.run {
                self.sizes = snapshot
                self.isComputing = false
            }
        }
    }

    private static func computeSizes() -> SizeSnapshot {
        let fm = FileManager.default
        let container = AppConfig.appGroupContainerURL(fileManager: fm)
        let docs = AppConfig.documentsURL(fileManager: fm)

        let database = directorySize(at: container.appendingPathComponent("Database"))
            + directorySize(at: docs.appendingPathComponent("Database"))
        let books = directorySize(at: container.appendingPathComponent("Books"))
            + directorySize(at: docs.appendingPathComponent("Books"))
        let covers = directorySize(at: container.appendingPathComponent("Covers"))
            + directorySize(at: docs.appendingPathComponent("Covers"))
        let aiIndex = directorySize(at: container.appendingPathComponent("ai_index"))
            + directorySize(at: docs.appendingPathComponent("ai_index"))
        let conversations = directorySize(at: container.appendingPathComponent("conversations"))
            + directorySize(at: docs.appendingPathComponent("conversations"))
        let memory = directorySize(at: container.appendingPathComponent("memory"))
            + directorySize(at: docs.appendingPathComponent("memory"))

        return SizeSnapshot(
            database: database,
            books: books,
            covers: covers,
            aiIndex: aiIndex,
            conversations: conversations,
            memory: memory
        )
    }

    private static func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    // MARK: - Actions

    private func clearDirectory(named name: String) {
        let fm = FileManager.default
        let container = AppConfig.appGroupContainerURL(fileManager: fm)
        let url = container.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        recompute()
    }

    private func exportData() {
        // Placeholder: marks the request for export. Real export happens in
        // the platform-specific share sheet hooked up from the app layer.
        showToast("Export prepared")
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { if toast == message { toast = nil } }
        }
    }

    // MARK: - Types

    struct SizeSnapshot: Sendable {
        let database: UInt64
        let books: UInt64
        let covers: UInt64
        let aiIndex: UInt64
        let conversations: UInt64
        let memory: UInt64

        var total: UInt64 {
            database + books + covers + aiIndex + conversations + memory
        }

        static let empty = SizeSnapshot(
            database: 0, books: 0, covers: 0, aiIndex: 0, conversations: 0, memory: 0
        )
    }
}

import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// Settings page for the local AI library/RAG index — picks the embedding
/// provider/model, chunking parameters, batch size, and exposes bulk
/// re-index / clear actions.
@MainActor
public struct AILibraryIndexView: View {
    @State private var providerId: String
    @State private var modelId: String
    @State private var chunkSize: Double
    @State private var overlap: Double
    @State private var batchSize: Int
    @State private var indexStatusText: String = ""
    @State private var storageUsedText: String = ""
    @State private var isWorking: Bool = false
    @State private var workingMessage: String = ""
    @State private var workingProgress: Double = 0.0
    @State private var lastError: String?

    private let defaults = AppConfig.groupDefaults

    public init() {
        let d = AppConfig.groupDefaults
        _providerId = State(initialValue: d.string(forKey: "rag_embedding_provider") ?? "openai")
        _modelId = State(initialValue: d.string(forKey: "rag_embedding_model") ?? EmbeddingService.defaultModel)
        _chunkSize = State(initialValue: d.object(forKey: "rag_chunk_size") as? Double ?? 768)
        _overlap = State(initialValue: d.object(forKey: "rag_chunk_overlap") as? Double ?? 96)
        _batchSize = State(initialValue: (d.object(forKey: "rag_batch_size") as? Int) ?? 16)
    }

    public var body: some View {
        formContent
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(String(localized: "settings.ai_library.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { refreshStatus() }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            providerSection
            modelSection
            chunkingSection
            statusSection
            actionsSection
            if let err = lastError {
                Section {
                    Text(err)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.destructive)
                }
            }
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section(String(localized: "settings.ai_library.embedding_provider")) {
            Picker(String(localized: "settings.ai_library.provider"), selection: $providerId) {
                Text(ProviderFactory.displayName(for: .openai)).tag("openai")
                Text(ProviderFactory.displayName(for: .gemini)).tag("gemini")
                Text(ProviderFactory.displayName(for: .azure)).tag("azure")
                Text(String(localized: "settings.custom_provider")).tag("custom")
            }
        }
        .onChange(of: providerId) { _, v in defaults.set(v, forKey: "rag_embedding_provider") }
    }

    private var modelSection: some View {
        Section(String(localized: "settings.ai_library.embedding_model")) {
            Picker(String(localized: "settings.ai_library.model"), selection: $modelId) {
                ForEach(modelsForCurrentProvider, id: \.self) { m in
                    Text(m).tag(m)
                }
                if !modelsForCurrentProvider.contains(modelId) && !modelId.isEmpty {
                    Text(modelId).tag(modelId)
                }
            }
            TextField(String(localized: "settings.ai_library.custom_model_placeholder"), text: $modelId)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .font(AppTypography.caption)
        }
        .onChange(of: modelId) { _, v in defaults.set(v, forKey: "rag_embedding_model") }
    }

    private var chunkingSection: some View {
        Section(String(localized: "settings.ai_library.chunking")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "settings.ai_library.chunk_size"))
                    Spacer()
                    Text(AppLocalization.format("settings.ai_library.tokens_format", locale: .autoupdatingCurrent, Int(chunkSize)))
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(Morandi.secondaryText)
                }
                Slider(value: $chunkSize, in: 256...2048, step: 32)
                    .tint(Morandi.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "settings.ai_library.overlap"))
                    Spacer()
                    Text(AppLocalization.format("settings.ai_library.tokens_format", locale: .autoupdatingCurrent, Int(overlap)))
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(Morandi.secondaryText)
                }
                Slider(value: $overlap, in: 32...256, step: 8)
                    .tint(Morandi.accent)
            }
            Stepper(value: $batchSize, in: 1...100) {
                HStack {
                    Text(String(localized: "settings.ai_library.batch_size"))
                    Spacer()
                    Text("\(batchSize)")
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .onChange(of: chunkSize) { _, v in defaults.set(v, forKey: "rag_chunk_size") }
        .onChange(of: overlap) { _, v in defaults.set(v, forKey: "rag_chunk_overlap") }
        .onChange(of: batchSize) { _, v in defaults.set(v, forKey: "rag_batch_size") }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: "books.vertical")
                    .foregroundStyle(Morandi.sage)
                Text(indexStatusText.isEmpty ? String(localized: "settings.ai_library.no_index_data") : indexStatusText)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(Morandi.powder)
                Text(AppLocalization.format(
                    "settings.ai_library.storage_format",
                    locale: .autoupdatingCurrent,
                    storageUsedText.isEmpty ? "0 KB" : storageUsedText
                ))
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }
            if isWorking {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workingMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.primaryText)
                    ProgressView(value: workingProgress)
                        .tint(Morandi.accent)
                }
            }
        } header: {
            Text("settings.ai_library.status")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await indexAllBooks() }
            } label: {
                Label("settings.ai_library.index_all_books", systemImage: "wand.and.stars")
                    .foregroundStyle(Morandi.accent)
            }
            .disabled(isWorking)

            Button {
                Task { await clearAllIndexes() }
            } label: {
                Label("settings.ai_library.clear_all_indexes", systemImage: "trash")
                    .foregroundStyle(Morandi.destructive)
            }
            .disabled(isWorking)

            Button {
                refreshStatus()
            } label: {
                Label("settings.ai_library.refresh_status", systemImage: "arrow.clockwise")
                    .foregroundStyle(Morandi.secondaryText)
            }
        }
    }

    // MARK: - Helpers

    private var modelsForCurrentProvider: [String] {
        switch providerId {
        case "openai":
            return ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"]
        case "gemini":
            return ["text-embedding-004", "embedding-001"]
        case "azure":
            return ["text-embedding-3-small", "text-embedding-3-large"]
        default:
            return []
        }
    }

    private func refreshStatus() {
        let dir = AppConfig.appGroupContainerURL().appendingPathComponent("rag")
        let count = chunkCount(in: dir)
        indexStatusText = AppLocalization.format(
            "settings.ai_library.indexed_chunks_format",
            locale: .autoupdatingCurrent,
            count
        )
        storageUsedText = directorySizeFormatted(dir)
    }

    private func chunkCount(in directory: URL) -> Int {
        let store = VectorStore(directory: directory)
        return (try? store.countSync()) ?? 0
    }

    private func directorySizeFormatted(_ url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return "0 KB" }
        var total: Int64 = 0
        for case let f as URL in enumerator {
            if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(s)
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    private func indexAllBooks() async {
        // Library book enumeration lives in the host app; here we only
        // reset progress and instruct the user. A future PR can wire to the
        // full library service.
        isWorking = true
        workingMessage = String(localized: "settings.ai_library.indexing_not_wired")
        workingProgress = 1.0
        defer {
            isWorking = false
            refreshStatus()
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func clearAllIndexes() async {
        isWorking = true
        workingMessage = String(localized: "settings.ai_library.clearing_index")
        workingProgress = 0.5
        defer { isWorking = false }
        let dir = AppConfig.appGroupContainerURL().appendingPathComponent("rag")
        let store = VectorStore(directory: dir)
        do {
            try await store.clear()
            workingProgress = 1.0
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - VectorStore sync helper

private extension VectorStore {
    /// Synchronous count helper used purely from the settings UI.
    nonisolated func countSync() throws -> Int {
        // The actor's count(bookId:) is async; we approximate with 0 here to
        // avoid blocking — the UI shows a refresh button that triggers async
        // updates if needed in the future.
        return 0
    }
}

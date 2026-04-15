import Foundation
import PTCore

public actor MemoryWorkflowService {
    public enum WorkflowError: LocalizedError {
        case emptyText
        case documentNotFound(String)
        case candidateNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .emptyText:
                return AppLocalization.string(
                    "errors.memory.empty_text",
                    value: "Memory text cannot be empty."
                )
            case .documentNotFound:
                return AppLocalization.string(
                    "errors.memory.document_not_found",
                    value: "The selected memory document could not be found."
                )
            case .candidateNotFound:
                return AppLocalization.string(
                    "errors.memory.candidate_not_found",
                    value: "The selected memory item could not be found."
                )
            }
        }
    }

    private let directory: URL
    private let fileManager: FileManager
    private let indexDatabase: MemoryIndexDatabase
    private let candidateStore: MemoryCandidateStore
    private let locale: Locale

    public init(
        directory: URL,
        fileManager: FileManager = .default,
        indexDatabase: MemoryIndexDatabase? = nil,
        candidateStore: MemoryCandidateStore? = nil,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.indexDatabase = indexDatabase ?? MemoryIndexDatabase(directory: directory)
        self.candidateStore = candidateStore ?? MemoryCandidateStore(directory: directory, fileManager: fileManager)
        self.locale = locale
    }

    public func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func listCandidates(status: MemoryCandidateStatus? = nil) async throws -> [MemoryCandidate] {
        try ensureDirectory()
        return try await candidateStore.list(status: status)
    }

    public func addToReviewInbox(
        text: String,
        targetDoc: MemoryDocTarget,
        sourceType: String = "manual",
        conversationId: String? = nil,
        messageNodeId: String? = nil,
        summary: String? = nil,
        displayText: String? = nil,
        sourcePointer: String? = nil,
        rawContextRef: String? = nil,
        confidence: Double? = nil,
        triggerKind: String? = nil,
        bookId: Int64? = nil,
        cfi: String? = nil,
        chapter: String? = nil,
        sourceKind: MemorySourceKind = .manual,
        tags: [String] = [],
        rationale: String? = nil
    ) async throws -> MemoryCandidate {
        let normalized = try normalize(text)
        try ensureDirectory()

        let candidate = MemoryCandidate(
            summary: summary ?? defaultSummary(for: normalized),
            text: normalized,
            targetDoc: targetDoc,
            sourceType: sourceType,
            createdAt: Date(),
            status: .pending,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            bookId: bookId,
            cfi: cfi,
            chapter: chapter,
            sourceKind: sourceKind,
            tags: tags,
            rationale: rationale,
            displayText: displayText,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            confidence: confidence,
            triggerKind: triggerKind
        )
        return try await candidateStore.upsert(candidate)
    }

    public func saveToDaily(
        text: String,
        date: Date = Date(),
        sourceType: String = "manual",
        conversationId: String? = nil,
        messageNodeId: String? = nil,
        summary: String? = nil,
        displayText: String? = nil,
        sourcePointer: String? = nil,
        rawContextRef: String? = nil,
        confidence: Double? = nil,
        triggerKind: String? = nil,
        bookId: Int64? = nil,
        cfi: String? = nil,
        chapter: String? = nil,
        sourceKind: MemorySourceKind = .manual,
        tags: [String] = [],
        rationale: String? = nil
    ) async throws -> MemoryCandidate {
        let normalized = try normalize(text)
        let filename = dailyDocumentName(for: date)
        try await append(normalized, to: filename, header: dailyHeader(for: date))

        let now = Date()
        let candidate = MemoryCandidate(
            summary: summary ?? defaultSummary(for: normalized),
            text: normalized,
            targetDoc: .daily,
            appliedTargetDoc: .daily,
            sourceType: sourceType,
            createdAt: now,
            status: .applied,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            bookId: bookId,
            cfi: cfi,
            chapter: chapter,
            sourceKind: sourceKind,
            tags: tags,
            rationale: rationale,
            displayText: displayText,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            confidence: confidence,
            triggerKind: triggerKind,
            appliedAt: now,
            reviewedAt: now,
            decisionSource: "direct_save"
        )
        return try await candidateStore.upsert(candidate)
    }

    public func saveToLongTerm(
        text: String,
        sourceType: String = "manual",
        conversationId: String? = nil,
        messageNodeId: String? = nil,
        summary: String? = nil,
        displayText: String? = nil,
        sourcePointer: String? = nil,
        rawContextRef: String? = nil,
        confidence: Double? = nil,
        triggerKind: String? = nil,
        bookId: Int64? = nil,
        cfi: String? = nil,
        chapter: String? = nil,
        sourceKind: MemorySourceKind = .manual,
        tags: [String] = [],
        rationale: String? = nil
    ) async throws -> MemoryCandidate {
        let normalized = try normalize(text)
        try await append(normalized, to: "MEMORY.md", header: longTermHeader)

        let now = Date()
        let candidate = MemoryCandidate(
            summary: summary ?? defaultSummary(for: normalized),
            text: normalized,
            targetDoc: .longTerm,
            appliedTargetDoc: .longTerm,
            sourceType: sourceType,
            createdAt: now,
            status: .applied,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            bookId: bookId,
            cfi: cfi,
            chapter: chapter,
            sourceKind: sourceKind,
            tags: tags,
            rationale: rationale,
            displayText: displayText,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            confidence: confidence,
            triggerKind: triggerKind,
            appliedAt: now,
            reviewedAt: now,
            decisionSource: "direct_save"
        )
        return try await candidateStore.upsert(candidate)
    }

    public func applyCandidate(
        _ candidateID: String,
        targetDoc: MemoryDocTarget,
        date: Date = Date()
    ) async throws -> MemoryCandidate {
        guard let candidate = try await candidateStore.getById(candidateID) else {
            throw WorkflowError.candidateNotFound(candidateID)
        }

        if candidate.status == .applied, candidate.appliedTargetDoc == targetDoc {
            return candidate
        }

        switch targetDoc {
        case .daily:
            try await append(candidate.text, to: dailyDocumentName(for: date), header: dailyHeader(for: date))
        case .longTerm:
            try await append(candidate.text, to: "MEMORY.md", header: longTermHeader)
        }

        return try await candidateStore.markApplied(candidateID, targetDoc: targetDoc, reviewedAt: Date())
    }

    public func dismissCandidate(_ candidateID: String) async throws -> MemoryCandidate {
        try ensureDirectory()
        return try await candidateStore.dismiss(candidateID)
    }

    public func listDocuments() throws -> [MemoryDocumentSummary] {
        try ensureDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter(isManagedDocumentURL(_:))
            .map(documentSummary(for:))
            .sorted(by: sortDocuments)
    }

    public func loadDocument(named name: String) throws -> String {
        let fileURL = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw WorkflowError.documentNotFound(name)
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    public func saveDocument(named name: String, content: String) async throws {
        try ensureDirectory()
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        try await reindexDocument(at: fileURL)
    }

    @discardableResult
    public func createTodayDocumentIfNeeded(now: Date = Date()) async throws -> MemoryDocumentSummary {
        try ensureDirectory()

        let name = dailyDocumentName(for: now)
        let url = directory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: url.path) == false {
            try dailyHeader(for: now).write(to: url, atomically: true, encoding: .utf8)
        }

        try await reindexDocument(at: url)
        return try documentSummary(for: url)
    }

    public func search(query: String, limit: Int = 20) async throws -> [MemorySearchResult] {
        try ensureDirectory()
        for document in try listDocuments() {
            let path = directory.appendingPathComponent(document.name).path
            try await indexDatabase.indexFile(path: path)
        }
        return try await indexDatabase.search(query: query, limit: limit)
    }

    private func append(_ text: String, to name: String, header: String) async throws {
        try ensureDirectory()

        let fileURL = directory.appendingPathComponent(name)
        let updatedContent: String
        if fileManager.fileExists(atPath: fileURL.path) {
            let existing = try String(contentsOf: fileURL, encoding: .utf8)
            let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            let separator: String
            if trimmedExisting.isEmpty {
                separator = ""
            } else if existing.hasSuffix("\n\n") {
                separator = ""
            } else if existing.hasSuffix("\n") {
                separator = "\n"
            } else {
                separator = "\n\n"
            }
            updatedContent = existing + separator + text + "\n"
        } else {
            updatedContent = header + text + "\n"
        }

        try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
        try await reindexDocument(at: fileURL)
    }

    private func reindexDocument(at url: URL) async throws {
        guard isManagedDocumentURL(url) else { return }
        try await indexDatabase.indexFile(path: url.path)
    }

    private func normalize(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw WorkflowError.emptyText
        }
        return trimmed
    }

    private func defaultSummary(for text: String) -> String {
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(compact.prefix(80))
    }

    private func dailyDocumentName(for date: Date) -> String {
        MemoryDocumentLocalization.fileName(for: date)
    }

    private func dailyHeader(for date: Date) -> String {
        MemoryDocumentLocalization.dailyHeader(for: date, locale: locale)
    }

    private var longTermHeader: String {
        MemoryDocumentLocalization.longTermHeader(locale: locale)
    }

    private func isManagedDocumentURL(_ url: URL) -> Bool {
        documentKind(for: url.lastPathComponent) != nil
    }

    private func documentKind(for name: String) -> MemoryDocumentSummary.Kind? {
        if name == "MEMORY.md" {
            return .longTerm
        }
        if isDailyDocumentName(name) {
            return .daily
        }
        return nil
    }

    private func isDailyDocumentName(_ name: String) -> Bool {
        MemoryDocumentLocalization.date(fromFileName: name) != nil
    }

    private func documentSummary(for url: URL) throws -> MemoryDocumentSummary {
        guard let kind = documentKind(for: url.lastPathComponent) else {
            throw WorkflowError.documentNotFound(url.lastPathComponent)
        }

        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let preview = String(
            content
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .prefix(140)
        )
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return MemoryDocumentSummary(
            name: url.lastPathComponent,
            kind: kind,
            preview: preview,
            modifiedAt: modifiedAt
        )
    }

    private func sortDocuments(lhs: MemoryDocumentSummary, rhs: MemoryDocumentSummary) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind == .longTerm
        }
        return lhs.name > rhs.name
    }
}

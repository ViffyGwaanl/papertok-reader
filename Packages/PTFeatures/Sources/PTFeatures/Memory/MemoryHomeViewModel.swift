import Foundation
import Observation
import PTAIServices
import PTCore

@MainActor
@Observable
public final class MemoryHomeViewModel {
    public enum Section: String, CaseIterable, Identifiable {
        case review
        case documents
        case search
        case capture

        public var id: String { rawValue }
    }

    public let service: MemoryWorkflowService

    public var selectedSection: Section = .review
    public var selectedCandidateStatus: MemoryCandidateStatus = .pending
    public var candidates: [MemoryCandidate] = []
    public var documents: [MemoryDocumentSummary] = []
    public var selectedDocumentName: String?
    public var selectedDocumentContent: String = ""
    public var searchText: String = ""
    public var searchResults: [MemorySearchResult] = []
    public var captureText: String = ""
    public var captureTarget: MemoryDocTarget = .daily
    public var errorMessage: String?
    public var isLoading: Bool = false

    // Bulk selection
    public var isMultiSelectMode: Bool = false
    public var selectedCandidateIds: Set<String> = []

    // Tag editing
    public var allKnownTags: [String] = []
    public var editingTagsCandidateId: String?

    // Session digest
    public var latestDigestSummary: String?
    public var isGeneratingDigest: Bool = false

    public init(service: MemoryWorkflowService) {
        self.service = service
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await reloadCandidates()
        await reloadDocuments(autoloadSelection: true)
        await reloadAllTags()
        await loadLatestDigest()
    }

    public func reloadCandidates() async {
        do {
            candidates = try await service.listCandidates(status: selectedCandidateStatus)
            errorMessage = nil
        } catch {
            errorMessage = loadErrorMessage(for: error)
        }
    }

    public func reloadDocuments(autoloadSelection: Bool = false) async {
        do {
            documents = try await service.listDocuments()
            errorMessage = nil
            if autoloadSelection, selectedDocumentName == nil {
                selectedDocumentName = documents.first?.name
            }
            if let selectedDocumentName,
               documents.contains(where: { $0.name == selectedDocumentName }) {
                selectedDocumentContent = try await service.loadDocument(named: selectedDocumentName)
            } else if let first = documents.first {
                selectedDocumentName = first.name
                selectedDocumentContent = try await service.loadDocument(named: first.name)
            } else {
                selectedDocumentContent = ""
            }
        } catch {
            errorMessage = loadErrorMessage(for: error)
        }
    }

    public func selectDocument(_ name: String) async {
        do {
            selectedDocumentName = name
            selectedDocumentContent = try await service.loadDocument(named: name)
            errorMessage = nil
        } catch {
            errorMessage = loadErrorMessage(for: error)
        }
    }

    public func saveSelectedDocument() async {
        guard let selectedDocumentName else { return }
        do {
            try await service.saveDocument(named: selectedDocumentName, content: selectedDocumentContent)
            errorMessage = nil
            await reloadDocuments()
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func createTodayDocument(now: Date = Date()) async {
        do {
            let summary = try await service.createTodayDocumentIfNeeded(now: now)
            selectedDocumentName = summary.name
            selectedSection = .documents
            errorMessage = nil
            await reloadDocuments()
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func applyCandidate(_ id: String, target: MemoryDocTarget) async {
        do {
            _ = try await service.applyCandidate(id, targetDoc: target)
            errorMessage = nil
            await reloadCandidates()
            await reloadDocuments(autoloadSelection: true)
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func dismissCandidate(_ id: String) async {
        do {
            _ = try await service.dismissCandidate(id)
            errorMessage = nil
            await reloadCandidates()
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            searchResults = []
            return
        }
        do {
            searchResults = try await service.search(query: query, limit: 20)
            errorMessage = nil
        } catch {
            errorMessage = loadErrorMessage(for: error)
        }
    }

    public func saveCapture(addToInbox: Bool, target: MemoryDocTarget) async {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        do {
            if addToInbox {
                _ = try await service.addToReviewInbox(
                    text: text,
                    targetDoc: target,
                    sourceType: "manual",
                    sourceKind: .manual
                )
                selectedSection = .review
                await reloadCandidates()
            } else {
                switch target {
                case .daily:
                    _ = try await service.saveToDaily(
                        text: text,
                        sourceType: "manual",
                        sourceKind: .manual
                    )
                case .longTerm:
                    _ = try await service.saveToLongTerm(
                        text: text,
                        sourceType: "manual",
                        sourceKind: .manual
                    )
                }
                selectedSection = .documents
                await reloadDocuments(autoloadSelection: true)
            }
            captureText = ""
            errorMessage = nil
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    // MARK: - Bulk Operations

    public func toggleSelection(_ id: String) {
        if selectedCandidateIds.contains(id) {
            selectedCandidateIds.remove(id)
        } else {
            selectedCandidateIds.insert(id)
        }
        if selectedCandidateIds.isEmpty {
            isMultiSelectMode = false
        }
    }

    public func enterMultiSelect(startingWith id: String) {
        isMultiSelectMode = true
        selectedCandidateIds = [id]
    }

    public func exitMultiSelect() {
        isMultiSelectMode = false
        selectedCandidateIds = []
    }

    public func bulkApply(ids: Set<String>, target: MemoryDocTarget = .daily) async {
        do {
            try await service.bulkApply(ids: Array(ids), targetDoc: target)
            exitMultiSelect()
            errorMessage = nil
            await reloadCandidates()
            await reloadDocuments(autoloadSelection: true)
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func bulkDismiss(ids: Set<String>) async {
        do {
            try await service.bulkDismiss(ids: Array(ids))
            exitMultiSelect()
            errorMessage = nil
            await reloadCandidates()
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func bulkAddTag(ids: Set<String>, tag: String) async {
        do {
            try await service.bulkAddTag(ids: Array(ids), tag: tag)
            exitMultiSelect()
            errorMessage = nil
            await reloadCandidates()
            await reloadAllTags()
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    // MARK: - Tag Editing

    public func updateTags(candidateId: String, tags: [String]) async {
        do {
            _ = try await service.updateTags(candidateId: candidateId, tags: tags)
            errorMessage = nil
            await reloadCandidates()
            await reloadAllTags()
        } catch {
            errorMessage = actionErrorMessage(for: error)
        }
    }

    public func reloadAllTags() async {
        do {
            allKnownTags = try await service.allTags()
        } catch {
            // non-critical
        }
    }

    // MARK: - Source Jump-Back

    public func navigateToSource(_ candidate: MemoryCandidate) {
        guard let bookId = candidate.bookId else { return }
        let locator = candidate.cfi
        NotificationCenter.default.post(
            name: .memorySourceJumpBack,
            object: nil,
            userInfo: [
                "bookID": String(bookId),
                "locator": locator as Any,
            ]
        )
    }

    // MARK: - Session Digest

    public func loadLatestDigest() async {
        do {
            let documents = try await service.listDocuments()
            guard let latestDaily = documents.first(where: { $0.kind == .daily }) else {
                latestDigestSummary = nil
                return
            }
            let content = try await service.loadDocument(named: latestDaily.name)
            // Look for session digest section marker
            if let range = content.range(of: "## Session Digest") ??
               content.range(of: "## ") {
                let afterHeader = content[range.upperBound...]
                let nextSection = afterHeader.range(of: "\n## ")
                let digestText: String
                if let nextSection {
                    digestText = String(afterHeader[..<nextSection.lowerBound])
                } else {
                    digestText = String(afterHeader)
                }
                let trimmed = digestText.trimmingCharacters(in: .whitespacesAndNewlines)
                latestDigestSummary = trimmed.isEmpty ? nil : trimmed
            } else {
                latestDigestSummary = nil
            }
        } catch {
            latestDigestSummary = nil
        }
    }

    private func loadErrorMessage(for error: Error) -> String {
        AppLocalization.userFacingErrorMessage(
            for: error,
            fallbackKey: "common.failed_to_load"
        )
    }

    private func actionErrorMessage(for error: Error) -> String {
        AppLocalization.userFacingErrorMessage(
            for: error,
            fallbackKey: "common.error"
        )
    }
}

public extension Notification.Name {
    static let memorySourceJumpBack = Notification.Name("PaperTokMemorySourceJumpBack")
}

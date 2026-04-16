import Foundation
import Testing
import PTAIServices
import PTCore
@testable import PTFeatures

@Suite("MemoryHomeViewModel")
@MainActor
struct MemoryHomeViewModelTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-home-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("load populates review inbox and selects a document")
    func loadPopulatesState() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(
            directory: dir,
            locale: Locale(identifier: "zh-Hans")
        )
        _ = try await service.addToReviewInbox(
            text: "Remember the user's annotation preference.",
            targetDoc: .daily,
            sourceType: "manual"
        )
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2024
        components.month = 4
        components.day = 14
        components.hour = 12
        let fixedDate = try #require(components.date)
        _ = try await service.createTodayDocumentIfNeeded(now: fixedDate)

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()

        #expect(viewModel.candidates.count == 1)
        #expect(viewModel.selectedDocumentName == "2024-04-14.md")
        #expect(viewModel.selectedDocumentContent.contains("每日记忆"))
    }

    @Test("applyCandidate refreshes the inbox and documents")
    func applyCandidateRefreshes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let candidate = try await service.addToReviewInbox(
            text: "Persist this as a long-term memory.",
            targetDoc: .longTerm,
            sourceType: "manual"
        )

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()
        await viewModel.applyCandidate(candidate.id, target: .longTerm)

        #expect(viewModel.candidates.isEmpty)
        #expect(viewModel.documents.contains { $0.name == "MEMORY.md" })
    }

    @Test("saveCapture can send text to the review inbox")
    func saveCaptureToInbox() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let viewModel = MemoryHomeViewModel(service: service)

        viewModel.captureText = "A manual capture for later review."
        await viewModel.saveCapture(addToInbox: true, target: .daily)

        #expect(viewModel.captureText.isEmpty)
        #expect(viewModel.candidates.count == 1)
        #expect(viewModel.candidates.first?.status == .pending)
    }

    @Test("load uses a localized fallback when memory storage is unavailable")
    func loadUsesLocalizedFallbackWhenStorageUnavailable() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("memory-file")
        try "not a directory".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = MemoryWorkflowService(directory: fileURL)
        let viewModel = MemoryHomeViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.errorMessage == AppLocalization.string("common.failed_to_load"))
    }

    // MARK: - Bulk Operations

    @Test("bulkApply applies all selected candidates and exits multi-select")
    func bulkApplyAppliesAll() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let c1 = try await service.addToReviewInbox(text: "Item 1", targetDoc: .daily, sourceType: "manual")
        let c2 = try await service.addToReviewInbox(text: "Item 2", targetDoc: .daily, sourceType: "manual")

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.candidates.count == 2)

        viewModel.enterMultiSelect(startingWith: c1.id)
        viewModel.toggleSelection(c2.id)
        #expect(viewModel.selectedCandidateIds.count == 2)

        await viewModel.bulkApply(ids: viewModel.selectedCandidateIds)

        #expect(viewModel.isMultiSelectMode == false)
        #expect(viewModel.selectedCandidateIds.isEmpty)
        // After applying, pending filter shows empty
        #expect(viewModel.candidates.isEmpty)
    }

    @Test("bulkDismiss dismisses all selected candidates")
    func bulkDismissDismissesAll() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let c1 = try await service.addToReviewInbox(text: "Item A", targetDoc: .daily, sourceType: "manual")
        let c2 = try await service.addToReviewInbox(text: "Item B", targetDoc: .daily, sourceType: "manual")

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()

        viewModel.enterMultiSelect(startingWith: c1.id)
        viewModel.toggleSelection(c2.id)
        await viewModel.bulkDismiss(ids: viewModel.selectedCandidateIds)

        #expect(viewModel.isMultiSelectMode == false)
        #expect(viewModel.candidates.isEmpty) // pending filter
    }

    // MARK: - Tag Update

    @Test("updateTags persists tags on a candidate")
    func updateTagsPersists() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let candidate = try await service.addToReviewInbox(
            text: "Tag test",
            targetDoc: .daily,
            sourceType: "manual"
        )

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()

        await viewModel.updateTags(candidateId: candidate.id, tags: ["swift", "memory"])

        #expect(viewModel.candidates.first?.tags == ["swift", "memory"])
        #expect(viewModel.allKnownTags.contains("swift"))
        #expect(viewModel.allKnownTags.contains("memory"))
    }

    // MARK: - Digest Loading

    @Test("loadLatestDigest returns nil when no documents exist")
    func digestReturnsNilWhenEmpty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.loadLatestDigest()

        #expect(viewModel.latestDigestSummary == nil)
    }

    @Test("bulkAddTag adds tag to all selected candidates")
    func bulkAddTagAddsToAll() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let c1 = try await service.addToReviewInbox(text: "Tag bulk 1", targetDoc: .daily, sourceType: "manual")
        let c2 = try await service.addToReviewInbox(text: "Tag bulk 2", targetDoc: .daily, sourceType: "manual")

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()

        viewModel.enterMultiSelect(startingWith: c1.id)
        viewModel.toggleSelection(c2.id)
        await viewModel.bulkAddTag(ids: viewModel.selectedCandidateIds, tag: "important")

        // Reload and check tags
        await viewModel.reloadCandidates()
        for candidate in viewModel.candidates {
            #expect(candidate.tags.contains("important"))
        }
    }

    // MARK: - Multi-Select Mode

    @Test("enterMultiSelect and exitMultiSelect toggle mode")
    func multiSelectModeToggles() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let c1 = try await service.addToReviewInbox(text: "Mode test", targetDoc: .daily, sourceType: "manual")

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()

        #expect(viewModel.isMultiSelectMode == false)
        viewModel.enterMultiSelect(startingWith: c1.id)
        #expect(viewModel.isMultiSelectMode == true)
        #expect(viewModel.selectedCandidateIds.count == 1)

        viewModel.exitMultiSelect()
        #expect(viewModel.isMultiSelectMode == false)
        #expect(viewModel.selectedCandidateIds.isEmpty)
    }

    @Test("toggleSelection removes last item exits multi-select")
    func toggleSelectionExitsWhenEmpty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = MemoryWorkflowService(directory: dir)
        let c1 = try await service.addToReviewInbox(text: "Toggle test", targetDoc: .daily, sourceType: "manual")

        let viewModel = MemoryHomeViewModel(service: service)
        await viewModel.load()

        viewModel.enterMultiSelect(startingWith: c1.id)
        viewModel.toggleSelection(c1.id)
        #expect(viewModel.isMultiSelectMode == false)
        #expect(viewModel.selectedCandidateIds.isEmpty)
    }
}

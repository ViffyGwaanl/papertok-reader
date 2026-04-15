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
}

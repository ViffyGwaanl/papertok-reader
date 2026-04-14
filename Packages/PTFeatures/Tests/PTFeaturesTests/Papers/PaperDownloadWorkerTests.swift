import Foundation
import Testing
import PTCore
@testable import PTFeatures
@testable import PTNetworking

@Suite("PaperDownloadWorker")
struct PaperDownloadWorkerTests {
    @Test("emits byte progress, importing state, and imported result")
    func emitsProgressAndImportedResult() async throws {
        let plan = try #require(PaperDownloadPlan(detail: makeDetail()))
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let downloadedFile = tempRoot.appendingPathComponent(plan.suggestedFilename)
        try Data("paper".utf8).write(to: downloadedFile)

        let worker = PaperDownloadWorker(
            downloader: RecordingPaperFileDownloader(
                fileURL: downloadedFile,
                progressEvents: [
                    .init(receivedBytes: 64, totalBytes: 256),
                    .init(receivedBytes: 256, totalBytes: 256),
                ]
            ),
            importer: RecordingPaperLibraryImporter(
                result: .success(.placeholder(title: "Imported Paper", filePath: downloadedFile.path))
            )
        )
        let sink = DownloadStatusSink()

        try await worker.run(plan: plan) { status in
            await sink.append(status)
        }

        let statuses = await sink.snapshot()
        #expect(statuses.count == 4)

        if case let .downloading(firstPlan, phase, progress) = statuses[0] {
            #expect(firstPlan == plan)
            #expect(phase == .downloading)
            #expect(progress == .init(receivedBytes: 64, totalBytes: 256))
        } else {
            Issue.record("Expected the first status to report download progress")
        }

        if case let .downloading(secondPlan, phase, progress) = statuses[1] {
            #expect(secondPlan == plan)
            #expect(phase == .downloading)
            #expect(progress == .init(receivedBytes: 256, totalBytes: 256))
        } else {
            Issue.record("Expected the second status to report completed bytes")
        }

        if case let .downloading(importPlan, phase, progress) = statuses[2] {
            #expect(importPlan == plan)
            #expect(phase == .importing)
            #expect(progress == nil)
        } else {
            Issue.record("Expected an importing status before the final result")
        }

        #expect(statuses[3] == .imported("Imported Paper"))
    }

    @Test("maps duplicate import failures to already in bookshelf")
    func mapsDuplicateImportResult() async throws {
        let plan = try #require(PaperDownloadPlan(detail: makeDetail()))
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let downloadedFile = tempRoot.appendingPathComponent(plan.suggestedFilename)
        try Data("paper".utf8).write(to: downloadedFile)

        let existingBook = Book.placeholder(title: "Existing Paper", filePath: downloadedFile.path)
        let worker = PaperDownloadWorker(
            downloader: RecordingPaperFileDownloader(fileURL: downloadedFile, progressEvents: []),
            importer: RecordingPaperLibraryImporter(result: .failure(.alreadyExists(existingBook)))
        )
        let sink = DownloadStatusSink()

        try await worker.run(plan: plan) { status in
            await sink.append(status)
        }

        let statuses = await sink.snapshot()
        #expect(statuses.last == .alreadyInBookshelf("Existing Paper"))
    }

    @Test("maps generic download failures to a localized import fallback")
    func mapsGenericDownloadFailure() async throws {
        let plan = try #require(PaperDownloadPlan(detail: makeDetail()))
        let worker = PaperDownloadWorker(
            downloader: FailingPaperFileDownloader(error: PlainDownloadFailure.failed),
            importer: RecordingPaperLibraryImporter(
                result: .success(.placeholder(title: "Imported Paper", filePath: "/tmp/paper.pdf"))
            )
        )
        let sink = DownloadStatusSink()

        try await worker.run(plan: plan) { status in
            await sink.append(status)
        }

        let statuses = await sink.snapshot()
        let failedStatus = try #require(statuses.last)
        if case let .failed(message, returnedPlan) = failedStatus {
            #expect(message == AppLocalization.string("errors.import.failed"))
            #expect(returnedPlan == plan)
        } else {
            Issue.record("Expected the worker to emit a localized failure state")
        }
    }

    @Test("maps generic import failures to a localized import fallback")
    func mapsGenericImportFailure() async throws {
        let plan = try #require(PaperDownloadPlan(detail: makeDetail()))
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let downloadedFile = tempRoot.appendingPathComponent(plan.suggestedFilename)
        try Data("paper".utf8).write(to: downloadedFile)

        let worker = PaperDownloadWorker(
            downloader: RecordingPaperFileDownloader(fileURL: downloadedFile, progressEvents: []),
            importer: FailingPaperLibraryImporter(error: PlainImportFailure.failed)
        )
        let sink = DownloadStatusSink()

        try await worker.run(plan: plan) { status in
            await sink.append(status)
        }

        let statuses = await sink.snapshot()
        let failedStatus = try #require(statuses.last)
        if case let .failed(message, returnedPlan) = failedStatus {
            #expect(message == AppLocalization.string("errors.import.failed"))
            #expect(returnedPlan == plan)
        } else {
            Issue.record("Expected the worker to emit a localized import failure state")
        }
    }

    private func makeDetail() throws -> PaperTokDetail {
        let json = """
        {
          "id": 7,
          "title": "Transformers",
          "pdfUrl": "https://papertok.ai/pdf/paper.pdf",
          "images": [],
          "generatedImages": []
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PaperTokDetail.self, from: json)
    }
}

private actor DownloadStatusSink {
    private var statuses: [PaperDownloadStatus] = []

    func append(_ status: PaperDownloadStatus) {
        statuses.append(status)
    }

    func snapshot() -> [PaperDownloadStatus] {
        statuses
    }
}

private actor RecordingPaperFileDownloader: PaperFileDownloading {
    let fileURL: URL
    let progressEvents: [PaperTransferProgress]

    init(fileURL: URL, progressEvents: [PaperTransferProgress]) {
        self.fileURL = fileURL
        self.progressEvents = progressEvents
    }

    func download(
        from url: URL,
        suggestedFilename: String,
        onProgress: @escaping @Sendable (PaperTransferProgress) async -> Void
    ) async throws -> URL {
        for event in progressEvents {
            await onProgress(event)
        }
        return fileURL
    }
}

private actor RecordingPaperLibraryImporter: PaperLibraryImporting {
    let result: Result<Book, BookImportError>

    init(result: Result<Book, BookImportError>) {
        self.result = result
    }

    func importFile(from url: URL) async throws -> Book {
        try result.get()
    }
}

private enum PlainDownloadFailure: Error {
    case failed
}

private enum PlainImportFailure: Error {
    case failed
}

private actor FailingPaperFileDownloader: PaperFileDownloading {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func download(
        from url: URL,
        suggestedFilename: String,
        onProgress: @escaping @Sendable (PaperTransferProgress) async -> Void
    ) async throws -> URL {
        throw error
    }
}

private actor FailingPaperLibraryImporter: PaperLibraryImporting {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func importFile(from url: URL) async throws -> Book {
        throw error
    }
}

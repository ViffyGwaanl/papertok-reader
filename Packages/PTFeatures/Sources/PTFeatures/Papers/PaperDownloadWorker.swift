import Foundation
import PTCore

enum PaperDownloadPhase: Equatable, Sendable {
    case downloading
    case importing

    var title: String {
        switch self {
        case .downloading: AppLocalization.string("papers.download.phase.downloading")
        case .importing: AppLocalization.string("papers.download.phase.importing")
        }
    }
}

struct PaperTransferProgress: Equatable, Sendable {
    let receivedBytes: Int64
    let totalBytes: Int64?

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        let fraction = Double(receivedBytes) / Double(totalBytes)
        return min(max(fraction, 0), 1)
    }

    var statusText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file

        let receivedText = formatter.string(fromByteCount: receivedBytes)
        guard let totalBytes, totalBytes > 0 else {
            return receivedText
        }

        let totalText = formatter.string(fromByteCount: totalBytes)
        let percent = Int((fractionCompleted ?? 0) * 100)
        return "\(percent)% • \(receivedText) / \(totalText)"
    }
}

protocol PaperFileDownloading: Sendable {
    func download(
        from url: URL,
        suggestedFilename: String,
        onProgress: @escaping @Sendable (PaperTransferProgress) async -> Void
    ) async throws -> URL
}

protocol PaperLibraryImporting: Sendable {
    func importFile(from url: URL) async throws -> Book
}

extension BookImportService: PaperLibraryImporting {}

struct PaperDownloadWorker {
    let downloader: any PaperFileDownloading
    let importer: any PaperLibraryImporting

    init(
        downloader: any PaperFileDownloading = URLSessionPaperFileDownloader(),
        importer: any PaperLibraryImporting
    ) {
        self.downloader = downloader
        self.importer = importer
    }

    func run(
        plan: PaperDownloadPlan,
        onStatus: @escaping @Sendable (PaperDownloadStatus) async -> Void
    ) async throws {
        let localURL: URL
        do {
            localURL = try await downloader.download(
                from: plan.downloadURL,
                suggestedFilename: plan.suggestedFilename,
                onProgress: { progress in
                    await onStatus(.downloading(plan: plan, phase: .downloading, progress: progress))
                }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await onStatus(.failed(message: userFacingImportFailureMessage(for: error), plan: plan))
            return
        }

        defer {
            try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent())
        }

        await onStatus(.downloading(plan: plan, phase: .importing, progress: nil))

        do {
            let importedBook = try await importer.importFile(from: localURL)
            await onStatus(.imported(importedBook.title))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BookImportError {
            switch error {
            case .alreadyExists(let book):
                await onStatus(.alreadyInBookshelf(book.title))
            default:
                await onStatus(.failed(message: error.errorDescription ?? AppLocalization.string("errors.import.failed"), plan: plan))
            }
        } catch {
            await onStatus(.failed(message: userFacingImportFailureMessage(for: error), plan: plan))
        }
    }

    private func userFacingImportFailureMessage(for error: Error) -> String {
        AppLocalization.localizedErrorDescription(error)
            ?? AppLocalization.string("errors.import.failed")
    }
}

private struct URLSessionPaperFileDownloader: PaperFileDownloading {
    private static let progressChunkSize = 64 * 1024

    func download(
        from url: URL,
        suggestedFilename: String,
        onProgress: @escaping @Sendable (PaperTransferProgress) async -> Void
    ) async throws -> URL {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fileURL = tempDirectory.appendingPathComponent(suggestedFilename)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }

        let expectedBytes = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : nil
        var buffer = Data()
        buffer.reserveCapacity(Self.progressChunkSize)
        var receivedBytes: Int64 = 0
        var lastReportedBytes: Int64 = 0

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            receivedBytes += 1

            if buffer.count >= Self.progressChunkSize {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            if receivedBytes - lastReportedBytes >= Int64(Self.progressChunkSize) {
                lastReportedBytes = receivedBytes
                await onProgress(.init(receivedBytes: receivedBytes, totalBytes: expectedBytes))
            }
        }

        if buffer.isEmpty == false {
            try fileHandle.write(contentsOf: buffer)
        }

        await onProgress(.init(receivedBytes: receivedBytes, totalBytes: expectedBytes))
        return fileURL
    }
}

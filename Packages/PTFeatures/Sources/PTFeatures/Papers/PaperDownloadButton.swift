import Foundation
import SwiftUI
import PTNetworking
import PTUI

enum PaperDownloadFormat: String, Equatable, Sendable {
    case epub
    case pdf
}

struct PaperDownloadPlan: Equatable, Sendable {
    let format: PaperDownloadFormat
    let downloadURL: URL
    let suggestedFilename: String

    init?(detail: PaperTokDetail, api: PaperTokAPI = PaperTokAPI()) {
        if let epubURL = detail.bestEpubUrl.flatMap({ Self.makeURL(from: $0, using: api) }) {
            self.format = .epub
            self.downloadURL = epubURL
            self.suggestedFilename = Self.suggestedFilename(
                title: detail.displayTitle ?? detail.title,
                fallbackID: detail.id,
                format: .epub
            )
            return
        }

        guard let pdfURL = detail.pdfUrl.flatMap({ Self.makeURL(from: $0, using: api) }) else {
            return nil
        }

        self.format = .pdf
        self.downloadURL = pdfURL
        self.suggestedFilename = Self.suggestedFilename(
            title: detail.displayTitle ?? detail.title,
            fallbackID: detail.id,
            format: .pdf
        )
    }

    var buttonTitle: String {
        switch format {
        case .epub: return "Import EPUB"
        case .pdf: return "Import PDF"
        }
    }

    private static func makeURL(from rawValue: String, using api: PaperTokAPI) -> URL? {
        let resolved = api.resolveURL(rawValue)
        guard !resolved.isEmpty else { return nil }
        return URL(string: resolved)
    }

    private static func suggestedFilename(title: String, fallbackID: Int, format: PaperDownloadFormat) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "paper-\(fallbackID)" : trimmed
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let sanitized = base.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                result.append(character)
            }
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filenameBase = sanitized.isEmpty ? "paper-\(fallbackID)" : sanitized
        return "\(filenameBase).\(format.rawValue)"
    }
}

enum PaperDownloadStatus: Equatable, Sendable {
    case idle(plan: PaperDownloadPlan?)
    case downloading(plan: PaperDownloadPlan, phase: PaperDownloadPhase, progress: PaperTransferProgress?)
    case imported(String)
    case alreadyInBookshelf(String)
    case failed(message: String, plan: PaperDownloadPlan?)

    var activePlan: PaperDownloadPlan? {
        switch self {
        case .idle(let plan): return plan
        case .downloading(let plan, _, _): return plan
        case .failed(_, let plan): return plan
        case .imported, .alreadyInBookshelf: return nil
        }
    }
}

/// Download button showing exact persisted state for a paper import.
public struct PaperDownloadButton: View {
    let detail: PaperTokDetail
    let status: PaperDownloadStatus
    let onDownload: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    public var body: some View {
        Group {
            switch status {
            case .imported:
                Label(String(localized: "bookshelf.imported_to_bookshelf"), systemImage: "checkmark.circle.fill")
                    .font(AppTypography.subheadline.weight(.medium))
                    .foregroundStyle(Morandi.sage)

            case .alreadyInBookshelf:
                Label(String(localized: "bookshelf.already_in_bookshelf"), systemImage: "books.vertical.fill")
                    .font(AppTypography.subheadline.weight(.medium))
                    .foregroundStyle(Morandi.sage)

            case .downloading(_, let phase, let progress):
                HStack(spacing: AppSpacing.md) {
                    if let fraction = progress?.fractionCompleted, phase == .downloading {
                        ProgressView(value: fraction)
                            .tint(Morandi.accent)
                            .frame(width: 88)
                    } else {
                        ProgressView()
                            .tint(Morandi.accent)
                            .frame(width: 88)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.title)
                            .font(AppTypography.subheadline.weight(.medium))
                            .foregroundStyle(Morandi.primaryText)
                        Text(progressText(phase: phase, progress: progress))
                            .font(AppTypography.caption.monospacedDigit())
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

            case .failed(let message, let plan):
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label(String(localized: "bookshelf.import_failed"), systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.subheadline.weight(.medium))
                        .foregroundStyle(Morandi.destructive)
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                    if let plan {
                        Button(action: onRetry) {
                            Label(plan.buttonTitle, systemImage: "arrow.clockwise")
                                .font(AppTypography.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Morandi.accent)
                    }
                }

            case .idle(let plan):
                HStack(spacing: AppSpacing.sm) {
                    if let plan {
                        Button(action: onDownload) {
                            Label(plan.buttonTitle, systemImage: "arrow.down.circle")
                                .font(AppTypography.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Morandi.accent)
                    }

                    if let urlString = detail.url, let originalURL = URL(string: urlString) {
                        Link(destination: originalURL) {
                            Label(String(localized: "reader.view_original"), systemImage: "safari")
                                .font(AppTypography.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(Morandi.secondaryText)
                    }

                    if let rawMarkdown = detail.rawMarkdownUrl, let rawURL = URL(string: rawMarkdown) {
                        Link(destination: rawURL) {
                            Label(String(localized: "reader.read_markdown"), systemImage: "doc.text")
                                .font(AppTypography.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(Morandi.secondaryText)
                    }
                }
            }
        }
    }

    private func progressText(phase: PaperDownloadPhase, progress: PaperTransferProgress?) -> String {
        switch phase {
        case .downloading:
            return progress?.statusText ?? "Starting…"
        case .importing:
            return "Saving to Bookshelf…"
        }
    }
}

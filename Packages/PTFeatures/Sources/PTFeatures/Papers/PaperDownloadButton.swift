import Foundation
import SwiftUI
import PTCore
import PTNetworking
import PTUI

enum PaperDownloadFormat: String, Equatable, Sendable {
    case epub
    case pdf
}

/// An EPUB variant surfaced for a single paper, paired with its resolved URL.
/// Used by the detail view to show a picker of available language flavors.
struct PaperEpubVariantOption: Equatable, Sendable {
    let kind: PaperEpubVariant
    let rawURL: String
}

struct PaperDownloadPlan: Equatable, Sendable {
    let format: PaperDownloadFormat
    let downloadURL: URL
    let suggestedFilename: String
    let variant: PaperEpubVariant?

    init?(detail: PaperTokDetail, api: PaperTokAPI = PaperTokAPI()) {
        if let epubURL = detail.bestEpubUrl.flatMap({ Self.makeURL(from: $0, using: api) }) {
            self.format = .epub
            self.downloadURL = epubURL
            self.variant = Self.defaultVariant(for: detail)
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
        self.variant = nil
        self.suggestedFilename = Self.suggestedFilename(
            title: detail.displayTitle ?? detail.title,
            fallbackID: detail.id,
            format: .pdf
        )
    }

    /// Plan for a specific EPUB variant; returns `nil` if that variant is not
    /// exposed by the paper (e.g. variant=.english on a paper with only `.chinese`).
    init?(detail: PaperTokDetail, variant: PaperEpubVariant, api: PaperTokAPI = PaperTokAPI()) {
        guard let rawURL = Self.rawURL(for: variant, in: detail),
              let resolved = Self.makeURL(from: rawURL, using: api) else {
            return nil
        }
        self.format = .epub
        self.downloadURL = resolved
        self.variant = variant
        self.suggestedFilename = Self.suggestedFilename(
            title: detail.displayTitle ?? detail.title,
            fallbackID: detail.id,
            format: .epub
        )
    }

    var buttonTitle: String {
        switch format {
        case .epub:
            return AppLocalization.string("papers.import_epub")
        case .pdf:
            return AppLocalization.string("papers.import_pdf")
        }
    }

    /// Variants present on `detail`, ordered so the language-neutral default
    /// appears first, followed by Chinese, English, then Bilingual. Consumers
    /// (the detail view) decide whether to show a menu (>1 option) or just a
    /// single button.
    static func availableEpubVariants(for detail: PaperTokDetail) -> [PaperEpubVariantOption] {
        let pairs: [(PaperEpubVariant, String?)] = [
            (.default, detail.epubUrl),
            (.chinese, detail.epubUrlZh),
            (.english, detail.epubUrlEn),
            (.bilingual, detail.epubUrlBilingual),
        ]
        return pairs.compactMap { variant, raw in
            guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return PaperEpubVariantOption(kind: variant, rawURL: raw)
        }
    }

    private static func defaultVariant(for detail: PaperTokDetail) -> PaperEpubVariant? {
        availableEpubVariants(for: detail).first?.kind
    }

    private static func rawURL(for variant: PaperEpubVariant, in detail: PaperTokDetail) -> String? {
        switch variant {
        case .default: return detail.epubUrl
        case .chinese: return detail.epubUrlZh
        case .english: return detail.epubUrlEn
        case .bilingual: return detail.epubUrlBilingual
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

/// Renders the live download status for a paper import: in-flight progress,
/// imported/already-on-shelf confirmation, and failure + retry.
///
/// The idle CTA (import button, variant picker, "view original" link) lives in
/// `PaperDetailView.topActionBar`, so this view no longer renders an action
/// button when `status == .idle`. See W5.1 issue 6 / 7.
public struct PaperDownloadButton: View {
    let detail: PaperTokDetail
    let status: PaperDownloadStatus
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

            case .idle:
                EmptyView()
            }
        }
    }

    private func progressText(phase: PaperDownloadPhase, progress: PaperTransferProgress?) -> String {
        switch phase {
        case .downloading:
            return progress?.statusText
                ?? AppLocalization.string("papers.download.starting")
        case .importing:
            return AppLocalization.string("papers.download.saving_to_bookshelf")
        }
    }
}

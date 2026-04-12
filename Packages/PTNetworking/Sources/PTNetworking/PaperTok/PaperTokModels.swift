import Foundation

// MARK: - PaperTokCard

/// A paper card from the PaperTok feed API (`/api/papers/random`).
public struct PaperTokCard: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let displayTitle: String?
    public let extract: String
    public let day: String?
    public let thumbnail: Thumbnail?
    public let thumbnails: [String]
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case id = "pageid"
        case title
        case displayTitle = "displaytitle"
        case extract
        case day
        case thumbnail
        case thumbnails
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        extract = try container.decodeIfPresent(String.self, forKey: .extract) ?? ""
        day = try container.decodeIfPresent(String.self, forKey: .day)
        thumbnail = try container.decodeIfPresent(Thumbnail.self, forKey: .thumbnail)
        thumbnails = try container.decodeIfPresent([String].self, forKey: .thumbnails) ?? []
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    public var bestTitle: String {
        if let dt = displayTitle, !dt.trimmingCharacters(in: .whitespaces).isEmpty {
            return dt
        }
        return title
    }

    public var thumbnailURL: String? {
        thumbnail?.source
    }

    public struct Thumbnail: Codable, Sendable, Equatable {
        public let source: String?
        public let width: Int?
        public let height: Int?
    }
}

// MARK: - PaperTokDetail

/// Full detail of a paper from the PaperTok detail API (`/api/papers/:id`).
public struct PaperTokDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let source: String?
    public let day: String?
    public let title: String
    public let displayTitle: String?
    public let externalId: String?
    public let url: String?
    public let thumbnailUrl: String?
    public let textVariant: String?
    public let captionVariant: String?
    public let oneLiner: String?
    public let oneLinerEn: String?
    public let contentExplainCn: String?
    public let contentExplainEn: String?
    public let contentExplain: String?
    public let contentDialogue: String?
    public let contentDialogueEn: String?
    public let pdfUrl: String?
    public let pdfLocalUrl: String?
    public let rawMarkdownUrl: String?
    public let epubUrl: String?
    public let epubUrlEn: String?
    public let epubUrlZh: String?
    public let epubUrlBilingual: String?
    public let images: [String]
    public let imageCaptions: [String: String]?
    public let imageCaptionsEn: [String: String]?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let generatedImages: [PaperTokGeneratedImage]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        day = try container.decodeIfPresent(String.self, forKey: .day)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        textVariant = try container.decodeIfPresent(String.self, forKey: .textVariant)
        captionVariant = try container.decodeIfPresent(String.self, forKey: .captionVariant)
        oneLiner = try container.decodeIfPresent(String.self, forKey: .oneLiner)
        oneLinerEn = try container.decodeIfPresent(String.self, forKey: .oneLinerEn)
        contentExplainCn = try container.decodeIfPresent(String.self, forKey: .contentExplainCn)
        contentExplainEn = try container.decodeIfPresent(String.self, forKey: .contentExplainEn)
        contentExplain = try container.decodeIfPresent(String.self, forKey: .contentExplain)
        contentDialogue = try container.decodeIfPresent(String.self, forKey: .contentDialogue)
        contentDialogueEn = try container.decodeIfPresent(String.self, forKey: .contentDialogueEn)
        pdfUrl = try container.decodeIfPresent(String.self, forKey: .pdfUrl)
        pdfLocalUrl = try container.decodeIfPresent(String.self, forKey: .pdfLocalUrl)
        rawMarkdownUrl = try container.decodeIfPresent(String.self, forKey: .rawMarkdownUrl)
        epubUrl = try container.decodeIfPresent(String.self, forKey: .epubUrl)
        epubUrlEn = try container.decodeIfPresent(String.self, forKey: .epubUrlEn)
        epubUrlZh = try container.decodeIfPresent(String.self, forKey: .epubUrlZh)
        epubUrlBilingual = try container.decodeIfPresent(String.self, forKey: .epubUrlBilingual)
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
        imageCaptions = try container.decodeIfPresent([String: String].self, forKey: .imageCaptions)
        imageCaptionsEn = try container.decodeIfPresent([String: String].self, forKey: .imageCaptionsEn)
        createdAt = Self.parseDate(
            try container.decodeIfPresent(String.self, forKey: .createdAt)
        )
        updatedAt = Self.parseDate(
            try container.decodeIfPresent(String.self, forKey: .updatedAt)
        )
        generatedImages = try container.decodeIfPresent([PaperTokGeneratedImage].self, forKey: .generatedImages) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, day, title, displayTitle, externalId, url
        case thumbnailUrl, textVariant, captionVariant
        case oneLiner, oneLinerEn
        case contentExplainCn, contentExplainEn, contentExplain
        case contentDialogue, contentDialogueEn
        case pdfUrl, pdfLocalUrl, rawMarkdownUrl
        case epubUrl, epubUrlEn, epubUrlZh, epubUrlBilingual
        case images, imageCaptions, imageCaptionsEn
        case createdAt, updatedAt
        case generatedImages
    }

    public var bestEpubUrl: String? {
        [epubUrl, epubUrlZh, epubUrlEn, epubUrlBilingual]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public func preferredExplanation(language: String) -> String? {
        switch Self.normalizedLanguage(language) {
        case "en":
            return Self.firstNonEmpty([contentExplainEn, contentExplain, contentExplainCn])
        default:
            return Self.firstNonEmpty([contentExplainCn, contentExplain, contentExplainEn])
        }
    }

    public func preferredDialogue(language: String) -> String? {
        switch Self.normalizedLanguage(language) {
        case "en":
            return Self.firstNonEmpty([contentDialogueEn, contentDialogue])
        default:
            return Self.firstNonEmpty([contentDialogue, contentDialogueEn])
        }
    }

    public var carouselImages: [String] {
        let gen = generatedImages.map(\.url).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return gen.isEmpty ? images : gen
    }

    private static func normalizedLanguage(_ language: String) -> String {
        language.lowercased() == "en" ? "en" : "zh"
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        return apiTimestampFormatter.date(from: value)
            ?? fractionalSecondsFormatter.date(from: value)
            ?? iso8601Formatter.date(from: value)
    }

    private static let apiTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - PaperTokGeneratedImage

public struct PaperTokGeneratedImage: Codable, Sendable, Equatable {
    public let url: String
    public let provider: String?
    public let lang: String?
}

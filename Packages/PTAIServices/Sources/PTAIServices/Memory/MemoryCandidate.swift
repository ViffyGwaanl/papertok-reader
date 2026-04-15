import Foundation

public enum MemoryDocTarget: String, Codable, CaseIterable, Sendable {
    case daily
    case longTerm
}

public enum MemoryCandidateStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case applied
    case dismissed
}

public enum MemorySourceKind: String, Codable, CaseIterable, Sendable {
    case chat
    case reading
    case manual
}

public struct MemoryCandidate: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var summary: String
    public var text: String
    public var targetDoc: MemoryDocTarget
    public var appliedTargetDoc: MemoryDocTarget?
    public var sourceType: String
    public var createdAt: Date
    public var status: MemoryCandidateStatus
    public var conversationId: String?
    public var messageNodeId: String?
    public var bookId: Int64?
    public var cfi: String?
    public var chapter: String?
    public var sourceKind: MemorySourceKind
    public var tags: [String]
    public var rationale: String?
    public var displayText: String?
    public var sourcePointer: String?
    public var rawContextRef: String?
    public var confidence: Double?
    public var triggerKind: String?
    public var appliedAt: Date?
    public var reviewedAt: Date?
    public var dismissedAt: Date?
    public var decisionSource: String?

    public init(
        id: String = UUID().uuidString,
        summary: String,
        text: String,
        targetDoc: MemoryDocTarget,
        appliedTargetDoc: MemoryDocTarget? = nil,
        sourceType: String,
        createdAt: Date = Date(),
        status: MemoryCandidateStatus = .pending,
        conversationId: String? = nil,
        messageNodeId: String? = nil,
        bookId: Int64? = nil,
        cfi: String? = nil,
        chapter: String? = nil,
        sourceKind: MemorySourceKind = .manual,
        tags: [String] = [],
        rationale: String? = nil,
        displayText: String? = nil,
        sourcePointer: String? = nil,
        rawContextRef: String? = nil,
        confidence: Double? = nil,
        triggerKind: String? = nil,
        appliedAt: Date? = nil,
        reviewedAt: Date? = nil,
        dismissedAt: Date? = nil,
        decisionSource: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.text = text
        self.targetDoc = targetDoc
        self.appliedTargetDoc = appliedTargetDoc
        self.sourceType = sourceType
        self.createdAt = createdAt
        self.status = status
        self.conversationId = conversationId
        self.messageNodeId = messageNodeId
        self.bookId = bookId
        self.cfi = cfi
        self.chapter = chapter
        self.sourceKind = sourceKind
        self.tags = tags
        self.rationale = rationale
        self.displayText = displayText
        self.sourcePointer = sourcePointer
        self.rawContextRef = rawContextRef
        self.confidence = confidence
        self.triggerKind = triggerKind
        self.appliedAt = appliedAt
        self.reviewedAt = reviewedAt
        self.dismissedAt = dismissedAt
        self.decisionSource = decisionSource
    }

    public var effectiveTargetDoc: MemoryDocTarget {
        appliedTargetDoc ?? targetDoc
    }

    public var effectiveDisplayText: String {
        if let displayText = Self.trimmed(displayText), displayText.isEmpty == false {
            return displayText
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var effectiveSourcePointer: String {
        if let sourcePointer = Self.trimmed(sourcePointer), sourcePointer.isEmpty == false {
            return sourcePointer
        }

        let conversation = Self.trimmed(conversationId)
        let message = Self.trimmed(messageNodeId)
        switch (conversation, message) {
        case let (conversation?, message?):
            return "\(conversation)#\(message)"
        case let (conversation?, nil):
            return conversation
        case let (nil, message?):
            return message
        case (nil, nil):
            return bookPointer
        }
    }

    public var bookPointer: String {
        var parts: [String] = []
        if let bookId {
            parts.append("book:\(bookId)")
        }
        if let chapter = Self.trimmed(chapter) {
            parts.append("chapter:\(chapter)")
        }
        if let cfi = Self.trimmed(cfi) {
            parts.append("cfi:\(cfi)")
        }
        return parts.joined(separator: " | ")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct MemoryDocumentSummary: Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case daily
        case longTerm
    }

    public let name: String
    public let kind: Kind
    public let preview: String
    public let modifiedAt: Date?

    public init(name: String, kind: Kind, preview: String, modifiedAt: Date?) {
        self.name = name
        self.kind = kind
        self.preview = preview
        self.modifiedAt = modifiedAt
    }

    public var id: String { name }
}

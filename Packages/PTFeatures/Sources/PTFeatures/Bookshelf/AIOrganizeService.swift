import Foundation
import PTCore
import PTAIServices

/// Suggests a set of group/folder assignments for a user's bookshelf using an LLM.
///
/// The service prompts a `ChatModelProvider` with book metadata (title + author),
/// asks for a JSON response describing proposed groupings, parses the response
/// into `GroupSuggestion` values and optionally applies them via `GroupDAO` / `BookDAO`.
public actor AIOrganizeService {
    public struct GroupSuggestion: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let description: String
        public let bookIds: [Int64]

        public init(
            id: UUID = UUID(),
            name: String,
            description: String,
            bookIds: [Int64]
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.bookIds = bookIds
        }
    }

    public enum OrganizeError: Error, LocalizedError, Sendable {
        case noBooks
        case noProviderResponse
        case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .noBooks:
            return AppLocalization.string("errors.organize.no_books")
        case .noProviderResponse:
            return AppLocalization.string("errors.organize.empty_response")
        case .invalidResponse(let detail):
            return AppLocalization.format("errors.organize.invalid_response_format", locale: .autoupdatingCurrent,
                detail
            )
        }
    }
}

    private let model: String

    public init(model: String = "gpt-4o-mini") {
        self.model = model
    }

    /// Request group suggestions from the provider for the supplied books.
    public func suggestGroups(
        books: [Book],
        provider: ChatModelProvider
    ) async throws -> [GroupSuggestion] {
        guard books.isEmpty == false else { throw OrganizeError.noBooks }

        let systemPrompt = """
        You are a librarian that organizes a user's personal ebook library into
        meaningful groups. Respond with STRICT JSON only — no prose, no code
        fences. The JSON schema is:
        {
          "groups": [
            {
              "name": "string",
              "description": "string",
              "book_ids": [int, int, ...]
            }
          ]
        }
        Every book must appear in exactly one group. Prefer 3–8 groups.
        """

        let bookLines = books.compactMap { book -> String? in
            guard let id = book.id else { return nil }
            let author = book.author.isEmpty ? "Unknown" : book.author
            return "- id=\(id) | \"\(book.title)\" — \(author)"
        }.joined(separator: "\n")

        let userPrompt = """
        Organize these books into topical groups:

        \(bookLines)
        """

        let request = ChatRequest(
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            model: model,
            temperature: 0.2,
            responseFormat: .json
        )

        let response = try await provider.complete(request)
        guard let text = response.message.textContent, text.isEmpty == false else {
            throw OrganizeError.noProviderResponse
        }

        return try parse(response: text)
    }

    /// Persist the supplied suggestions by creating groups and moving books.
    public func applySuggestions(
        _ suggestions: [GroupSuggestion],
        groupDAO: GroupDAO,
        bookDAO: BookDAO
    ) async throws {
        for suggestion in suggestions {
            let created = try await groupDAO.create(name: suggestion.name, parentId: nil)
            guard let groupId = created.id else { continue }
            for bookId in suggestion.bookIds {
                try await bookDAO.move(id: bookId, toGroupId: groupId)
            }
        }
    }

    // MARK: - Parsing

    internal func parse(response: String) throws -> [GroupSuggestion] {
        let cleaned = Self.stripCodeFences(response)
        guard let data = cleaned.data(using: .utf8) else {
            throw OrganizeError.invalidResponse("not utf-8")
        }

        struct Payload: Decodable {
            let groups: [RawGroup]
        }
        struct RawGroup: Decodable {
            let name: String
            let description: String?
            let book_ids: [Int64]?
            let bookIds: [Int64]?
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.groups.map { raw in
                GroupSuggestion(
                    name: raw.name,
                    description: raw.description ?? "",
                    bookIds: raw.book_ids ?? raw.bookIds ?? []
                )
            }
        } catch {
            throw OrganizeError.invalidResponse(error.localizedDescription)
        }
    }

    internal static func stripCodeFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if trimmed.hasSuffix("```") {
                trimmed.removeLast(3)
            }
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

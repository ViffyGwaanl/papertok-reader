import Foundation
import PTCore
import PTReader

/// Output format for highlight exports.
public enum HighlightExportFormat: String, Sendable, CaseIterable {
    case markdown
    case plaintext
    case json
}

/// Builds a serialized representation of all annotations (highlights,
/// notes, bookmarks) for a given book.
///
/// The output is intentionally self-contained so it can be shared via
/// `ShareLink`, copied, or written to disk by callers.
public struct HighlightExportService: Sendable {
    public init() {}

    public func export(
        bookId: Int64,
        bookTitle: String,
        format: HighlightExportFormat,
        database: AppDatabase
    ) async throws -> String {
        let dao = BookNoteDAO(database: database)
        let notes = try await dao.fetchByBookId(bookId)
        let sorted = notes.sorted { ($0.createTime ?? .distantPast) < ($1.createTime ?? .distantPast) }

        switch format {
        case .markdown:
            return renderMarkdown(notes: sorted, bookTitle: bookTitle)
        case .plaintext:
            return renderPlainText(notes: sorted, bookTitle: bookTitle)
        case .json:
            return try renderJSON(notes: sorted, bookTitle: bookTitle)
        }
    }

    // MARK: - Renderers

    private func renderMarkdown(notes: [BookNote], bookTitle: String) -> String {
        var out = "# \(bookTitle)\n\n"
        out += "Exported \(formattedDate(Date())) — \(notes.count) annotation\(notes.count == 1 ? "" : "s")\n\n"

        let groups = NoteGroup.group(notes: notes)
        for group in groups {
            out += "## \(group.title)\n\n"
            for note in group.notes {
                let chapter = note.chapter.isEmpty ? "" : " — *\(note.chapter)*"
                out += "- \(escapeMarkdown(note.content))\(chapter)\n"
                if let readerNote = note.readerNote, !readerNote.isEmpty {
                    out += "  > \(escapeMarkdown(readerNote))\n"
                }
                if let createTime = note.createTime {
                    out += "  _\(formattedDate(createTime))_\n"
                }
                out += "\n"
            }
        }
        return out
    }

    private func renderPlainText(notes: [BookNote], bookTitle: String) -> String {
        var out = "\(bookTitle)\n"
        out += String(repeating: "=", count: bookTitle.count) + "\n\n"
        for note in notes {
            out += "[\(note.type.uppercased())] \(note.content)\n"
            if !note.chapter.isEmpty {
                out += "  Chapter: \(note.chapter)\n"
            }
            if let readerNote = note.readerNote, !readerNote.isEmpty {
                out += "  Note: \(readerNote)\n"
            }
            if let createTime = note.createTime {
                out += "  \(formattedDate(createTime))\n"
            }
            out += "\n"
        }
        return out
    }

    private func renderJSON(notes: [BookNote], bookTitle: String) throws -> String {
        struct ExportEntry: Encodable {
            let type: String
            let content: String
            let chapter: String
            let color: String
            let note: String?
            let createdAt: Date?
        }
        struct ExportPayload: Encodable {
            let book: String
            let exportedAt: Date
            let entries: [ExportEntry]
        }

        let payload = ExportPayload(
            book: bookTitle,
            exportedAt: Date(),
            entries: notes.map {
                ExportEntry(
                    type: $0.type,
                    content: $0.content,
                    chapter: $0.chapter,
                    color: $0.color,
                    note: $0.readerNote,
                    createdAt: $0.createTime
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func escapeMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private struct NoteGroup {
        let title: String
        let notes: [BookNote]

        static func group(notes: [BookNote]) -> [NoteGroup] {
            var highlights: [BookNote] = []
            var bookmarks: [BookNote] = []
            var readerNotes: [BookNote] = []
            for note in notes {
                switch note.type {
                case NoteType.highlight.rawValue: highlights.append(note)
                case NoteType.bookmark.rawValue: bookmarks.append(note)
                case NoteType.note.rawValue: readerNotes.append(note)
                default: highlights.append(note)
                }
            }
            var groups: [NoteGroup] = []
            if !highlights.isEmpty { groups.append(.init(title: "Highlights", notes: highlights)) }
            if !readerNotes.isEmpty { groups.append(.init(title: "Notes", notes: readerNotes)) }
            if !bookmarks.isEmpty { groups.append(.init(title: "Bookmarks", notes: bookmarks)) }
            return groups
        }
    }
}

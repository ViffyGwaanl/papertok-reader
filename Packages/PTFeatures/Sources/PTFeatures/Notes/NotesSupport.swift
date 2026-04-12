import Foundation

public struct NotesSummary: Equatable, Sendable {
    public let totalNotes: Int
    public let booksWithNotes: Int

    public init(totalNotes: Int = 0, booksWithNotes: Int = 0) {
        self.totalNotes = totalNotes
        self.booksWithNotes = booksWithNotes
    }
}

public struct NotesBookGroup: Identifiable, Equatable, Sendable {
    public let bookId: Int64
    public let bookTitle: String
    public let notes: [BookNote]
    public let lastUpdatedAt: Date

    public var id: Int64 { bookId }

    public init(bookId: Int64, bookTitle: String, notes: [BookNote], lastUpdatedAt: Date) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.notes = notes
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public enum NotesExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case csv
    case txt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        case .txt: return "TXT"
        }
    }
}

public enum NoteColorResolver {
    public static func normalizedHex(for storedColor: String) -> String {
        let trimmed = storedColor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "8FA68A" }

        let lowered = trimmed.lowercased()
        switch lowered {
        case "yellow": return "E8D890"
        case "red": return "D09898"
        case "blue": return "90B0D0"
        case "green": return "98C8A0"
        case "purple": return "B898C8"
        default:
            return trimmed.replacingOccurrences(of: "#", with: "").uppercased()
        }
    }
}

public enum NotesExportBuilder {
    public static func render(
        groups: [NotesBookGroup],
        summary: NotesSummary,
        format: NotesExportFormat
    ) -> String {
        switch format {
        case .markdown:
            return renderMarkdown(groups: groups, summary: summary)
        case .csv:
            return renderCSV(groups: groups)
        case .txt:
            return renderText(groups: groups, summary: summary)
        }
    }

    private static func renderMarkdown(groups: [NotesBookGroup], summary: NotesSummary) -> String {
        var lines = [
            "# PaperTok Notes Export",
            "",
            "- Total notes: \(summary.totalNotes)",
            "- Books with notes: \(summary.booksWithNotes)",
        ]

        for group in groups {
            lines.append("")
            lines.append("## \(group.bookTitle)")

            for note in group.notes {
                lines.append("- [\(note.displayType)] \(note.content)")
                if note.chapter.isEmpty == false {
                    lines.append("  - Chapter: \(note.chapter)")
                }
                if let readerNote = note.readerNote, readerNote.isEmpty == false {
                    lines.append("  - Note: \(readerNote)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func renderCSV(groups: [NotesBookGroup]) -> String {
        var rows = ["book_title,note_type,chapter,content,reader_note,color"]
        for group in groups {
            for note in group.notes {
                rows.append([
                    escapeCSV(group.bookTitle),
                    escapeCSV(note.type),
                    escapeCSV(note.chapter),
                    escapeCSV(note.content),
                    escapeCSV(note.readerNote ?? ""),
                    escapeCSV(NoteColorResolver.normalizedHex(for: note.color)),
                ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func renderText(groups: [NotesBookGroup], summary: NotesSummary) -> String {
        var lines = [
            "PaperTok Notes Export",
            "Total notes: \(summary.totalNotes)",
            "Books with notes: \(summary.booksWithNotes)",
        ]

        for group in groups {
            lines.append("")
            lines.append("\(group.bookTitle)")
            lines.append(String(repeating: "-", count: max(group.bookTitle.count, 8)))

            for note in group.notes {
                lines.append("[\(note.displayType)] \(note.content)")
                if note.chapter.isEmpty == false {
                    lines.append("Chapter: \(note.chapter)")
                }
                if let readerNote = note.readerNote, readerNote.isEmpty == false {
                    lines.append("Note: \(readerNote)")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension BookNote {
    public var displayType: String {
        switch type.lowercased() {
        case "highlight": return "Highlight"
        case "bookmark": return "Bookmark"
        case "note": return "Note"
        default: return type.capitalized
        }
    }
}

import Foundation

/// Actions available in the reader context menu when text is selected.
public enum ContextMenuAction: String, CaseIterable, Identifiable, Sendable {
    case highlight
    case note
    case copy
    case translate
    case explain
    case summarize
    case define
    case search
    case share

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .highlight:  return "Highlight"
        case .note:       return "Note"
        case .copy:       return "Copy"
        case .translate:  return "Translate"
        case .explain:    return "Explain"
        case .summarize:  return "Summarize"
        case .define:     return "Define"
        case .search:     return "Search"
        case .share:      return "Share"
        }
    }

    public var icon: String {
        switch self {
        case .highlight:  return "highlighter"
        case .note:       return "note.text"
        case .copy:       return "doc.on.doc"
        case .translate:  return "globe"
        case .explain:    return "lightbulb"
        case .summarize:  return "text.justify.leading"
        case .define:     return "character.book.closed"
        case .search:     return "magnifyingglass"
        case .share:      return "square.and.arrow.up"
        }
    }

    public var category: Category {
        switch self {
        case .highlight, .note:
            return .annotate
        case .translate, .explain, .summarize, .define:
            return .ai
        case .copy, .search, .share:
            return .utility
        }
    }

    public enum Category: String, CaseIterable, Sendable {
        case annotate
        case ai
        case utility
    }
}

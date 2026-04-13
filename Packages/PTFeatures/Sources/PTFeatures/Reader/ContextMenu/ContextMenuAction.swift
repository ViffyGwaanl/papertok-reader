import Foundation
import PTCore

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
        case .highlight:  return AppLocalization.string("reader.highlight", value: "Highlight")
        case .note:       return AppLocalization.string("common.note", value: "Note")
        case .copy:       return AppLocalization.string("common.copy", value: "Copy")
        case .translate:  return AppLocalization.string("reader.quick_action.translate.title", value: "Translate")
        case .explain:    return AppLocalization.string("reader.quick_action.explain.title", value: "Explain")
        case .summarize:  return AppLocalization.string("reader.quick_action.summarize.title", value: "Summarize")
        case .define:     return AppLocalization.string("reader.quick_action.define_vocabulary.title", value: "Define")
        case .search:     return AppLocalization.string("common.search", value: "Search")
        case .share:      return AppLocalization.string("common.share", value: "Share")
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

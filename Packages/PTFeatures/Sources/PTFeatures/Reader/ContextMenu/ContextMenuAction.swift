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
        case .highlight:  return AppLocalization.string("reader.highlight")
        case .note:       return AppLocalization.string("common.note")
        case .copy:       return AppLocalization.string("common.copy")
        case .translate:  return AppLocalization.string("reader.quick_action.translate.title")
        case .explain:    return AppLocalization.string("reader.quick_action.explain.title")
        case .summarize:  return AppLocalization.string("reader.quick_action.summarize.title")
        case .define:     return AppLocalization.string("reader.quick_action.define_vocabulary.title")
        case .search:     return AppLocalization.string("common.search")
        case .share:      return AppLocalization.string("common.share")
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

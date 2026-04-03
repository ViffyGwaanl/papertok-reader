import SwiftUI

/// The 6 main tabs of the app.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case papers
    case bookshelf
    case notes
    case statistics
    case ai
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .papers: return "Papers"
        case .bookshelf: return "Bookshelf"
        case .notes: return "Notes"
        case .statistics: return "Statistics"
        case .ai: return "AI"
        case .settings: return "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .papers: return "doc.text.magnifyingglass"
        case .bookshelf: return "books.vertical"
        case .notes: return "note.text"
        case .statistics: return "chart.bar"
        case .ai: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    /// Default tab order.
    public static let defaultOrder: [AppTab] = [.papers, .bookshelf, .notes, .statistics, .ai, .settings]
}

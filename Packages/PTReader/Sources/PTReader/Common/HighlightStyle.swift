import Foundation

public enum HighlightColor: String, CaseIterable, Sendable, Codable {
    case yellow
    case red
    case blue
    case green
    case purple

    public var hex: String {
        switch self {
        case .yellow: return "FFFFEB3B"
        case .red:    return "FFF44336"
        case .blue:   return "FF2196F3"
        case .green:  return "FF4CAF50"
        case .purple: return "FF9C27B0"
        }
    }

    public init(databaseValue: String) {
        self = Self.allCases.first { $0.hex == databaseValue } ?? .yellow
    }
}

public enum NoteType: String, CaseIterable, Sendable, Codable {
    case highlight
    case bookmark
    case note
    case underline
    case strikethrough
}

import Foundation

public enum BookNoteAnnotationKind: String, Codable, Hashable, CaseIterable, Sendable {
    case highlight
    case underline
    case strikethrough
}

extension BookNote {
    public var annotationKind: BookNoteAnnotationKind {
        get { BookNoteAnnotationKind(rawValue: type) ?? .highlight }
        set { type = newValue.rawValue }
    }
}

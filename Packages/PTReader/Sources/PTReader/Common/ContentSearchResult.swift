import Foundation

public struct ContentSearchResult: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public let text: String
    public let chapterTitle: String
    public let chapterHref: String
    public let textBefore: String
    public let textAfter: String
    public let progression: Double

    public init(
        text: String,
        chapterTitle: String,
        chapterHref: String,
        textBefore: String = "",
        textAfter: String = "",
        progression: Double = 0
    ) {
        self.text = text
        self.chapterTitle = chapterTitle
        self.chapterHref = chapterHref
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.progression = progression
    }
}

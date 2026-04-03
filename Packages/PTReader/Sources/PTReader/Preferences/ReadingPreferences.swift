import Foundation
import Observation

@Observable
public final class ReadingPreferences: @unchecked Sendable {
    public var style: BookStyle
    public var theme: ReadTheme
    public var pageTurnMode: PageTurnMode
    public var textAlignment: TextAlignment
    public var isScrollMode: Bool

    public init(
        style: BookStyle = .default,
        theme: ReadTheme = .defaultLight,
        pageTurnMode: PageTurnMode = .swipe,
        textAlignment: TextAlignment = .justify,
        isScrollMode: Bool = false
    ) {
        self.style = style
        self.theme = theme
        self.pageTurnMode = pageTurnMode
        self.textAlignment = textAlignment
        self.isScrollMode = isScrollMode
    }
}

public enum PageTurnMode: String, CaseIterable, Sendable, Codable {
    case swipe
    case tap
    case scroll
}

public enum TextAlignment: String, CaseIterable, Sendable, Codable {
    case left
    case right
    case center
    case justify
}

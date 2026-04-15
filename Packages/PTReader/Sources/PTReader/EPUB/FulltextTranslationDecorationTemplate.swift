#if canImport(ReadiumNavigator)
import Foundation
import ReadiumNavigator
import ReadiumShared

public enum FulltextTranslationDecorationTemplate {
    public static let styleID: Decoration.Style.Id = "pt.translation.fulltext"
    public static let cssClass = "pt-translation-overlay"
    public static let userInfoTranslationKey = "translation"
    public static let userInfoParagraphIDKey = "paragraphId"

    public static let stylesheet: String = """
    .\(cssClass) {
        display: block;
        margin-top: 0.35em;
        font-size: 0.85em;
        line-height: 1.4;
        color: #7a6f63;
        pointer-events: none;
        font-style: normal;
        opacity: 0.92;
    }
    """

    public static func htmlTemplate() -> HTMLDecorationTemplate {
        HTMLDecorationTemplate(
            layout: .boxes,
            width: .page,
            element: { decoration in renderElementHTML(for: decoration) },
            stylesheet: stylesheet
        )
    }

    /// Renders the element HTML that the decoration template would emit for
    /// `decoration`. Exposed so the template can be snapshot-tested without
    /// reaching into Readium's internal `HTMLDecorationTemplate.element`.
    public static func renderElementHTML(for decoration: Decoration) -> String {
        let raw = (decoration.userInfo[userInfoTranslationKey as AnyHashable] as? String) ?? ""
        let escaped = htmlEscape(raw)
        return "<div class=\"\(cssClass)\">\(escaped)</div>"
    }

    public static func decoration(id: String, locator: Locator, translatedText: String) -> Decoration {
        let userInfo: [AnyHashable: AnyHashable] = [
            userInfoTranslationKey as AnyHashable: translatedText as AnyHashable,
            userInfoParagraphIDKey as AnyHashable: id as AnyHashable,
        ]
        return Decoration(
            id: id,
            locator: locator,
            style: Decoration.Style(id: styleID, config: translatedText as AnyHashable),
            userInfo: userInfo
        )
    }

    static func htmlEscape(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&#39;")
            default: out.append(ch)
            }
        }
        return out
    }
}
#endif

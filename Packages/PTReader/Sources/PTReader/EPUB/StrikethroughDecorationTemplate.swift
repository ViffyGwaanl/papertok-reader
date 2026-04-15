#if canImport(ReadiumNavigator)
import Foundation
import ReadiumNavigator
import ReadiumShared
#if canImport(UIKit)
import UIKit
#endif

/// Custom Readium HTML decoration template for the app's strikethrough
/// annotation kind. Readium 3.8.0 ships no built-in strikethrough style, so we
/// emit an absolutely-positioned overlay whose top border paints a horizontal
/// line-through across every line box of the decorated range.
public enum StrikethroughDecorationTemplate {
    public static let styleID: Decoration.Style.Id = "pt.annotation.strikethrough"
    public static let cssClass = "pt-strikethrough-overlay"
    public static let userInfoTintKey = "tintHex"
    public static let defaultTintHex = "#FFD54F"

    public static let stylesheet: String = """
    .\(cssClass) {
        position: absolute;
        left: 0;
        right: 0;
        top: 50%;
        height: 0;
        border-top: 2px solid var(--pt-tint, \(defaultTintHex));
        text-decoration: line-through;
        pointer-events: none;
        opacity: 0.85;
    }
    """

    public static func htmlTemplate() -> HTMLDecorationTemplate {
        HTMLDecorationTemplate(
            layout: .boxes,
            width: .wrap,
            element: { decoration in renderElementHTML(for: decoration) },
            stylesheet: stylesheet
        )
    }

    /// Renders the element HTML that Readium would emit for `decoration`.
    /// Exposed so the template can be snapshot-tested without reaching into
    /// Readium's internal `HTMLDecorationTemplate.element`.
    public static func renderElementHTML(for decoration: Decoration) -> String {
        let raw = (decoration.userInfo[userInfoTintKey as AnyHashable] as? String) ?? defaultTintHex
        let escaped = htmlEscape(raw)
        return "<div class=\"\(cssClass)\" style=\"--pt-tint:\(escaped);\"></div>"
    }

    public static func decoration(id: String, locator: Locator, tintHex: String) -> Decoration {
        let normalized = normalizedTintHex(tintHex)
        let userInfo: [AnyHashable: AnyHashable] = [
            userInfoTintKey as AnyHashable: normalized as AnyHashable,
        ]
        return Decoration(
            id: id,
            locator: locator,
            style: Decoration.Style(id: styleID, config: normalized as AnyHashable),
            userInfo: userInfo
        )
    }

    #if canImport(UIKit)
    public static func decoration(id: String, locator: Locator, tint: UIColor?) -> Decoration {
        decoration(id: id, locator: locator, tintHex: hexString(from: tint))
    }

    static func hexString(from color: UIColor?) -> String {
        guard let color else { return defaultTintHex }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return defaultTintHex
        }
        let ri = Int(round(max(0, min(1, r)) * 255))
        let gi = Int(round(max(0, min(1, g)) * 255))
        let bi = Int(round(max(0, min(1, b)) * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
    #endif

    /// Normalize a stored-or-user hex to a CSS-friendly `#RRGGBB` string. The
    /// app persists colors as uppercase `AARRGGBB` without the leading `#`.
    static func normalizedTintHex(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") {
            s = String(s.dropFirst())
        }
        let upper = s.uppercased()
        switch upper.count {
        case 8:
            let rgb = upper.suffix(6)
            return "#\(rgb)"
        case 6:
            return "#\(upper)"
        default:
            return defaultTintHex
        }
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

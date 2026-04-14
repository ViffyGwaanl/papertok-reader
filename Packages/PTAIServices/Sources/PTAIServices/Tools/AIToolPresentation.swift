import Foundation
import PTCore

public enum AIToolPresentation {
    public static func displayName(
        for rawName: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        AppLocalization.string(
            nameKey(for: rawName),
            locale: locale,
            value: fallbackDisplayName(for: rawName)
        )
    }

    public static func displayDescription(
        for rawName: String,
        fallback fallbackDescription: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        AppLocalization.string(
            descriptionKey(for: rawName),
            locale: locale,
            value: fallbackDescription
        )
    }

    public static func nameKey(for rawName: String) -> String {
        "ai.tool.builtin.\(rawName).name"
    }

    public static func descriptionKey(for rawName: String) -> String {
        "ai.tool.builtin.\(rawName).description"
    }

    private static func fallbackDisplayName(for rawName: String) -> String {
        rawName
            .split(separator: "_")
            .map { component in
                let token = String(component)
                switch token.lowercased() {
                case "cfi":
                    return "CFI"
                case "url":
                    return "URL"
                case "ios":
                    return "iOS"
                case "bm25":
                    return "BM25"
                case "rag":
                    return "RAG"
                default:
                    return token.capitalized
                }
            }
            .joined(separator: " ")
    }
}

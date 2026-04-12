import Foundation
import PTReader

public enum ReaderImageAnalysisPrompt {
    public static func build(
        for asset: ReaderImageAsset,
        bookTitle: String,
        chapterTitle: String?
    ) -> String {
        var lines = [
            "Analyze this image from the book \"\(bookTitle)\".",
            "Explain what it shows and how it relates to the reading."
        ]

        if let chapterTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), chapterTitle.isEmpty == false {
            lines.append("Current chapter: \(chapterTitle).")
        }
        if let title = asset.title, title.isEmpty == false {
            lines.append("Image title: \(title).")
        }
        if let altText = asset.altText, altText.isEmpty == false {
            lines.append("Alt text: \(altText).")
        }
        if let sourceURL = asset.sourceURL, sourceURL.isEmpty == false {
            lines.append("Source: \(sourceURL).")
        }

        return lines.joined(separator: " ")
    }
}

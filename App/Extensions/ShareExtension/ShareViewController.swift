#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point.
/// Receives shared files (PDF/EPUB/DOCX) and passes them to the main app via URL scheme.
class ShareViewController: UIViewController {
    /// UTIs that identify Microsoft Word .docx documents.
    private static let docxTypeIdentifiers: [String] = [
        UTType("org.openxmlformats.wordprocessingml.document")?.identifier ?? "org.openxmlformats.wordprocessingml.document",
        "com.microsoft.word.doc"
    ]

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let providers = extensionItems.compactMap { $0.attachments }.flatMap { $0 }

        Task {
            // Opportunistically extract text from any .docx attachments so downstream
            // handlers (AI chat, inbox import) receive searchable plain text.
            _ = try? await Self.extractDOCXText(from: providers)

            let eventID = UUID().uuidString
            let requestedRoute = ShareDefaultRoute.current()
            if let event = await ShareHandler.captureEvent(
                from: providers,
                eventID: eventID,
                requestedRoute: requestedRoute
            ) {
                let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? eventID
                let openURL: URL?
                switch event.route {
                case .bookshelfImport:
                    openURL = URL(string: "paperreader://import?token=\(encodedEventID)")
                case .aiChat:
                    openURL = URL(string: "paperreader://ai?share_token=\(encodedEventID)")
                case .ask:
                    openURL = URL(string: "paperreader://shortcuts/ask?share_token=\(encodedEventID)")
                }

                if let openURL {
                    // Open the main app to handle the import
                    await self.extensionContext?.open(openURL)
                }
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Detects .docx attachments in the provided item providers, loads them,
    /// and returns the concatenated extracted text (or nil if none were found).
    private static func extractDOCXText(from providers: [NSItemProvider]) async throws -> String? {
        var accumulated: [String] = []
        for provider in providers {
            guard let typeIdentifier = docxTypeIdentifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
                continue
            }

            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { loadedURL, _ in
                    continuation.resume(returning: loadedURL)
                }
            }
            guard let url else { continue }

            if let text = try? DOCXExtractor.extractText(from: url), text.isEmpty == false {
                accumulated.append(text)
            }
        }
        return accumulated.isEmpty ? nil : accumulated.joined(separator: "\n\n")
    }
}
#endif

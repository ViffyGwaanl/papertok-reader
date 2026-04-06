#if os(iOS)
import Foundation
import UniformTypeIdentifiers

/// Extracts file URLs from NSItemProvider list (called from ShareViewController).
/// Copies files to the App Group container so the main app can access them.
public enum ShareHandler {
    /// Supported file types for sharing into PaperTok Reader.
    static let supportedTypes: [UTType] = [
        .pdf,
        UTType("org.idpf.epub-container") ?? .data,
    ]

    /// Extract file URLs from extension input items.
    public static func extractFiles(from items: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []

        for item in items {
            for type in supportedTypes {
                if item.hasItemConformingToTypeIdentifier(type.identifier) {
                    if let url = try? await loadURL(from: item, type: type) {
                        let dest = sharedInboxURL().appendingPathComponent(url.lastPathComponent)
                        // Remove existing file at destination if needed
                        try? FileManager.default.removeItem(at: dest)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        urls.append(dest)
                        break
                    }
                }
            }
        }
        return urls
    }

    private static func loadURL(from item: NSItemProvider, type: UTType) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            item.loadItem(forTypeIdentifier: type.identifier, options: nil) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = data as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func sharedInboxURL() -> URL {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.ai.papertok.paperreader")!
        let inbox = container.appendingPathComponent("ShareInbox")
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }
}
#endif

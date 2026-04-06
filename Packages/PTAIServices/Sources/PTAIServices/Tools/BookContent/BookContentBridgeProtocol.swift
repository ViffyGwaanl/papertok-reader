import Foundation

/// Minimal protocol bridging PTReader.BookContentBridge without circular dependency.
/// The actual implementation lives in PTReader; it is injected at runtime via ToolContext or tool properties.
public protocol BookContentBridgeProtocol: Sendable {
    func tableOfContentsJSON() async throws -> String
    func chapterContent(href: String) async throws -> String
    func fullText() async throws -> String
    func search(query: String) async throws -> String
}

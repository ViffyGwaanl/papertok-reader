import Foundation

public protocol Translator: Sendable {
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}

public struct AITranslationServiceTranslator: Translator {
    private let service: AITranslationService

    public init(service: AITranslationService) {
        self.service = service
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let resolvedSource: String? = (source == "auto" || source.isEmpty) ? nil : source
        return try await service.translate(text, to: target, from: resolvedSource)
    }
}

import AppIntents
import Foundation
import PTCore
import PTAIServices
import PTFeatures

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ShortcutAIServiceError: LocalizedError {
    case emptyResponse
    case invalidImageData
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return AppLocalization.string("errors.ai.shortcut_empty_response")
        case .invalidImageData:
            return AppLocalization.string("errors.ai.shortcut_invalid_image")
        case .requestFailed(let message):
            return message
        }
    }
}

actor ShortcutAIService {
    private let defaults: UserDefaults
    private let store: PendingAIRequestStore

    init(
        defaults: UserDefaults = AppConfig.groupDefaults,
        store: PendingAIRequestStore? = nil
    ) {
        self.defaults = defaults
        self.store = store ?? PendingAIRequestStore(defaults: defaults)
    }

    func sendMessage(prompt: String, images: [IntentFile]?) async throws -> String {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedImages = try await encode(images ?? [])
        let queued = store.enqueue(prompt: normalizedPrompt, images: encodedImages, source: .appIntent)
        store.markStarted(id: queued.id)

        do {
            let response = try await execute(prompt: normalizedPrompt, images: encodedImages)
            store.markCompleted(id: queued.id, responseText: response)
            return response
        } catch {
            let message = userFacingMessage(for: error)
            store.markFailed(id: queued.id, message: message)
            throw ShortcutAIServiceError.requestFailed(message)
        }
    }

    private func execute(prompt: String, images: [PendingAIRequestImage]) async throws -> String {
        let resolvedProvider = StoredAIProviderCatalog(defaults: defaults).resolveCurrentProvider()
        let provider = resolvedProvider.provider
        let modelID = resolvedProvider.modelId
        let runtimePreferences = AIChatRuntimePreferences.load(
            defaults: defaults,
            providerId: resolvedProvider.providerId
        )
        let systemPrompt = defaults.string(forKey: AppConfig.Keys.aiSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var messages: [ChatMessage] = []
        if let systemPrompt, systemPrompt.isEmpty == false {
            messages.append(.system(systemPrompt))
        }

        var userContent: [ContentPart] = [.text(prompt)]
        for image in images {
            userContent.append(.imageBase64(data: image.data.base64EncodedString(), mediaType: image.mediaType))
        }
        messages.append(ChatMessage(role: .user, content: userContent))

        let response = try await provider.complete(
            ChatRequest(
                messages: messages,
                model: modelID,
                temperature: runtimePreferences.generationSettings.temperature,
                maxTokens: runtimePreferences.generationSettings.maxTokens,
                topP: runtimePreferences.generationSettings.topP,
                presencePenalty: runtimePreferences.generationSettings.presencePenalty,
                frequencyPenalty: runtimePreferences.generationSettings.frequencyPenalty,
                stopSequences: runtimePreferences.generationSettings.stopSequences.isEmpty
                    ? nil
                    : runtimePreferences.generationSettings.stopSequences,
                thinkingLevel: provider.supportedCapabilities.contains(.thinking)
                    ? (runtimePreferences.defaultThinkingLevel == .off ? nil : runtimePreferences.defaultThinkingLevel)
                    : nil
            )
        )
        let text = response.message.content.compactMap { part -> String? in
            guard case .text(let value) = part else { return nil }
            return value
        }.joined()
        let normalized = sanitizedResponseText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw ShortcutAIServiceError.emptyResponse
        }
        return normalized
    }

    private func userFacingMessage(for error: Error) -> String {
        AppLocalization.userFacingErrorMessage(
            for: error,
            fallbackKey: "errors.ai.service_unavailable"
        )
    }

    private func sanitizedResponseText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?s)\[thinking\].*?\[/thinking\]"#,
            with: "",
            options: .regularExpression
        )
    }

    private func encode(_ images: [IntentFile]) async throws -> [PendingAIRequestImage] {
        var encoded: [PendingAIRequestImage] = []
        encoded.reserveCapacity(images.count)

        for image in images {
            guard let fileURL = image.fileURL else {
                throw ShortcutAIServiceError.invalidImageData
            }
            let data = try Data(contentsOf: fileURL)
            guard let normalized = normalizeImage(data: data, fallbackFilename: fileURL.lastPathComponent) else {
                throw ShortcutAIServiceError.invalidImageData
            }
            encoded.append(normalized)
        }

        return encoded
    }

    private func normalizeImage(data: Data, fallbackFilename: String) -> PendingAIRequestImage? {
#if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let resized = resize(image: image, maxDimension: 2048)
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let baseName = URL(fileURLWithPath: fallbackFilename).deletingPathExtension().lastPathComponent
        return PendingAIRequestImage(filename: "\(baseName).jpg", mediaType: "image/jpeg", data: jpegData)
#elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        let resized = resize(image: image, maxDimension: 2048)
        guard let tiffData = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }
        let baseName = URL(fileURLWithPath: fallbackFilename).deletingPathExtension().lastPathComponent
        return PendingAIRequestImage(filename: "\(baseName).jpg", mediaType: "image/jpeg", data: jpegData)
#else
        return PendingAIRequestImage(filename: fallbackFilename, mediaType: "image/jpeg", data: data)
#endif
    }

#if canImport(UIKit)
    private func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
#elseif canImport(AppKit)
    private func resize(image: NSImage, maxDimension: CGFloat) -> NSImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let targetSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        resized.unlockFocus()
        return resized
    }
#endif
}

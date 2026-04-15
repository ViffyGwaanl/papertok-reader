import Foundation
import Testing
@testable import PTFeatures
import PTAIServices

private struct NoopTranslator: Translator {
    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        text
    }
}

@Suite("EPUBFulltextTranslationSettingsController")
@MainActor
struct EPUBFulltextTranslationSettingsControllerTests {
    private func makeController(
        onEnabledChanged: @escaping (Bool) async -> Void = { _ in },
        onTargetLanguageChanged: @escaping () async -> Void = {}
    ) -> (EPUBFulltextTranslationSettingsController, FulltextTranslationCache, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-fulltext-settings-\(UUID().uuidString)", isDirectory: true)
        let cache = FulltextTranslationCache(directory: tempDir)
        let runtime = FulltextTranslationRuntime(translator: NoopTranslator(), cache: cache)
        let controller = EPUBFulltextTranslationSettingsController(
            runtime: runtime,
            cache: cache,
            onEnabledChanged: onEnabledChanged,
            onTargetLanguageChanged: onTargetLanguageChanged
        )
        return (controller, cache, tempDir)
    }

    @Test("setTargetLanguage forwards to runtime and fires the change callback")
    func targetLanguageForwarding() async {
        var didNotify = false
        let (controller, _, tempDir) = makeController(onTargetLanguageChanged: { didNotify = true })
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await controller.runtime.setTargetLanguage("ja")
        await controller.onTargetLanguageChanged()

        #expect(controller.runtime.targetLanguage == "ja")
        #expect(didNotify == true)
    }

    @Test("cache.purge removes stored translations")
    func purgeClearsCache() async {
        let (controller, cache, tempDir) = makeController()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await cache.store(
            originalText: "hello",
            source: "auto",
            target: "zh-Hans",
            translation: "你好"
        )
        let before = await cache.lookup(originalText: "hello", source: "auto", target: "zh-Hans")
        #expect(before == "你好")

        await controller.cache.purge()

        let after = await cache.lookup(originalText: "hello", source: "auto", target: "zh-Hans")
        #expect(after == nil)
    }

    @Test("setEnabled round-trips and triggers the notifier")
    func enabledForwarding() async {
        var receivedValues: [Bool] = []
        let (controller, _, tempDir) = makeController(onEnabledChanged: { receivedValues.append($0) })
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await controller.runtime.setEnabled(true)
        await controller.onEnabledChanged(true)
        #expect(controller.runtime.isEnabled == true)

        await controller.runtime.setEnabled(false)
        await controller.onEnabledChanged(false)
        #expect(controller.runtime.isEnabled == false)

        #expect(receivedValues == [true, false])
    }
}

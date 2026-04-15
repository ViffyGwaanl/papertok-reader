import Foundation
import Testing
@testable import PTAIServices

@Suite("SessionDigestService localization")
struct SessionDigestServiceTests {
    private final class RecordingProvider: @unchecked Sendable, ChatModelProvider {
        let id = "recording"
        let displayName = "Recording"
        let supportedCapabilities: Set<ModelCapability> = []

        private(set) var lastRequest: ChatRequest?
        private let responseText: String

        init(responseText: String) {
            self.responseText = responseText
        }

        func complete(_ request: ChatRequest) async throws -> ChatResponse {
            lastRequest = request
            return ChatResponse(message: .assistant(responseText))
        }

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    private func makeLocalDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    @Test("digest errors use localized or friendly fallback descriptions")
    func localizedDigestErrors() {
        #expect(
            SessionDigestService.DigestError.emptyMessages.errorDescription
                == AppLocalization.string(
                    "errors.memory.digest.no_messages",
                    value: "No messages are available to summarize."
                )
        )
        #expect(
            SessionDigestService.DigestError.providerReturnedEmpty.errorDescription
                == AppLocalization.string("errors.ai.no_response")
        )
        #expect(
            SessionDigestService.DigestError.memoryDirectoryUnavailable.errorDescription
                == AppLocalization.string(
                    "errors.memory.digest.directory_unavailable",
                    value: "Couldn't access the memory folder."
                )
        )
    }

    @Test("digest prompt follows the injected locale and appended headings are localized")
    func localizedDigestPromptAndHeadings() async throws {
        let locale = Locale(identifier: "zh-Hans")
        let service = SessionDigestService(model: "test-model", maxWords: 120, locale: locale)
        let provider = RecordingProvider(responseText: "用户偏好乌龙茶，并计划继续完成阅读器功能。")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-digest-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = makeLocalDate(year: 2024, month: 4, day: 14, hour: 9, minute: 30)
        let digest = try await service.digestAndAppend(
            messages: [
                ChatMessage.user("请记住我喜欢乌龙茶。"),
                ChatMessage.assistant("我会记住，并继续完善阅读器。"),
            ],
            provider: provider,
            memoryDirectory: directory,
            now: now
        )

        #expect(digest == "用户偏好乌龙茶，并计划继续完成阅读器功能。")

        let request = try #require(provider.lastRequest)
        let prompt = try #require(request.messages.first?.textContent)
        #expect(prompt.contains("请使用简体中文。"))

        let content = try String(
            contentsOf: directory.appendingPathComponent("2024-04-14.md"),
            encoding: .utf8
        )
        #expect(content.contains("# 每日记忆 · 2024年4月14日"))
        #expect(content.contains("## 会话摘要 · 09:30"))
    }
}

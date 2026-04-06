import Testing
@testable import PTAIServices

@Suite("CurrentTimeTool")
struct CurrentTimeToolTests {
    @Test("returns iso8601, timestamp, and timezone")
    func returnsAllFields() async throws {
        let result = try await CurrentTimeTool().execute(
            arguments: [:],
            context: ToolContext()
        )
        #expect(!result.isError)
        #expect(result.content.contains("iso8601"))
        #expect(result.content.contains("timestamp"))
        #expect(result.content.contains("timezone"))
    }
}

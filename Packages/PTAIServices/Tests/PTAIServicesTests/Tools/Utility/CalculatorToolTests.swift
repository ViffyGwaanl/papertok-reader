import Testing
@testable import PTAIServices

@Suite("CalculatorTool")
struct CalculatorToolTests {
    let context = ToolContext()

    @Test("addition computes correctly")
    func addition() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "3 + 4"],
            context: context
        )
        #expect(result.content.contains("7"))
        #expect(!result.isError)
    }

    @Test("multiplication computes correctly")
    func multiplication() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "6 * 7"],
            context: context
        )
        #expect(result.content.contains("42"))
        #expect(!result.isError)
    }

    @Test("division by zero returns error")
    func divisionByZero() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "1 / 0"],
            context: context
        )
        #expect(result.isError)
    }

    @Test("missing expression returns error")
    func missingExpression() async throws {
        let result = try await CalculatorTool().execute(
            arguments: [:],
            context: context
        )
        #expect(result.isError)
    }

    @Test("invalid expression returns error")
    func invalidExpression() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "abc"],
            context: context
        )
        #expect(result.isError)
    }
}

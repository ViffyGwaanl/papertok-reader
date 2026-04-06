import Foundation

public struct CalculatorTool: AITool {
    public static let name = "calculator"
    public static let description = "Evaluate arithmetic expressions. Supports +, -, *, /, and parentheses."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let expression = arguments["expression"] as? String else {
            return ToolResult(content: "Missing 'expression' argument", isError: true)
        }
        do {
            let value = try evaluate(expression: expression)
            if value.isNaN || value.isInfinite {
                return ToolResult(content: "Cannot divide by zero", isError: true)
            }
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value)) : String(value)
            return ToolResult(content: formatted)
        } catch {
            return ToolResult(content: "Invalid expression: \(error.localizedDescription)", isError: true)
        }
    }

    private func evaluate(expression: String) throws -> Double {
        // Strictly allow only digits, operators, parentheses, dots, and whitespace
        let sanitized = expression.filter { $0.isNumber || $0.isWhitespace || "+-*/().".contains($0) }
        guard !sanitized.isEmpty else {
            throw NSError(domain: "Calculator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty expression"])
        }
        // Detect division by zero patterns (e.g. "/ 0", "/0") before NSExpression
        // which does integer division and silently returns 0
        let compressed = sanitized.replacingOccurrences(of: " ", with: "")
        if compressed.contains("/0") {
            // Check if 0 is actually the full number (not "10" etc.)
            let pattern = try? NSRegularExpression(pattern: "/0(?![0-9.])")
            let range = NSRange(compressed.startIndex..., in: compressed)
            if let pattern, pattern.firstMatch(in: compressed, range: range) != nil {
                return Double.infinity
            }
        }
        let expr = NSExpression(format: sanitized)
        guard let value = expr.expressionValue(with: nil, context: nil) as? Double else {
            throw NSError(domain: "Calculator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Evaluation failed"])
        }
        return value
    }
}

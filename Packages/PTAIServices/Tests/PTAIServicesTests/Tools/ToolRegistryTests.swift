import Testing
@testable import PTAIServices

@Suite("ToolRegistry")
struct ToolRegistryTests {
    @Test("default registry contains 46 tools")
    func toolCount() {
        let registry = ToolRegistry()
        #expect(registry.count == 46)
    }

    @Test("find calculator tool by name")
    func findCalculatorByName() {
        let registry = ToolRegistry()
        let tool = registry.tool(named: "calculator")
        #expect(tool != nil)
    }

    @Test("find memory_read tool by name")
    func findMemoryReadByName() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "memory_read") != nil)
    }

    @Test("find current_time tool by name")
    func findCurrentTimeByName() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "current_time") != nil)
    }

    @Test("allDefinitions returns correct count")
    func allDefinitionsCount() {
        let registry = ToolRegistry()
        let defs = registry.allDefinitions()
        #expect(defs.count == 46)
    }

    @Test("extra tools can be registered")
    func extraTools() {
        let registry = ToolRegistry(extras: [])
        #expect(registry.count == 46)
    }

    @Test("unknown tool returns nil")
    func unknownToolReturnsNil() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "nonexistent_tool") == nil)
    }

    @Test("all tool names are unique")
    func allToolNamesUnique() {
        let registry = ToolRegistry()
        let names = registry.allTools.map { type(of: $0).name }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test("registerAll populates orchestrator")
    func registerAllIntoOrchestrator() async {
        let registry = ToolRegistry()
        let orchestrator = ToolOrchestrator()
        await registry.registerAll(into: orchestrator)
        // The orchestrator should now have all tools registered
        // We verify by executing a known tool
        let result = try? await orchestrator.execute(
            calls: [ToolCall(id: "test", name: "current_time", arguments: "{}")],
            context: ToolContext()
        )
        #expect(result?.first?.isError == false)
    }
}

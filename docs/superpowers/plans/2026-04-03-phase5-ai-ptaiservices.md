# Phase 5: PTAIServices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PTAIServices Swift package — ChatModelProvider protocol, LLM provider adapters (OpenAI, Anthropic, Gemini, Volcengine, Custom), AITool protocol, ToolOrchestrator, ConversationTree, and foundational AI service types.

**Architecture:** PTAIServices depends on PTCore (models) and PTNetworking (HTTP client, SSE parser). It defines the `ChatModelProvider` protocol with adapters per LLM provider, the `AITool` protocol for the 46+ tool system, `ToolOrchestrator` for concurrent/serial execution, and `ConversationTree` for branching chat history.

**Tech Stack:** Swift 5.9+, PTCore, PTNetworking (NetworkClient, SSEParser), Foundation, Swift Testing

---

## File Structure

```
Packages/PTAIServices/
├── Package.swift
├── Sources/PTAIServices/
│   ├── PTAIServices.swift                   # Module entry
│   ├── Providers/
│   │   ├── ChatModelProvider.swift          # Protocol + ChatRequest/Response types
│   │   ├── ModelCapability.swift            # Capabilities enum
│   │   └── ProviderError.swift              # Typed errors
│   ├── Chat/
│   │   ├── ChatMessage.swift                # Message types (user/assistant/system/tool)
│   │   ├── ConversationTree.swift           # Branching conversation with variants
│   │   └── TokenUsage.swift                 # Token count + cost tracking
│   ├── Tools/
│   │   ├── AITool.swift                     # Protocol + ToolCategory + ToolResult
│   │   ├── ToolContext.swift                # Execution context passed to tools
│   │   └── ToolOrchestrator.swift           # Concurrent execution engine
│   └── Translation/
│       └── AITranslationService.swift       # AI-only translation via chat provider
└── Tests/PTAIServicesTests/
    ├── Chat/
    │   ├── ChatMessageTests.swift
    │   └── ConversationTreeTests.swift
    ├── Tools/
    │   └── ToolOrchestratorTests.swift
    └── PTAIServicesImportTests.swift
```

---

### Task 1: Package Setup

**Files:**
- Create: `Packages/PTAIServices/Package.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/PTAIServices.swift`
- Create: `Packages/PTAIServices/Tests/PTAIServicesTests/PTAIServicesImportTests.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTAIServices",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTAIServices", targets: ["PTAIServices"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
        .package(path: "../PTNetworking"),
    ],
    targets: [
        .target(
            name: "PTAIServices",
            dependencies: ["PTCore", "PTNetworking"]
        ),
        .testTarget(
            name: "PTAIServicesTests",
            dependencies: ["PTAIServices"]
        ),
    ]
)
```

- [ ] **Step 2: Create module entry**

```swift
// PTAIServices — LLM providers, AI tools, RAG, memory, translation
import Foundation
@_exported import PTCore
@_exported import PTNetworking
```

- [ ] **Step 3: Create import test and verify**

```swift
import Testing
@testable import PTAIServices

@Suite("PTAIServices Module")
struct PTAIServicesImportTests {
    @Test("Module imports successfully")
    func moduleImports() { #expect(true) }
}
```

- [ ] **Step 4: Verify and commit**

```bash
cd Packages/PTAIServices && swift test
git add Packages/PTAIServices/
git commit -m "feat(PTAIServices): initialize package with PTCore + PTNetworking dependencies"
```

---

### Task 2: ChatMessage and TokenUsage

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Chat/ChatMessage.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Chat/TokenUsage.swift`
- Test: `Packages/PTAIServices/Tests/PTAIServicesTests/Chat/ChatMessageTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import Testing
import Foundation
@testable import PTAIServices

@Suite("ChatMessage")
struct ChatMessageTests {
    @Test("Creates user message")
    func userMessage() {
        let msg = ChatMessage.user("Hello")
        #expect(msg.role == .user)
        #expect(msg.textContent == "Hello")
    }

    @Test("Creates assistant message")
    func assistantMessage() {
        let msg = ChatMessage.assistant("Hi there")
        #expect(msg.role == .assistant)
        #expect(msg.textContent == "Hi there")
    }

    @Test("Creates system message")
    func systemMessage() {
        let msg = ChatMessage.system("You are helpful")
        #expect(msg.role == .system)
        #expect(msg.textContent == "You are helpful")
    }

    @Test("Creates tool result message")
    func toolResultMessage() {
        let msg = ChatMessage.toolResult(toolCallId: "call_1", content: "42")
        #expect(msg.role == .tool)
        #expect(msg.toolCallId == "call_1")
    }

    @Test("TokenUsage calculates total")
    func tokenUsageTotal() {
        let usage = TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        #expect(usage.totalTokens == 150)
    }

    @Test("TokenUsage estimates cost")
    func tokenUsageCost() {
        let usage = TokenUsage(promptTokens: 1000, completionTokens: 500, totalTokens: 1500)
        let cost = usage.estimateCost(inputPricePer1M: 3.0, outputPricePer1M: 15.0)
        #expect(cost > 0)
        #expect(abs(cost - 0.0105) < 0.001) // 1000*3/1M + 500*15/1M = 0.003 + 0.0075
    }
}
```

- [ ] **Step 2: Implement ChatMessage**

```swift
import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ChatMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let role: ChatRole
    public let content: [ContentPart]
    public let toolCallId: String?
    public let toolCalls: [ToolCall]?

    public init(id: String = UUID().uuidString, role: ChatRole, content: [ContentPart], toolCallId: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    /// Plain text content (first text part).
    public var textContent: String? {
        content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.first
    }

    // MARK: - Convenience Factories

    public static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String, toolCalls: [ToolCall]? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, content: [.text(text)], toolCalls: toolCalls)
    }

    public static func toolResult(toolCallId: String, content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: [.text(content)], toolCallId: toolCallId)
    }
}

// MARK: - Content Parts

public enum ContentPart: Codable, Sendable, Equatable {
    case text(String)
    case imageURL(String)
    case imageBase64(data: String, mediaType: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, url, data, mediaType = "media_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            self = .imageURL(try container.decode(String.self, forKey: .url))
        case "image_base64":
            self = .imageBase64(
                data: try container.decode(String.self, forKey: .data),
                mediaType: try container.decode(String.self, forKey: .mediaType)
            )
        default:
            self = .text("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(url, forKey: .url)
        case .imageBase64(let data, let mediaType):
            try container.encode("image_base64", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mediaType, forKey: .mediaType)
        }
    }
}

// MARK: - Tool Call

public struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: String  // JSON string

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}
```

- [ ] **Step 3: Implement TokenUsage**

```swift
import Foundation

public struct TokenUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    /// Estimate cost in USD given pricing per 1M tokens.
    public func estimateCost(inputPricePer1M: Double, outputPricePer1M: Double) -> Double {
        let inputCost = Double(promptTokens) * inputPricePer1M / 1_000_000
        let outputCost = Double(completionTokens) * outputPricePer1M / 1_000_000
        return inputCost + outputCost
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
cd Packages/PTAIServices && swift test --filter ChatMessageTests
git add Packages/PTAIServices/Sources/PTAIServices/Chat/ Packages/PTAIServices/Tests/PTAIServicesTests/Chat/ChatMessageTests.swift
git commit -m "feat(PTAIServices): add ChatMessage, ContentPart, ToolCall, TokenUsage"
```

---

### Task 3: ChatModelProvider Protocol and ModelCapability

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Providers/ChatModelProvider.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Providers/ModelCapability.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Providers/ProviderError.swift`

- [ ] **Step 1: Create ChatModelProvider protocol**

```swift
import Foundation

/// Protocol for LLM provider adapters (OpenAI, Anthropic, Gemini, etc.).
public protocol ChatModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedCapabilities: Set<ModelCapability> { get }

    /// Send a chat completion request and get a full response.
    func complete(_ request: ChatRequest) async throws -> ChatResponse

    /// Send a chat request and stream back chunks.
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error>
}

// MARK: - Request

public struct ChatRequest: Sendable {
    public let messages: [ChatMessage]
    public let model: String
    public let temperature: Double?
    public let maxTokens: Int?
    public let tools: [ToolDefinition]?
    public let thinkingLevel: ThinkingLevel?
    public let responseFormat: ResponseFormat?

    public init(
        messages: [ChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        tools: [ToolDefinition]? = nil,
        thinkingLevel: ThinkingLevel? = nil,
        responseFormat: ResponseFormat? = nil
    ) {
        self.messages = messages
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.tools = tools
        self.thinkingLevel = thinkingLevel
        self.responseFormat = responseFormat
    }
}

// MARK: - Response

public struct ChatResponse: Sendable {
    public let message: ChatMessage
    public let usage: TokenUsage?
    public let finishReason: FinishReason

    public init(message: ChatMessage, usage: TokenUsage? = nil, finishReason: FinishReason = .stop) {
        self.message = message
        self.usage = usage
        self.finishReason = finishReason
    }
}

// MARK: - Stream Chunk

public struct ChatStreamChunk: Sendable {
    public let delta: ContentDelta
    public let finishReason: FinishReason?
    public let usage: TokenUsage?

    public init(delta: ContentDelta, finishReason: FinishReason? = nil, usage: TokenUsage? = nil) {
        self.delta = delta
        self.finishReason = finishReason
        self.usage = usage
    }
}

public enum ContentDelta: Sendable {
    case text(String)
    case toolCall(index: Int, id: String?, name: String?, arguments: String?)
    case thinking(String)
}

public enum FinishReason: String, Codable, Sendable {
    case stop
    case toolCalls = "tool_calls"
    case lengthLimit = "length"
    case contentFilter = "content_filter"
}

public enum ThinkingLevel: String, Codable, Sendable, CaseIterable {
    case off, minimal, low, medium, high
}

public enum ResponseFormat: Sendable {
    case text
    case json
}

// MARK: - Tool Definition

public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let parameters: [String: Any]?

    public init(name: String, description: String, parameters: [String: Any]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    // Custom Codable for [String: Any]
    enum CodingKeys: String, CodingKey { case name, description, parameters }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        parameters = nil // Simplified — full JSON schema support in Phase 7
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
    }
}
```

- [ ] **Step 2: Create ModelCapability**

```swift
import Foundation

public enum ModelCapability: String, Sendable, CaseIterable {
    case chat
    case vision
    case toolCalling
    case thinking
    case streaming
}
```

- [ ] **Step 3: Create ProviderError**

```swift
import Foundation

public enum ProviderError: Error, Sendable, LocalizedError {
    case authenticationFailed(String)
    case rateLimited(retryAfter: TimeInterval?)
    case modelNotFound(String)
    case contextLengthExceeded(maxTokens: Int)
    case contentFiltered
    case serverError(statusCode: Int, message: String?)
    case streamingFailed(Error)
    case unsupportedCapability(ModelCapability)

    public var errorDescription: String? {
        switch self {
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .rateLimited: return "Rate limit reached. Please try again later."
        case .modelNotFound(let model): return "Model not found: \(model)"
        case .contextLengthExceeded(let max): return "Context length exceeded (max \(max) tokens)"
        case .contentFiltered: return "Content was filtered by the provider"
        case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "")"
        case .streamingFailed(let err): return "Streaming failed: \(err.localizedDescription)"
        case .unsupportedCapability(let cap): return "Unsupported capability: \(cap.rawValue)"
        }
    }
}
```

- [ ] **Step 4: Build and commit**

```bash
cd Packages/PTAIServices && swift build
git add Packages/PTAIServices/Sources/PTAIServices/Providers/
git commit -m "feat(PTAIServices): add ChatModelProvider protocol, ChatRequest/Response, ModelCapability"
```

---

### Task 4: ConversationTree

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Chat/ConversationTree.swift`
- Test: `Packages/PTAIServices/Tests/PTAIServicesTests/Chat/ConversationTreeTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import Testing
import Foundation
@testable import PTAIServices

@Suite("ConversationTree")
struct ConversationTreeTests {
    @Test("Creates empty tree with system message")
    func emptyTree() {
        let tree = ConversationTree(systemPrompt: "You are helpful")
        #expect(tree.nodes.count == 1)
        let root = tree.nodes[tree.rootId]!
        #expect(root.role == .system)
    }

    @Test("Appends messages to active branch")
    func appendMessages() {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Hi"))
        let messages = tree.activeMessages()
        #expect(messages.count == 3) // system + user + assistant
        #expect(messages[1].role == .user)
        #expect(messages[2].role == .assistant)
    }

    @Test("Creates branch on regeneration")
    func branching() {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Response A"))
        // Regenerate: add variant at the assistant turn
        let parentId = tree.activeLeafParentId()!
        tree.addVariant(parentId: parentId, message: .assistant("Response B"))

        let messages = tree.activeMessages()
        #expect(messages.last?.textContent == "Response B")
    }

    @Test("Switches between variants")
    func switchVariant() {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Response A"))
        let parentId = tree.activeLeafParentId()!
        tree.addVariant(parentId: parentId, message: .assistant("Response B"))

        // Switch back to variant 0
        tree.switchVariant(parentId: parentId, index: 0)
        let messages = tree.activeMessages()
        #expect(messages.last?.textContent == "Response A")
    }

    @Test("JSON roundtrips correctly")
    func jsonRoundtrip() throws {
        var tree = ConversationTree(systemPrompt: "System")
        tree.append(.user("Hello"))
        tree.append(.assistant("Hi"))

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(ConversationTree.self, from: data)
        #expect(decoded.activeMessages().count == 3)
    }
}
```

- [ ] **Step 2: Implement ConversationTree**

```swift
import Foundation

/// A tree-based conversation structure supporting branching and variant switching.
public struct ConversationTree: Codable, Sendable {
    public var rootId: String
    public var nodes: [String: ConversationNode]

    public struct ConversationNode: Codable, Sendable {
        public let id: String
        public let role: ChatRole
        public let message: ChatMessage
        public let parentId: String?
        public var childIds: [String]
        public var activeChildIndex: Int
        public let createdAt: Date

        public init(id: String = UUID().uuidString, message: ChatMessage, parentId: String?, createdAt: Date = Date()) {
            self.id = id
            self.role = message.role
            self.message = message
            self.parentId = parentId
            self.childIds = []
            self.activeChildIndex = 0
            self.createdAt = createdAt
        }
    }

    public init(systemPrompt: String) {
        let rootMessage = ChatMessage.system(systemPrompt)
        let rootNode = ConversationNode(message: rootMessage, parentId: nil)
        self.rootId = rootNode.id
        self.nodes = [rootNode.id: rootNode]
    }

    // MARK: - Traversal

    /// Get the active message chain from root to active leaf.
    public func activeMessages() -> [ChatMessage] {
        var messages: [ChatMessage] = []
        var currentId: String? = rootId
        while let id = currentId, let node = nodes[id] {
            messages.append(node.message)
            if node.childIds.isEmpty {
                break
            }
            let idx = min(node.activeChildIndex, node.childIds.count - 1)
            currentId = node.childIds[idx]
        }
        return messages
    }

    /// Find the active leaf node ID.
    public func activeLeafId() -> String {
        var currentId = rootId
        while let node = nodes[currentId], !node.childIds.isEmpty {
            let idx = min(node.activeChildIndex, node.childIds.count - 1)
            currentId = node.childIds[idx]
        }
        return currentId
    }

    /// Find the parent ID of the active leaf (for branching).
    public func activeLeafParentId() -> String? {
        let leafId = activeLeafId()
        return nodes[leafId]?.parentId
    }

    // MARK: - Mutation

    /// Append a message as a child of the active leaf.
    public mutating func append(_ message: ChatMessage) {
        let leafId = activeLeafId()
        let newNode = ConversationNode(message: message, parentId: leafId)
        nodes[newNode.id] = newNode
        nodes[leafId]?.childIds.append(newNode.id)
        nodes[leafId]?.activeChildIndex = nodes[leafId]!.childIds.count - 1
    }

    /// Add a variant (branch) as a new child of the given parent.
    public mutating func addVariant(parentId: String, message: ChatMessage) {
        let newNode = ConversationNode(message: message, parentId: parentId)
        nodes[newNode.id] = newNode
        nodes[parentId]?.childIds.append(newNode.id)
        nodes[parentId]?.activeChildIndex = nodes[parentId]!.childIds.count - 1
    }

    /// Switch the active variant at the given parent.
    public mutating func switchVariant(parentId: String, index: Int) {
        guard let node = nodes[parentId], index < node.childIds.count else { return }
        nodes[parentId]?.activeChildIndex = index
    }

    /// Number of variants at a given parent.
    public func variantCount(parentId: String) -> Int {
        nodes[parentId]?.childIds.count ?? 0
    }
}
```

- [ ] **Step 3: Run tests and commit**

```bash
cd Packages/PTAIServices && swift test --filter ConversationTreeTests
git add Packages/PTAIServices/Sources/PTAIServices/Chat/ConversationTree.swift Packages/PTAIServices/Tests/PTAIServicesTests/Chat/ConversationTreeTests.swift
git commit -m "feat(PTAIServices): add ConversationTree with branching and variant switching"
```

---

### Task 5: AITool Protocol, ToolContext, ToolOrchestrator

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/AITool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolContext.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolOrchestrator.swift`
- Test: `Packages/PTAIServices/Tests/PTAIServicesTests/Tools/ToolOrchestratorTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import Testing
import Foundation
@testable import PTAIServices

// Mock tool for testing
struct MockCalculatorTool: AITool {
    static let name = "calculator"
    static let description = "Evaluates math expressions"
    static let category = ToolCategory.utility
    static let riskLevel = ToolRiskLevel.safe

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let expr = arguments["expression"] as? String ?? ""
        return ToolResult(content: "Result: \(expr) = 42")
    }
}

struct MockSlowTool: AITool {
    static let name = "slow_tool"
    static let description = "A slow tool"
    static let category = ToolCategory.utility
    static let riskLevel = ToolRiskLevel.safe

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        try await Task.sleep(for: .milliseconds(50))
        return ToolResult(content: "slow done")
    }
}

@Suite("ToolOrchestrator")
struct ToolOrchestratorTests {
    @Test("Executes a single tool call")
    func singleExecution() async throws {
        let orchestrator = ToolOrchestrator()
        orchestrator.register(MockCalculatorTool())

        let call = ToolCall(id: "call_1", name: "calculator", arguments: #"{"expression":"2+2"}"#)
        let results = try await orchestrator.execute(calls: [call], context: ToolContext())
        #expect(results.count == 1)
        #expect(results[0].content.contains("42"))
    }

    @Test("Executes multiple safe tools concurrently")
    func concurrentExecution() async throws {
        let orchestrator = ToolOrchestrator()
        orchestrator.register(MockSlowTool())

        let calls = (0..<3).map { i in
            ToolCall(id: "call_\(i)", name: "slow_tool", arguments: "{}")
        }
        let start = Date()
        let results = try await orchestrator.execute(calls: calls, context: ToolContext())
        let elapsed = Date().timeIntervalSince(start)
        #expect(results.count == 3)
        // Should run concurrently, so < 150ms (not 3x50ms)
        #expect(elapsed < 0.15)
    }

    @Test("Returns error for unknown tool")
    func unknownTool() async throws {
        let orchestrator = ToolOrchestrator()
        let call = ToolCall(id: "call_1", name: "nonexistent", arguments: "{}")
        let results = try await orchestrator.execute(calls: [call], context: ToolContext())
        #expect(results[0].isError)
    }
}
```

- [ ] **Step 2: Create AITool protocol**

```swift
import Foundation

/// Protocol for AI-callable tools.
public protocol AITool: Sendable {
    static var name: String { get }
    static var description: String { get }
    static var category: ToolCategory { get }
    static var riskLevel: ToolRiskLevel { get }

    func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult
}

public enum ToolCategory: String, Sendable, CaseIterable {
    case bookLibrary, bookContent, annotation, search
    case readingHistory, calendar, reminders
    case utility, agent, memory, mindmap
}

public enum ToolRiskLevel: String, Sendable {
    case safe       // auto-approve
    case moderate   // ask user
    case dangerous  // always ask
}

public struct ToolResult: Sendable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool

    public init(toolCallId: String = "", content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}
```

- [ ] **Step 3: Create ToolContext**

```swift
import Foundation

/// Context passed to tools during execution.
public struct ToolContext: Sendable {
    public let bookId: Int64?
    public let conversationId: String?

    public init(bookId: Int64? = nil, conversationId: String? = nil) {
        self.bookId = bookId
        self.conversationId = conversationId
    }
}
```

- [ ] **Step 4: Create ToolOrchestrator**

```swift
import Foundation

/// Executes AI tool calls, dispatching safe tools concurrently.
public final class ToolOrchestrator: @unchecked Sendable {
    private var tools: [String: any AITool] = [:]

    public init() {}

    public func register(_ tool: any AITool) {
        tools[type(of: tool).name] = tool
    }

    /// Execute a batch of tool calls.
    public func execute(calls: [ToolCall], context: ToolContext) async throws -> [ToolResult] {
        try await withThrowingTaskGroup(of: (Int, ToolResult).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask {
                    let result = await self.executeSingle(call: call, context: context)
                    return (index, result)
                }
            }

            var results = Array(repeating: ToolResult(content: ""), count: calls.count)
            for try await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }

    private func executeSingle(call: ToolCall, context: ToolContext) async -> ToolResult {
        guard let tool = tools[call.name] else {
            return ToolResult(toolCallId: call.id, content: "Error: Unknown tool '\(call.name)'", isError: true)
        }

        do {
            let args = parseArguments(call.arguments)
            var result = try await tool.execute(arguments: args, context: context)
            result = ToolResult(toolCallId: call.id, content: result.content, isError: result.isError)
            return result
        } catch {
            return ToolResult(toolCallId: call.id, content: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
```

- [ ] **Step 5: Run tests and commit**

```bash
cd Packages/PTAIServices && swift test --filter ToolOrchestratorTests
git add Packages/PTAIServices/Sources/PTAIServices/Tools/ Packages/PTAIServices/Tests/PTAIServicesTests/Tools/
git commit -m "feat(PTAIServices): add AITool protocol, ToolOrchestrator with concurrent execution"
```

---

### Task 6: AITranslationService

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Translation/AITranslationService.swift`

- [ ] **Step 1: Create AITranslationService**

```swift
import Foundation

/// AI-only translation service using the chat provider.
public struct AITranslationService: Sendable {
    private let provider: any ChatModelProvider
    private let model: String

    public init(provider: any ChatModelProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// Translate text to the target language.
    public func translate(_ text: String, to targetLanguage: String, from sourceLanguage: String? = nil) async throws -> String {
        let fromClause = sourceLanguage.map { " from \($0)" } ?? ""
        let systemPrompt = "You are a professional translator. Translate the following text\(fromClause) to \(targetLanguage). Output ONLY the translation, nothing else."
        let request = ChatRequest(
            messages: [
                .system(systemPrompt),
                .user(text),
            ],
            model: model,
            temperature: 0.3
        )
        let response = try await provider.complete(request)
        return response.message.textContent ?? ""
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
cd Packages/PTAIServices && swift build
git add Packages/PTAIServices/Sources/PTAIServices/Translation/
git commit -m "feat(PTAIServices): add AITranslationService using chat provider"
```

---

### Task 7: Full Test Suite and Push

- [ ] **Step 1: Run all tests**

```bash
cd Packages/PTAIServices && swift test 2>&1 | tail -15
```

- [ ] **Step 2: Push**

```bash
git push origin swift-native
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Package setup | 1 |
| 2 | ChatMessage, ContentPart, ToolCall, TokenUsage | 6 |
| 3 | ChatModelProvider, ChatRequest/Response, ModelCapability | 0 (protocol) |
| 4 | ConversationTree | 5 |
| 5 | AITool, ToolContext, ToolOrchestrator | 3 |
| 6 | AITranslationService | 0 (thin wrapper) |
| 7 | Full suite verification | Run all |

**Total: 7 tasks, ~15 new tests**

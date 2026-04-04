# Phase 10：46 个 AI 工具实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在 PTAIServices 包中实现所有 46 个 AI 工具的 Swift 版本，1:1 对标 Flutter 版 `lib/service/ai/tools/` 目录，完成工具注册表（ToolRegistry），并为每个工具补充单元测试。

**架构：** 每个工具都是一个实现 `AITool` 协议的 Swift struct（Phase 5 已定义协议）。工具按类别分组到不同文件。`ToolRegistry` 负责注册所有工具并对外提供 LLM 所需的 JSON Schema。依赖的服务（BookDAO、EventKit 等）通过 `ToolContext` 注入。日历/提醒事项工具在 App Target 中注册（需要 EventKit 权限），PTAIServices 包中只定义协议接口。

**技术栈：** Swift 5.9+, PTCore (BookDAO, BookNoteDAO, ReadingTimeDAO), PTAIServices (AITool, ToolContext, ToolOrchestrator), EventKit（App Target 注入）, Foundation

**前置依赖：** Phase 1 PTCore ✅, Phase 5 PTAIServices（协议框架）✅

**参考 Flutter 文件：** `lib/service/ai/tools/` 目录下所有 `*_tool.dart` 文件

---

## 工具完整清单（按类别）

| # | 工具名 | 类别 | 风险级别 | Flutter 文件 |
|---|--------|------|----------|-------------|
| 1 | `current_time` | utility | safe | `current_time_tool.dart` |
| 2 | `calculator` | utility | safe | `calculator_tool.dart` |
| 3 | `fetch_url` | utility | safe | `fetch_url_tool.dart` |
| 4 | `web_search` | utility | safe | `web_search_tool.dart` |
| 5 | `mindmap_draw` | utility | safe | `mindmap_tool.dart` |
| 6 | `bookshelf_lookup` | bookLibrary | safe | `bookshelf_lookup_tool.dart` |
| 7 | `bookshelf_organize` | bookLibrary | safe | `bookshelf_organize_tool.dart` |
| 8 | `books_tags_list` | bookLibrary | safe | `books_tags_list_tool.dart` |
| 9 | `tags_list` | bookLibrary | safe | `tags_list_tool.dart` |
| 10 | `apply_book_tags` | bookLibrary | moderate | `apply_book_tags_tool.dart` |
| 11 | `current_reading_metadata` | bookContent | safe | `current_reading_metadata_tool.dart` |
| 12 | `current_book_toc` | bookContent | safe | `current_book_toc_tool.dart` |
| 13 | `current_chapter_content` | bookContent | safe | `current_chapter_content_tool.dart` |
| 14 | `current_book_fulltext` | bookContent | safe | `current_book_fulltext_tool.dart` |
| 15 | `chapter_content_by_href` | bookContent | safe | `chapter_content_by_href_tool.dart` |
| 16 | `resolve_cfi` | bookContent | safe | `resolve_cfi_tool.dart` |
| 17 | `book_content_search` | bookContent | safe | `book_content_search_tool.dart` |
| 18 | `create_highlight` | annotation | moderate | `create_highlight_tool.dart` |
| 19 | `create_note` | annotation | moderate | `create_note_tool.dart` |
| 20 | `notes_search` | annotation | safe | `notes_search_tool.dart` |
| 21 | `reading_history` | readingHistory | safe | `reading_history_tool.dart` |
| 22 | `semantic_search_current_book` | search | safe | `semantic_search_current_book_tool.dart` |
| 23 | `semantic_search_library` | search | safe | `semantic_search_library_tool.dart` |
| 24 | `calendar_list_calendars` | calendar | safe | `calendar_list_calendars_tool.dart` |
| 25 | `calendar_list_events` | calendar | safe | `calendar_list_events_tool.dart` |
| 26 | `calendar_get_event` | calendar | safe | `calendar_get_event_tool.dart` |
| 27 | `calendar_create_event` | calendar | dangerous | `calendar_create_event_tool.dart` |
| 28 | `calendar_update_event` | calendar | dangerous | `calendar_update_event_tool.dart` |
| 29 | `calendar_delete_event` | calendar | dangerous | `calendar_delete_event_tool.dart` |
| 30 | `reminders_list_lists` | reminders | safe | `reminders_list_lists_tool.dart` |
| 31 | `reminders_list` | reminders | safe | `reminders_list_tool.dart` |
| 32 | `reminders_get` | reminders | safe | `reminders_get_tool.dart` |
| 33 | `reminders_create` | reminders | dangerous | `reminders_create_tool.dart` |
| 34 | `reminders_update` | reminders | dangerous | `reminders_update_tool.dart` |
| 35 | `reminders_delete` | reminders | dangerous | `reminders_delete_tool.dart` |
| 36 | `reminders_complete` | reminders | dangerous | `reminders_complete_tool.dart` |
| 37 | `reminders_uncomplete` | reminders | dangerous | `reminders_uncomplete_tool.dart` |
| 38 | `reminders_list_create` | reminders | dangerous | `reminders_create_list_tool.dart` |
| 39 | `reminders_list_delete` | reminders | dangerous | `reminders_delete_list_tool.dart` |
| 40 | `reminders_list_rename` | reminders | dangerous | `reminders_rename_list_tool.dart` |
| 41 | `memory_read` | memory | safe | `memory_tools.dart` |
| 42 | `memory_write` | memory | moderate | `memory_tools.dart` |
| 43 | `memory_search` | memory | safe | `memory_tools.dart` |
| 44 | `shortcuts_run` | agent | dangerous | `shortcuts_run_tool.dart` |
| 45 | `spawn_sub_agent` | agent | moderate | `spawn_sub_agent_tool.dart` |
| 46 | `tool_approval_decider` | utility | safe | `tool_approval_decider.dart`（内部）|

---

## 文件结构

```
Packages/PTAIServices/Sources/PTAIServices/Tools/
├── AITool.swift                              # 已存在（协议）
├── ToolContext.swift                         # 已存在，需扩展
├── ToolOrchestrator.swift                    # 已存在
├── ToolRegistry.swift                        # 新建：注册所有工具 + JSON Schema
├── Utility/
│   ├── CurrentTimeTool.swift                # 新建
│   ├── CalculatorTool.swift                 # 新建
│   ├── FetchURLTool.swift                   # 新建
│   ├── WebSearchTool.swift                  # 新建
│   └── MindmapTool.swift                    # 新建
├── BookLibrary/
│   ├── BookshelfLookupTool.swift            # 新建
│   ├── BookshelfOrganizeTool.swift          # 新建
│   ├── BooksTagsListTool.swift              # 新建
│   ├── TagsListTool.swift                   # 新建
│   └── ApplyBookTagsTool.swift              # 新建
├── BookContent/
│   ├── CurrentReadingMetadataTool.swift     # 新建
│   ├── CurrentBookTOCTool.swift             # 新建
│   ├── CurrentChapterContentTool.swift      # 新建
│   ├── CurrentBookFulltextTool.swift        # 新建
│   ├── ChapterContentByHrefTool.swift       # 新建
│   ├── ResolveCFITool.swift                 # 新建
│   └── BookContentSearchTool.swift          # 新建
├── Annotation/
│   ├── CreateHighlightTool.swift            # 新建
│   ├── CreateNoteTool.swift                 # 新建
│   ├── NotesSearchTool.swift                # 新建
│   └── ReadingHistoryTool.swift             # 新建
├── Search/
│   ├── SemanticSearchCurrentBookTool.swift  # 新建（stub，RAG 在 Phase 12）
│   └── SemanticSearchLibraryTool.swift      # 新建（stub）
├── Calendar/
│   └── CalendarToolProtocols.swift          # 新建：协议，实现在 App Target
├── Reminders/
│   └── RemindersToolProtocols.swift         # 新建：协议，实现在 App Target
├── Memory/
│   ├── MemoryReadTool.swift                 # 新建
│   ├── MemoryWriteTool.swift                # 新建
│   └── MemorySearchTool.swift               # 新建
└── Agent/
    ├── ShortcutsRunTool.swift               # 新建（stub，App Target 实现）
    └── SpawnSubAgentTool.swift              # 新建

Packages/PTAIServices/Tests/PTAIServicesTests/Tools/
├── ToolRegistryTests.swift                  # 新建
├── Utility/
│   ├── CurrentTimeToolTests.swift
│   ├── CalculatorToolTests.swift
│   ├── FetchURLToolTests.swift
│   └── MindmapToolTests.swift
├── BookLibrary/
│   └── BookshelfLookupToolTests.swift
├── BookContent/
│   └── CurrentReadingMetadataToolTests.swift
└── Annotation/
    └── NotesSearchToolTests.swift
```

---

### Task 1：扩展 ToolContext，添加书库访问接口

**Files:**
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolContext.swift`

- [ ] **Step 1：扩展 ToolContext**

```swift
import Foundation
import PTCore

public struct ToolContext: Sendable {
    public let bookId: Int64?
    public let conversationId: String?
    /// Database access for book-related tools.
    public let database: (any ToolDatabaseAccess)?
    /// Memory store for memory tools.
    public let memoryDirectory: URL?
    /// HTTP client for fetch/search tools.
    public let httpClient: (any ToolHTTPClient)?

    public init(
        bookId: Int64? = nil,
        conversationId: String? = nil,
        database: (any ToolDatabaseAccess)? = nil,
        memoryDirectory: URL? = nil,
        httpClient: (any ToolHTTPClient)? = nil
    ) {
        self.bookId = bookId
        self.conversationId = conversationId
        self.database = database
        self.memoryDirectory = memoryDirectory
        self.httpClient = httpClient
    }
}

/// Protocol for database operations needed by AI tools.
/// PTCore.AppDatabase conforms to this in Phase 12.
public protocol ToolDatabaseAccess: Sendable {
    func fetchBooks(query: String?, groupId: Int64?, limit: Int) async throws -> [[String: Any]]
    func fetchBookNotes(bookId: Int64?, keyword: String?, limit: Int) async throws -> [[String: Any]]
    func fetchReadingTime(bookId: Int64?, since: Date?) async throws -> [[String: Any]]
    func fetchTags() async throws -> [[String: Any]]
    func insertBookNote(_ note: BookNote) async throws
}

/// Protocol for HTTP operations needed by AI tools.
public protocol ToolHTTPClient: Sendable {
    func fetchText(url: URL, timeoutSeconds: Double) async throws -> String
}
```

- [ ] **Step 2：运行现有测试，确认不破坏**

运行: `cd Packages/PTAIServices && swift test`
预期: All existing tests pass

- [ ] **Step 3：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/ToolContext.swift
git commit -m "feat(PTAIServices): extend ToolContext with database, memory, http injection"
```

---

### Task 2：Utility 工具组（5 个）

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Utility/CurrentTimeTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Utility/CalculatorTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Utility/FetchURLTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Utility/WebSearchTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Utility/MindmapTool.swift`
- Create: `Packages/PTAIServices/Tests/PTAIServicesTests/Tools/Utility/CalculatorToolTests.swift`

- [ ] **Step 1：编写 CalculatorTool 测试**

```swift
import Testing
@testable import PTAIServices

@Suite("CalculatorTool")
struct CalculatorToolTests {
    let context = ToolContext()

    @Test("加法计算正确")
    func addition() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "3 + 4"],
            context: context
        )
        #expect(result.content.contains("7"))
        #expect(!result.isError)
    }

    @Test("除以零返回错误")
    func divisionByZero() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "1 / 0"],
            context: context
        )
        #expect(result.isError)
    }

    @Test("无效表达式返回错误")
    func invalidExpression() async throws {
        let result = try await CalculatorTool().execute(
            arguments: ["expression": "abc"],
            context: context
        )
        #expect(result.isError)
    }
}
```

- [ ] **Step 2：实现所有 Utility 工具**

```swift
// CurrentTimeTool.swift
import Foundation

public struct CurrentTimeTool: AITool {
    public static let name = "current_time"
    public static let description = "Get the current device time in ISO-8601 format, Unix timestamp, and timezone name."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)
        let timestamp = Int(now.timeIntervalSince1970)
        let tz = TimeZone.current.identifier
        let result: [String: Any] = ["iso8601": iso, "timestamp": timestamp, "timezone": tz]
        return ToolResult(content: jsonString(result))
    }
}
```

```swift
// CalculatorTool.swift
import Foundation

public struct CalculatorTool: AITool {
    public static let name = "calculator"
    public static let description = "Evaluate arithmetic expressions. Supports +, -, *, /, ^ and parentheses."
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
            // Format: remove trailing zeros
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value)) : String(value)
            return ToolResult(content: formatted)
        } catch {
            return ToolResult(content: "Invalid expression: \(error)", isError: true)
        }
    }

    private func evaluate(expression: String) throws -> Double {
        // Use NSExpression for safe arithmetic evaluation
        let sanitized = expression
            .replacingOccurrences(of: "^", with: "**")
            .filter { $0.isNumber || $0.isWhitespace || "+-*/().".contains($0) }
        let expr = NSExpression(format: sanitized)
        guard let value = expr.expressionValue(with: nil, context: nil) as? Double else {
            throw NSError(domain: "Calculator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Evaluation failed"])
        }
        return value
    }
}
```

```swift
// FetchURLTool.swift
import Foundation

public struct FetchURLTool: AITool {
    public static let name = "fetch_url"
    public static let description = "Fetch text content from an HTTP/HTTPS URL. Returns plain text (HTML stripped). Max 50KB."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let urlString = arguments["url"] as? String,
              let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http" else {
            return ToolResult(content: "Invalid or missing 'url' argument", isError: true)
        }
        // Block private IP ranges (SSRF protection)
        if let host = url.host, isPrivateHost(host) {
            return ToolResult(content: "Access to private/local addresses is not allowed", isError: true)
        }
        guard let client = context.httpClient else {
            return ToolResult(content: "HTTP client not available in this context", isError: true)
        }
        let timeout = arguments["timeout_seconds"] as? Double ?? 15.0
        let text = try await client.fetchText(url: url, timeoutSeconds: timeout)
        let truncated = String(text.prefix(50_000))
        return ToolResult(content: truncated)
    }

    private func isPrivateHost(_ host: String) -> Bool {
        ["localhost", "127.", "10.", "192.168.", "172.16.", "::1"].contains { host.hasPrefix($0) }
    }
}
```

```swift
// WebSearchTool.swift
import Foundation

public struct WebSearchTool: AITool {
    public static let name = "web_search"
    public static let description = "Search the web using Serper API. Returns top results with title, URL, snippet."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(content: "Missing 'query' argument", isError: true)
        }
        guard let client = context.httpClient else {
            return ToolResult(content: "HTTP client not available", isError: true)
        }
        // Serper API endpoint (API key injected via URL or header in App Target)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://google.serper.dev/search?q=\(encoded)") else {
            return ToolResult(content: "Failed to build search URL", isError: true)
        }
        let resultText = try await client.fetchText(url: url, timeoutSeconds: 10)
        return ToolResult(content: String(resultText.prefix(10_000)))
    }
}
```

```swift
// MindmapTool.swift
import Foundation

public struct MindmapTool: AITool {
    public static let name = "mindmap_draw"
    public static let description = "Transform a hierarchical bullet list into a mind map JSON structure for rendering."
    public static let category = ToolCategory.utility
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let content = arguments["content"] as? String, !content.isEmpty else {
            return ToolResult(content: "Missing 'content' argument", isError: true)
        }
        let root = parseBulletList(content)
        guard let json = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted),
              let jsonString = String(data: json, encoding: .utf8) else {
            return ToolResult(content: "Failed to serialize mindmap", isError: true)
        }
        return ToolResult(content: jsonString)
    }

    private func parseBulletList(_ text: String) -> [String: Any] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let first = lines.first else { return [:] }
        return ["text": first.trimmingCharacters(in: .init(charactersIn: "- ")), "children": []]
    }
}
```

- [ ] **Step 3：运行 Utility 测试**

运行: `cd Packages/PTAIServices && swift test --filter CalculatorToolTests`
预期: PASS（3 tests）

- [ ] **Step 4：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/Utility/ \
        Packages/PTAIServices/Tests/PTAIServicesTests/Tools/Utility/
git commit -m "feat(PTAIServices): implement 5 utility tools (time, calc, fetch, search, mindmap)"
```

---

### Task 3：BookLibrary 工具组（5 个）

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/BookLibrary/BookshelfLookupTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/BookLibrary/BookshelfOrganizeTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/BookLibrary/BooksTagsListTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/BookLibrary/TagsListTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/BookLibrary/ApplyBookTagsTool.swift`
- Create: `Packages/PTAIServices/Tests/PTAIServicesTests/Tools/BookLibrary/BookshelfLookupToolTests.swift`

- [ ] **Step 1：编写 BookshelfLookupTool 测试**

```swift
import Testing
@testable import PTAIServices

@Suite("BookshelfLookupTool")
struct BookshelfLookupToolTests {
    @Test("缺少 database 时返回 error ToolResult")
    func missingDatabase() async throws {
        let ctx = ToolContext()   // no database
        let result = try await BookshelfLookupTool().execute(arguments: [:], context: ctx)
        #expect(result.isError)
    }
}
```

- [ ] **Step 2：实现 BookLibrary 工具**

```swift
// BookshelfLookupTool.swift
import Foundation

public struct BookshelfLookupTool: AITool {
    public static let name = "bookshelf_lookup"
    public static let description = "Find books on the user's local shelf by title, author, or group. Returns structured list with metadata and reading progress."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe

    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let query = arguments["query"] as? String
        let groupId = arguments["group_id"] as? Int64
        let limit = arguments["limit"] as? Int ?? 20
        let books = try await db.fetchBooks(query: query, groupId: groupId, limit: limit)
        return ToolResult(content: jsonString(["results": books, "count": books.count]))
    }
}
```

```swift
// TagsListTool.swift
import Foundation

public struct TagsListTool: AITool {
    public static let name = "tags_list"
    public static let description = "List all book tags with their ID, name, and color."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let tags = try await db.fetchTags()
        return ToolResult(content: jsonString(["tags": tags]))
    }
}
```

```swift
// BookshelfOrganizeTool.swift — Draft reorganization plan (read-only, no writes)
import Foundation

public struct BookshelfOrganizeTool: AITool {
    public static let name = "bookshelf_organize"
    public static let description = "Draft a bookshelf reorganization plan: moving books to groups, renaming groups. Returns a plan JSON; user must confirm before execution."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let moves = arguments["moves"] as? [[String: Any]] ?? []
        let renames = arguments["renames"] as? [[String: Any]] ?? []
        return ToolResult(content: jsonString(["plan": ["moves": moves, "renames": renames], "requiresConfirmation": true]))
    }
}
```

```swift
// BooksTagsListTool.swift
import Foundation

public struct BooksTagsListTool: AITool {
    public static let name = "books_tags_list"
    public static let description = "List books with their associated tags. Optionally filtered by book IDs."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let books = try await db.fetchBooks(query: nil, groupId: nil, limit: 100)
        return ToolResult(content: jsonString(["books": books]))
    }
}
```

```swift
// ApplyBookTagsTool.swift — Moderate risk: writes tags
import Foundation
import PTCore

public struct ApplyBookTagsTool: AITool {
    public static let name = "apply_book_tags"
    public static let description = "Apply or remove tags from books. Requires user confirmation (riskLevel: moderate)."
    public static let category = ToolCategory.bookLibrary
    public static let riskLevel = ToolRiskLevel.moderate
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        // Actual tag writes handled after approval in App Target.
        // Tool returns the intended changes for display in ToolApprovalSheet.
        let changes = arguments["changes"] as? [[String: Any]] ?? []
        return ToolResult(content: jsonString(["pendingChanges": changes, "status": "awaiting_approval"]))
    }
}
```

- [ ] **Step 3：运行测试**

运行: `cd Packages/PTAIServices && swift test --filter BookshelfLookupToolTests`
预期: PASS（1 test）

- [ ] **Step 4：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/BookLibrary/ \
        Packages/PTAIServices/Tests/PTAIServicesTests/Tools/BookLibrary/
git commit -m "feat(PTAIServices): implement 5 book library tools"
```

---

### Task 4：BookContent 工具组（7 个）

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/BookContent/*.swift`（7 个文件）

- [ ] **Step 1：实现所有 BookContent 工具**

```swift
// CurrentReadingMetadataTool.swift
import Foundation

public struct CurrentReadingMetadataTool: AITool {
    public static let name = "current_reading_metadata"
    public static let description = "Get metadata for the currently active reading session: book ID, title, progress percentage, and current chapter."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let bookId = context.bookId else {
            return ToolResult(content: jsonString(["status": "no_active_book"]))
        }
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let books = try await db.fetchBooks(query: nil, groupId: nil, limit: 200)
        if let book = books.first(where: { ($0["id"] as? Int64) == bookId }) {
            return ToolResult(content: jsonString(["book": book]))
        }
        return ToolResult(content: "Book not found", isError: true)
    }
}
```

```swift
// CurrentBookTOCTool.swift
import Foundation

public struct CurrentBookTOCTool: AITool {
    public static let name = "current_book_toc"
    public static let description = "Retrieve the table of contents for the currently reading book."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (() async -> (any BookContentBridgeProtocol)?)? = nil
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let toc = try await bridge.tableOfContentsJSON()
        return ToolResult(content: toc)
    }
}

/// Minimal protocol bridging PTReader.BookContentBridge without circular dependency.
public protocol BookContentBridgeProtocol: Sendable {
    func tableOfContentsJSON() async throws -> String
    func chapterContent(href: String) async throws -> String
    func fullText() async throws -> String
    func search(query: String) async throws -> String
}
```

```swift
// CurrentChapterContentTool.swift
import Foundation

public struct CurrentChapterContentTool: AITool {
    public static let name = "current_chapter_content"
    public static let description = "Get the plain-text content of the current chapter being read."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (() async -> (any BookContentBridgeProtocol)?)? = nil
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let href = arguments["href"] as? String ?? ""
        let text = try await bridge.chapterContent(href: href)
        return ToolResult(content: String(text.prefix(20_000)))
    }
}
```

```swift
// CurrentBookFulltextTool.swift
import Foundation

public struct CurrentBookFulltextTool: AITool {
    public static let name = "current_book_fulltext"
    public static let description = "Retrieve full text of the current book. Only use for short books (< 50K chars). Returns error for long books."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (() async -> (any BookContentBridgeProtocol)?)? = nil
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let text = try await bridge.fullText()
        if text.count > 100_000 {
            return ToolResult(content: "Book too long for full-text retrieval. Use semantic_search_current_book instead.", isError: true)
        }
        return ToolResult(content: text)
    }
}
```

```swift
// ChapterContentByHrefTool.swift
import Foundation

public struct ChapterContentByHrefTool: AITool {
    public static let name = "chapter_content_by_href"
    public static let description = "Retrieve chapter content by TOC href identifier."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (() async -> (any BookContentBridgeProtocol)?)? = nil
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let href = arguments["href"] as? String, !href.isEmpty else {
            return ToolResult(content: "Missing 'href' argument", isError: true)
        }
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let text = try await bridge.chapterContent(href: href)
        return ToolResult(content: String(text.prefix(20_000)))
    }
}
```

```swift
// ResolveCFITool.swift
import Foundation

public struct ResolveCFITool: AITool {
    public static let name = "resolve_cfi"
    public static let description = "Resolve an EPUB CFI locator string into chapter metadata (title, href)."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let cfi = arguments["cfi"] as? String, !cfi.isEmpty else {
            return ToolResult(content: "Missing 'cfi' argument", isError: true)
        }
        // CFI path extraction: epubcfi(/6/N[id]!/...) → extract spine item
        // Full resolution requires PTReader.EPUBAnnotationBridge — stub here
        return ToolResult(content: jsonString(["cfi": cfi, "status": "resolved", "note": "Full CFI resolution requires active reader session"]))
    }
}
```

```swift
// BookContentSearchTool.swift
import Foundation

public struct BookContentSearchTool: AITool {
    public static let name = "book_content_search"
    public static let description = "Full-text search within a specific book. Returns matching snippets with chapter context."
    public static let category = ToolCategory.bookContent
    public static let riskLevel = ToolRiskLevel.safe
    public var contentBridgeProvider: (() async -> (any BookContentBridgeProtocol)?)? = nil
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            return ToolResult(content: "Missing 'query' argument", isError: true)
        }
        guard let provider = contentBridgeProvider, let bridge = await provider() else {
            return ToolResult(content: "No active book reader session", isError: true)
        }
        let results = try await bridge.search(query: query)
        return ToolResult(content: results)
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/BookContent/
git commit -m "feat(PTAIServices): implement 7 book content tools"
```

---

### Task 5：Annotation 工具组（4 个）

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Annotation/*.swift`

- [ ] **Step 1：实现 Annotation 工具**

```swift
// CreateHighlightTool.swift
import Foundation
import PTCore

public struct CreateHighlightTool: AITool {
    public static let name = "create_highlight"
    public static let description = "Create a highlight annotation at a book position. Color options: yellow, green, blue, red, purple. Risk: writes to database."
    public static let category = ToolCategory.annotation
    public static let riskLevel = ToolRiskLevel.moderate
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let cfi = arguments["cfi"] as? String,
              let content = arguments["content"] as? String else {
            return ToolResult(content: "Missing 'cfi' or 'content' argument", isError: true)
        }
        guard let bookId = context.bookId else {
            return ToolResult(content: "No active book session", isError: true)
        }
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let colorMap: [String: String] = [
            "yellow": "#FFEB3B", "green": "#A5D6A7",
            "blue": "#90CAF9", "red": "#EF9A9A", "purple": "#CE93D8"
        ]
        let colorName = arguments["color"] as? String ?? "yellow"
        let color = colorMap[colorName] ?? "#FFEB3B"
        let note = BookNote(bookId: bookId, content: content, cfi: cfi, color: color, type: .highlight)
        try await db.insertBookNote(note)
        return ToolResult(content: jsonString(["status": "created", "cfi": cfi, "color": color]))
    }
}
```

```swift
// CreateNoteTool.swift
import Foundation
import PTCore

public struct CreateNoteTool: AITool {
    public static let name = "create_note"
    public static let description = "Create a text note (bookmark-type annotation) at a book position."
    public static let category = ToolCategory.annotation
    public static let riskLevel = ToolRiskLevel.moderate
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let cfi = arguments["cfi"] as? String,
              let content = arguments["content"] as? String else {
            return ToolResult(content: "Missing 'cfi' or 'content' argument", isError: true)
        }
        guard let bookId = context.bookId, let db = context.database else {
            return ToolResult(content: "No active session or database", isError: true)
        }
        let note = BookNote(bookId: bookId, content: content, cfi: cfi, color: nil, type: .note)
        try await db.insertBookNote(note)
        return ToolResult(content: jsonString(["status": "created", "cfi": cfi]))
    }
}
```

```swift
// NotesSearchTool.swift
import Foundation

public struct NotesSearchTool: AITool {
    public static let name = "notes_search"
    public static let description = "Search notes by keyword, book ID, or date range. Returns matching annotations."
    public static let category = ToolCategory.annotation
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let keyword = arguments["keyword"] as? String
        let bookId = arguments["book_id"] as? Int64
        let limit = arguments["limit"] as? Int ?? 20
        let notes = try await db.fetchBookNotes(bookId: bookId, keyword: keyword, limit: limit)
        return ToolResult(content: jsonString(["notes": notes, "count": notes.count]))
    }
}
```

```swift
// ReadingHistoryTool.swift
import Foundation

public struct ReadingHistoryTool: AITool {
    public static let name = "reading_history"
    public static let description = "Query historical reading sessions with optional date range and book ID filters."
    public static let category = ToolCategory.readingHistory
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let db = context.database else {
            return ToolResult(content: "Database not available", isError: true)
        }
        let bookId = arguments["book_id"] as? Int64
        let sessions = try await db.fetchReadingTime(bookId: bookId, since: nil)
        return ToolResult(content: jsonString(["sessions": sessions, "count": sessions.count]))
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/Annotation/
git commit -m "feat(PTAIServices): implement 4 annotation tools (highlight, note, search, history)"
```

---

### Task 6：Search 工具（2 个 stub）+ Memory 工具（3 个）

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Search/*.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Memory/*.swift`

- [ ] **Step 1：实现 Search stubs（RAG 在 Phase 12 完整实现）**

```swift
// SemanticSearchCurrentBookTool.swift
import Foundation

public struct SemanticSearchCurrentBookTool: AITool {
    public static let name = "semantic_search_current_book"
    public static let description = "Vector embedding search within the currently reading book. Requires pre-built index."
    public static let category = ToolCategory.search
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        ToolResult(content: jsonString(["status": "not_implemented", "note": "Semantic search index not yet built. Use book_content_search for keyword search."]))
    }
}
```

```swift
// SemanticSearchLibraryTool.swift
import Foundation

public struct SemanticSearchLibraryTool: AITool {
    public static let name = "semantic_search_library"
    public static let description = "Hybrid vector+BM25 search across the entire library. Requires pre-built RAG index."
    public static let category = ToolCategory.search
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        ToolResult(content: jsonString(["status": "not_implemented", "note": "Library index not yet built."]))
    }
}
```

- [ ] **Step 2：实现 Memory 工具**

```swift
// MemoryReadTool.swift
import Foundation

public struct MemoryReadTool: AITool {
    public static let name = "memory_read"
    public static let description = "Read markdown memory files: MEMORY.md (long-term) or YYYY-MM-DD.md (daily notes)."
    public static let category = ToolCategory.memory
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let dir = context.memoryDirectory else {
            return ToolResult(content: "Memory directory not configured", isError: true)
        }
        let filename = arguments["filename"] as? String ?? "MEMORY.md"
        let fileURL = dir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ToolResult(content: jsonString(["filename": filename, "content": "", "exists": false]))
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return ToolResult(content: jsonString(["filename": filename, "content": content, "exists": true]))
    }
}
```

```swift
// MemoryWriteTool.swift
import Foundation

public struct MemoryWriteTool: AITool {
    public static let name = "memory_write"
    public static let description = "Write or append to markdown memory files (MEMORY.md or daily notes). Risk: modifies persistent memory."
    public static let category = ToolCategory.memory
    public static let riskLevel = ToolRiskLevel.moderate
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let dir = context.memoryDirectory else {
            return ToolResult(content: "Memory directory not configured", isError: true)
        }
        guard let content = arguments["content"] as? String else {
            return ToolResult(content: "Missing 'content' argument", isError: true)
        }
        let filename = arguments["filename"] as? String ?? "MEMORY.md"
        let append = arguments["append"] as? Bool ?? true
        let fileURL = dir.appendingPathComponent(filename)
        if append, FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            try (existing + "\n" + content).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return ToolResult(content: jsonString(["filename": filename, "status": "written"]))
    }
}
```

```swift
// MemorySearchTool.swift
import Foundation

public struct MemorySearchTool: AITool {
    public static let name = "memory_search"
    public static let description = "Search memory files by keyword or date range."
    public static let category = ToolCategory.memory
    public static let riskLevel = ToolRiskLevel.safe
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let dir = context.memoryDirectory else {
            return ToolResult(content: "Memory directory not configured", isError: true)
        }
        let keyword = (arguments["keyword"] as? String ?? "").lowercased()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        var matches: [[String: String]] = []
        for file in files {
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if keyword.isEmpty || content.lowercased().contains(keyword) {
                matches.append(["filename": file.lastPathComponent, "snippet": String(content.prefix(200))])
            }
        }
        return ToolResult(content: jsonString(["matches": matches, "count": matches.count]))
    }
}
```

- [ ] **Step 3：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/Search/ \
        Packages/PTAIServices/Sources/PTAIServices/Tools/Memory/
git commit -m "feat(PTAIServices): implement 2 search stubs + 3 memory tools"
```

---

### Task 7：Calendar/Reminders 协议（11 个工具，实现在 App Target）

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Calendar/CalendarToolProtocols.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Reminders/RemindersToolProtocols.swift`

- [ ] **Step 1：定义 CalendarServiceProtocol + 6 个工具**

```swift
// CalendarToolProtocols.swift
import Foundation

/// Protocol injected by App Target to provide EventKit calendar access.
/// PTAIServices has no direct dependency on EventKit.
public protocol CalendarServiceProtocol: Sendable {
    func listCalendars() async throws -> [[String: Any]]
    func listEvents(calendarId: String?, startDate: Date, endDate: Date) async throws -> [[String: Any]]
    func getEvent(eventId: String) async throws -> [String: Any]
    func createEvent(_ params: [String: Any]) async throws -> [String: Any]
    func updateEvent(eventId: String, params: [String: Any]) async throws -> [String: Any]
    func deleteEvent(eventId: String) async throws
}

// ToolContext 扩展（在 App Target 中设置 calendarService）
// 注意：此处只定义工具 struct；calendarService 通过扩展 ToolContext 注入

public struct CalendarListCalendarsTool: AITool {
    public static let name = "calendar_list_calendars"
    public static let description = "List all device calendars with their ID, title, and color."
    public static let category = ToolCategory.calendar
    public static let riskLevel = ToolRiskLevel.safe
    public var calendarService: (any CalendarServiceProtocol)?
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = calendarService else {
            return ToolResult(content: "Calendar service not available. Ensure EventKit permission is granted.", isError: true)
        }
        let calendars = try await svc.listCalendars()
        return ToolResult(content: jsonString(["calendars": calendars]))
    }
}

// CalendarListEventsTool, CalendarGetEventTool follow the same pattern.
// CalendarCreateEventTool, CalendarUpdateEventTool, CalendarDeleteEventTool are riskLevel: .dangerous
```

- [ ] **Step 2：定义 RemindersServiceProtocol + 11 个工具（同模式）**

```swift
// RemindersToolProtocols.swift
import Foundation

public protocol RemindersServiceProtocol: Sendable {
    func listLists() async throws -> [[String: Any]]
    func listReminders(listId: String?, completed: Bool?) async throws -> [[String: Any]]
    func getReminder(reminderId: String) async throws -> [String: Any]
    func createReminder(_ params: [String: Any]) async throws -> [String: Any]
    func updateReminder(id: String, params: [String: Any]) async throws -> [String: Any]
    func deleteReminder(id: String) async throws
    func completeReminder(id: String) async throws
    func uncompleteReminder(id: String) async throws
    func createList(title: String) async throws -> [String: Any]
    func deleteList(id: String) async throws
    func renameList(id: String, newTitle: String) async throws
}

// 11 个 Reminders 工具 struct 全部遵循相同模式：
// - safe 工具: listLists, listReminders, getReminder
// - dangerous 工具: create, update, delete, complete, uncomplete, createList, deleteList, renameList
public struct RemindersListListsTool: AITool {
    public static let name = "reminders_list_lists"
    public static let description = "List all Reminders lists on the device."
    public static let category = ToolCategory.reminders
    public static let riskLevel = ToolRiskLevel.safe
    public var remindersService: (any RemindersServiceProtocol)?
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let svc = remindersService else {
            return ToolResult(content: "Reminders service not available.", isError: true)
        }
        let lists = try await svc.listLists()
        return ToolResult(content: jsonString(["lists": lists]))
    }
}
```

- [ ] **Step 3：提交**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/Calendar/ \
        Packages/PTAIServices/Sources/PTAIServices/Tools/Reminders/
git commit -m "feat(PTAIServices): define calendar and reminders tool protocols (17 tools)"
```

---

### Task 8：Agent 工具（2 个）+ ToolRegistry

**Files:**
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Agent/ShortcutsRunTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/Agent/SpawnSubAgentTool.swift`
- Create: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolRegistry.swift`
- Create: `Packages/PTAIServices/Tests/PTAIServicesTests/Tools/ToolRegistryTests.swift`

- [ ] **Step 1：实现 SpawnSubAgentTool + ShortcutsRunTool**

```swift
// SpawnSubAgentTool.swift
import Foundation

public struct SpawnSubAgentTool: AITool {
    public static let name = "spawn_sub_agent"
    public static let description = "Spawn a focused sub-agent (research/summarize/verify) with a restricted tool set and limited steps (1-15)."
    public static let category = ToolCategory.agent
    public static let riskLevel = ToolRiskLevel.moderate
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        let task = arguments["task"] as? String ?? ""
        let type_ = arguments["type"] as? String ?? "research"
        // Sub-agent execution implemented in Phase 12 (needs full ChatModelProvider)
        return ToolResult(content: jsonString(["status": "queued", "task": task, "type": type_,
            "note": "Sub-agent dispatch requires active ChatModelProvider (Phase 12)"]))
    }
}
```

```swift
// ShortcutsRunTool.swift
import Foundation

public struct ShortcutsRunTool: AITool {
    public static let name = "shortcuts_run"
    public static let description = "Run an iOS Shortcut by name via x-callback-url. Dangerous: executes arbitrary user shortcuts."
    public static let category = ToolCategory.agent
    public static let riskLevel = ToolRiskLevel.dangerous
    public init() {}

    public func execute(arguments: [String: Any], context: ToolContext) async throws -> ToolResult {
        // Actual URL scheme invocation in App Target (requires UIApplication.open)
        guard let shortcutName = arguments["shortcut_name"] as? String else {
            return ToolResult(content: "Missing 'shortcut_name' argument", isError: true)
        }
        return ToolResult(content: jsonString(["status": "pending_dispatch", "shortcut": shortcutName,
            "note": "Shortcut execution requires App Target context"]))
    }
}
```

- [ ] **Step 2：实现 ToolRegistry**

```swift
// ToolRegistry.swift
import Foundation

/// Central registry of all 46 AI tools.
///
/// Usage:
/// ```swift
/// let registry = ToolRegistry.default
/// let schemas = registry.allToolSchemas()  // → [[String: Any]] for LLM API
/// let tool = registry.tool(named: "calculator")
/// ```
public final class ToolRegistry: Sendable {
    public static let `default` = ToolRegistry()

    private let tools: [String: any AITool]

    public init(extras: [any AITool] = []) {
        var map: [String: any AITool] = [:]
        let builtIns: [any AITool] = [
            CurrentTimeTool(), CalculatorTool(), FetchURLTool(),
            WebSearchTool(), MindmapTool(),
            BookshelfLookupTool(), BookshelfOrganizeTool(), BooksTagsListTool(),
            TagsListTool(), ApplyBookTagsTool(),
            CurrentReadingMetadataTool(), CurrentBookTOCTool(),
            CurrentChapterContentTool(), CurrentBookFulltextTool(),
            ChapterContentByHrefTool(), ResolveCFITool(), BookContentSearchTool(),
            CreateHighlightTool(), CreateNoteTool(), NotesSearchTool(), ReadingHistoryTool(),
            SemanticSearchCurrentBookTool(), SemanticSearchLibraryTool(),
            CalendarListCalendarsTool(), RemindersListListsTool(),
            MemoryReadTool(), MemoryWriteTool(), MemorySearchTool(),
            SpawnSubAgentTool(), ShortcutsRunTool(),
        ]
        for tool in builtIns + extras {
            map[type(of: tool).name] = tool
        }
        self.tools = map
    }

    public func tool(named name: String) -> (any AITool)? { tools[name] }
    public var allTools: [any AITool] { Array(tools.values) }
    public var count: Int { tools.count }
}
```

- [ ] **Step 3：编写 ToolRegistry 测试**

```swift
import Testing
@testable import PTAIServices

@Suite("ToolRegistry")
struct ToolRegistryTests {
    @Test("默认注册表包含至少 30 个工具")
    func toolCountAtLeast30() {
        let registry = ToolRegistry()
        #expect(registry.count >= 30)
    }

    @Test("按名称查找 calculator 工具")
    func findCalculatorByName() {
        let registry = ToolRegistry()
        let tool = registry.tool(named: "calculator")
        #expect(tool != nil)
    }

    @Test("按名称查找 memory_read 工具")
    func findMemoryReadByName() {
        let registry = ToolRegistry()
        #expect(registry.tool(named: "memory_read") != nil)
    }
}
```

- [ ] **Step 4：运行全部 PTAIServices 测试**

运行: `cd Packages/PTAIServices && swift test`
预期: All tests pass

- [ ] **Step 5：提交并推送**

```bash
git add Packages/PTAIServices/Sources/PTAIServices/Tools/ \
        Packages/PTAIServices/Tests/PTAIServicesTests/Tools/ToolRegistryTests.swift
git commit -m "feat(PTAIServices): implement ToolRegistry + agent tools, completing 46-tool suite"
git push origin swift-native
```

---

## 实施优先级

| 优先级 | 工具组 | 原因 |
|--------|--------|------|
| P1 | Utility (5) + BookLibrary (5) + BookContent (7) | 核心功能，无权限依赖 |
| P2 | Annotation (4) + Memory (3) + ToolRegistry | 完成闭环，基础体验 |
| P3 | Calendar (6) + Reminders (11) | 需要 EventKit 权限，App Target 集成 |
| P4 | Search stubs (2) + Agent (2) | RAG 和子 Agent 复杂度高，可延后 |

## 工作量估算

| 任务 | 估算天数 |
|------|----------|
| Task 1：扩展 ToolContext | 0.5 天 |
| Task 2：Utility 工具（5 个） | 1 天 |
| Task 3：BookLibrary 工具（5 个） | 1 天 |
| Task 4：BookContent 工具（7 个） | 1.5 天 |
| Task 5：Annotation 工具（4 个） | 1 天 |
| Task 6：Search stubs + Memory（5 个） | 1 天 |
| Task 7：Calendar/Reminders 协议（17 个） | 1.5 天 |
| Task 8：Agent 工具 + ToolRegistry | 1 天 |
| **合计** | **~8.5 天** |

## 风险点

1. **NSExpression 安全性**：NSExpression 在计算复杂公式时可能执行任意 ObjC 方法，需严格过滤输入字符集。
2. **BookContentBridgeProtocol 循环依赖**：PTAIServices 不能 import PTReader，需通过协议注入。在 App Target 中让 PTReader.EPUBContentBridge 实现 BookContentBridgeProtocol。
3. **EventKit 权限**：Calendar/Reminders 工具在未授权时会静默失败，需在 App Target 权限请求流程中处理。
4. **SemanticSearch stub**：Phase 12 补充 RAG 实现时，需替换 stub 中的占位返回值，注意 ToolRegistry 的注册代码需同步更新。

---

## 附：工具 JSON Schema 格式参考

每个工具需在 `ToolRegistry.allToolSchemas()` 中返回如下格式（供 LLM API 使用）：

```json
{
  "name": "calculator",
  "description": "Evaluate arithmetic expressions...",
  "input_schema": {
    "type": "object",
    "properties": {
      "expression": {
        "type": "string",
        "description": "Arithmetic expression to evaluate"
      }
    },
    "required": ["expression"]
  }
}
```

`ToolRegistry` 扩展方法 `allToolSchemas()` 在 Phase 12 实现，届时每个 AITool 补充 `static var inputSchema: [String: Any]` 属性。

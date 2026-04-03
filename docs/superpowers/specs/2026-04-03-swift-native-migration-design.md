# PaperTok Reader — Flutter to Swift Native Migration Design

**Date:** 2026-04-03
**Status:** Approved
**Scope:** Full 1:1 feature migration + Apple-style UI redesign + macOS support

---

## 1. Overview

Migrate the entire PaperTok Reader Flutter application (551+ Dart files, 7.8 MB source) to a native Swift iOS/macOS app. Every feature is replicated 1:1, with the UI redesigned to follow Apple Human Interface Guidelines using SwiftUI.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI + UIKit hybrid | SwiftUI for all UI, UIKit bridged for EPUB/PDF rendering |
| EPUB Engine | Readium Swift SDK | Native Swift, community-maintained, supports macOS |
| Data Persistence | GRDB.swift (SQLite) | Direct schema reuse, RAG vector queries, best performance |
| AI/LLM Layer | Custom URLSession + SSE | Full control over 76 tools, non-standard providers, streaming |
| macOS Support | SwiftUI Multiplatform App | Shared logic + UI, `#if os()` for platform differences |
| State Management | @Observable (Observation framework) | iOS 17+ native, replaces Riverpod |
| Repository Strategy | Orphan branch `swift-native` in same repo | Clean start, easy Flutter reference |
| Architecture | Modular Swift Packages (6 packages) | Incremental compilation, testable, clear dependencies |
| Minimum Target | iOS 17.0 / macOS 14.0 | Required for @Observable, SwiftData coexistence, modern SwiftUI |
| Localization | Xcode String Catalogs (.xcstrings) | 14 languages, compile-time safe, Xcode native tooling |

---

## 2. Project Structure

```
PaperTokReader/
├── PaperTokReader.xcworkspace
├── App/                                    # Multiplatform App Target
│   ├── PaperTokReaderApp.swift            # @main entry
│   ├── AppDelegate.swift                  # UIKit lifecycle (iOS)
│   ├── Info.plist
│   ├── Entitlements/
│   │   ├── iOS.entitlements               # App Groups, Keychain
│   │   └── macOS.entitlements             # App Groups, Keychain, Sandbox
│   ├── iOS/                               # iOS-only code
│   │   └── SceneDelegate.swift
│   ├── macOS/                             # macOS-only code
│   │   └── MacCommands.swift              # Menu bar commands
│   ├── Resources/
│   │   ├── Assets.xcassets                # App icons, colors, images
│   │   ├── Fonts/                         # Source Han Serif SC
│   │   ├── Localizable.xcstrings          # 14 languages
│   │   └── BackgroundImages/              # Reading backgrounds
│   └── Extensions/
│       ├── ShareExtension/                # iOS/macOS Share Extension target
│       │   ├── ShareViewController.swift
│       │   ├── Info.plist
│       │   └── shareExtension.entitlements
│       └── AppIntents/                    # Shortcuts intents
│           └── SendMessageIntent.swift
├── Packages/
│   ├── PTCore/
│   │   ├── Package.swift
│   │   ├── Sources/PTCore/
│   │   │   ├── Models/                    # Book, BookNote, Tag, etc.
│   │   │   ├── Database/                  # GRDB setup, migrations, DAOs
│   │   │   ├── Enums/                     # All enum types
│   │   │   ├── Config/                    # AppConfig, UserDefaults wrappers
│   │   │   └── Utils/                     # Extensions, helpers
│   │   └── Tests/PTCoreTests/
│   ├── PTNetworking/
│   │   ├── Package.swift
│   │   ├── Sources/PTNetworking/
│   │   │   ├── HTTP/                      # NetworkClient, Endpoint
│   │   │   ├── SSE/                       # SSEParser, SSEEvent
│   │   │   ├── WebDAV/                    # WebDAVClient, sync logic
│   │   │   └── PaperTok/                  # PaperTok REST API client
│   │   └── Tests/PTNetworkingTests/
│   ├── PTReader/
│   │   ├── Package.swift
│   │   ├── Sources/PTReader/
│   │   │   ├── EPUB/                      # Readium EPUB integration
│   │   │   ├── PDF/                       # Readium PDF integration
│   │   │   ├── Common/                    # ReaderEngine, LocatorService
│   │   │   ├── Preferences/              # ReadingStyle, ReadingTheme
│   │   │   └── TTS/                       # AVSpeechSynthesizer wrapper
│   │   └── Tests/PTReaderTests/
│   ├── PTAIServices/
│   │   ├── Package.swift
│   │   ├── Sources/PTAIServices/
│   │   │   ├── Providers/                 # OpenAI, Anthropic, Gemini, etc.
│   │   │   ├── Chat/                      # ChatService, ConversationTree
│   │   │   ├── Tools/                     # 76 AI tools + orchestrator
│   │   │   ├── RAG/                       # Embeddings, vector search, indexing
│   │   │   ├── Memory/                    # MemoryStore, digest, search
│   │   │   ├── Translation/              # AI/DeepL/Google/Microsoft translators
│   │   │   ├── Skills/                    # Skill registry, built-in skills
│   │   │   ├── SubAgent/                  # Sub-agent runner
│   │   │   └── MCP/                       # MCP client, JSON-RPC, tool registry
│   │   └── Tests/PTAIServicesTests/
│   ├── PTUI/
│   │   ├── Package.swift
│   │   ├── Sources/PTUI/
│   │   │   ├── Components/               # Buttons, cards, chips, dialogs
│   │   │   ├── Markdown/                 # Markdown renderer (AI responses)
│   │   │   ├── Charts/                   # Reading stats charts
│   │   │   ├── Theme/                    # Color scheme, typography
│   │   │   └── Modifiers/               # Custom ViewModifiers
│   │   └── Tests/PTUITests/
│   └── PTFeatures/
│       ├── Package.swift
│       ├── Sources/PTFeatures/
│       │   ├── Papers/                    # PaperTok feed, detail, import
│       │   ├── Bookshelf/                # Library, groups, import, organize
│       │   ├── Reader/                    # Reading page, AI panel, settings
│       │   ├── Notes/                     # Notes list, search, export
│       │   ├── Statistics/               # Dashboard, heatmap, trends
│       │   ├── AIChat/                    # Chat UI, history, provider switch
│       │   ├── Settings/                  # All settings subpages
│       │   ├── Search/                    # Full-text search
│       │   ├── Onboarding/               # Introduction screens
│       │   ├── Share/                     # Share handling, routing
│       │   └── Navigation/               # Tab/sidebar routing
│       └── Tests/PTFeaturesTests/
└── vendor/                                # Forked dependencies if needed
```

---

## 3. Package Dependency Graph

```
App
 └── PTFeatures
      ├── PTUI ──────────→ PTCore
      ├── PTAIServices ──→ PTNetworking ──→ PTCore
      ├── PTReader ──────→ PTCore
      └── (direct) ──────→ PTCore
```

**Dependency rules:**
- PTCore: GRDB.swift only (zero other external deps)
- PTNetworking: PTCore only
- PTReader: PTCore + ReadiumOPDS + ReadiumShared + ReadiumNavigator + ReadiumStreamer
- PTAIServices: PTCore + PTNetworking
- PTUI: PTCore only
- PTFeatures: all above packages
- App: PTFeatures + platform frameworks (EventKit, AppIntents, etc.)

---

## 4. PTCore — Models, Database, Configuration

### 4.1 Database (GRDB.swift)

Schema version 7, identical to Flutter SQLite schema for zero-cost data migration:

**Tables:**
| Table | Primary Key | Description |
|-------|-------------|-------------|
| tb_books | id (auto) | Book metadata, file path, progress, cover |
| tb_notes | id (auto) | Highlights, bookmarks, notes with CFI position |
| tb_themes | id (auto) | Reading themes (background/text colors) |
| tb_styles | id (auto) | Reading styles (font, margins, spacing) |
| tb_reading_time | id (auto) | Daily reading duration records |
| tb_tags | id (auto) | Book tags/categories |
| tb_groups | id (auto) | Bookshelf folder hierarchy (parent_id FK) |

Additional tables for AI:
| Table | Description |
|-------|-------------|
| ai_conversations | Conversation tree v2 (JSON blob per conversation) |
| ai_embeddings | Vector embeddings for RAG (book_id, chunk_id, vector BLOB) |
| ai_memory_index | Memory search index (text + embedding) |

**Migration strategy:**
- DatabaseMigrator with numbered migrations v1–v7
- Future migrations increment from v8
- Users upgrading from Flutter: copy `anx_reader.db` to Swift app container, run pending migrations

### 4.2 Models

All models are Swift structs conforming to `Codable`, `FetchableRecord`, `PersistableRecord`, `Identifiable`, `Sendable`.

**Core models (mapped from 44 Dart models):**
- `Book` — metadata, file path, reading progress
- `BookNote` — annotation with CFI, color, type (highlight/bookmark/note)
- `ReadingTime` — daily duration tracking
- `Tag`, `BookTag` — categorization
- `TbGroup` — bookshelf folder hierarchy
- `ReadTheme` — visual theme (colors)
- `BookStyle` — per-book reading preferences (font, margins, spacing)
- `AiConversation` — conversation tree v2 with branching
- `AiMessage` — single message with role, content, tool calls, thinking
- `AiProviderConfig` — provider settings (endpoint, API key, models)
- `AiToolApproval` — per-tool approval policy
- `AttachmentItem` — multimodal attachment (image/text, base64/path)
- `SyncState` — WebDAV sync status
- `PaperTokPaper` — academic paper metadata
- `ChapterSplitRule` — custom chapter boundary regex
- `SharePromptPreset` — share routing preset

### 4.3 Configuration

```swift
// App-wide configuration via AppStorage + App Group UserDefaults
enum AppConfig {
    static let suiteName = "group.ai.papertok.paperreader"
    static let defaults = UserDefaults(suiteName: suiteName)!
    
    // AI settings
    @AppStorage("ai_provider_id", store: defaults) static var aiProviderId = "openai"
    @AppStorage("ai_model_id", store: defaults) static var aiModelId = "gpt-4o"
    @AppStorage("ai_system_prompt", store: defaults) static var aiSystemPrompt = ""
    @AppStorage("ai_thinking_level", store: defaults) static var aiThinkingLevel = 0
    
    // Reading settings
    @AppStorage("default_font_size", store: defaults) static var defaultFontSize = 18.0
    @AppStorage("page_turn_mode", store: defaults) static var pageTurnMode = "swipe"
    
    // Sync settings
    @AppStorage("webdav_url", store: defaults) static var webdavURL = ""
    @AppStorage("webdav_username", store: defaults) static var webdavUsername = ""
    // API keys stored in Keychain, not UserDefaults
}
```

### 4.4 Keychain

API keys stored in iOS/macOS Keychain (replaces Flutter's encrypted SharedPreferences):
```swift
struct KeychainService {
    static func save(key: String, value: String) throws
    static func load(key: String) throws -> String?
    static func delete(key: String) throws
}
```

### 4.5 State Management

Replace Riverpod with `@Observable` (Observation framework, iOS 17+):

| Flutter (Riverpod) | Swift (@Observable) |
|---------------------|---------------------|
| `StateNotifierProvider` | `@Observable class ViewModel` |
| `FutureProvider` | `async func` in ViewModel |
| `StreamProvider` | `AsyncSequence` / `AsyncStream` |
| `ref.watch()` | SwiftUI auto-tracks `@Observable` properties |
| `ref.read()` | Direct property access |
| `ProviderScope` | `@Environment` + `.environment()` modifier |

Dependency injection via SwiftUI Environment:
```swift
@Observable final class BookshelfViewModel { ... }

// In App
ContentView()
    .environment(BookshelfViewModel(db: appDatabase))
    .environment(AIChatViewModel(aiService: aiService))
```

---

## 5. PTNetworking — HTTP, SSE, WebDAV

### 5.1 Network Client

```swift
// Replaces Dio
actor NetworkClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    func requestRaw(_ endpoint: Endpoint) async throws -> Data
    func upload(_ endpoint: Endpoint, data: Data) async throws
    func download(_ endpoint: Endpoint, to: URL) async throws
}

struct Endpoint {
    let method: HTTPMethod
    let baseURL: URL
    let path: String
    let headers: [String: String]
    let queryItems: [URLQueryItem]?
    let body: Encodable?
    let timeout: TimeInterval
}
```

### 5.2 SSE Stream Parser

```swift
// Server-Sent Events parser for LLM streaming
struct SSEEvent {
    let event: String?    // event type
    let data: String      // payload (JSON)
    let id: String?
    let retry: Int?
}

struct SSEParser {
    /// Parse URLSession.AsyncBytes into SSE events
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error>
}
```

Features:
- 15-second heartbeat detection (prevent proxy disconnection)
- JSON repair layer for truncated LLM output
- Automatic reconnection with last-event-id

### 5.3 WebDAV Client

```swift
actor WebDAVClient {
    func propfind(path: String) async throws -> [RemoteFile]
    func get(path: String) async throws -> Data
    func put(path: String, data: Data) async throws
    func delete(path: String) async throws
    func mkcol(path: String) async throws
    
    // Authentication
    enum Auth {
        case basic(user: String, password: String)
        case digest(user: String, password: String, realm: String, nonce: String)
    }
}
```

Sync strategy:
- AI settings snapshot: whole-file newer-wins (timestamp comparison)
- Exclude `api_key` from sync payload
- Sync triggers: app background/foreground, manual

### 5.4 PaperTok API Client

```swift
struct PaperTokAPI {
    let client: NetworkClient
    let baseURL = URL(string: "https://papertok.ai")!
    
    func fetchRandomPapers(language: String, count: Int) async throws -> [Paper]
    func fetchPaperDetail(id: String) async throws -> Paper
    func fetchPapersByDate(date: Date, language: String) async throws -> [Paper]
}
```

---

## 6. PTReader — Readium EPUB/PDF Engine

### 6.1 Dependencies

- `ReadiumShared` — core models (Publication, Locator, Link)
- `ReadiumStreamer` — publication parsing (EPUB/PDF)
- `ReadiumNavigator` — rendering (EPUBNavigatorViewController, PDFNavigatorViewController)
- `ReadiumOPDS` — optional, for OPDS catalog support

### 6.2 Reader Engine

```swift
@Observable
final class ReaderEngine {
    let publication: Publication
    var currentLocator: Locator
    var readingProgress: Double
    var tableOfContents: [Link]
    
    // Navigator (UIKit, bridged to SwiftUI)
    let epubNavigator: EPUBNavigatorViewController
    // or
    let pdfNavigator: PDFNavigatorViewController
}
```

### 6.3 Feature Mapping

| Feature | Readium API |
|---------|-------------|
| Open EPUB | Streamer.open(asset:) → Publication |
| Open PDF | Streamer.open(asset:) → Publication |
| Page navigation | Navigator.go(to: Locator) |
| Current position | Navigator.currentLocation → Locator |
| Progress | Locator.locations.totalProgression |
| TOC | Publication.tableOfContents |
| Full-text search | Publication.search(query:) → SearchIterator |
| Text selection | Navigator.delegate (selection callback) |
| Highlights | DecorationStyle + Navigator.apply(decorations:) |
| Bookmarks | Save Locator to database |
| Custom CSS | EPUBPreferences (fontSize, fontFamily, theme, margins, etc.) |
| Images | Navigator delegate for image tap events |
| CFI support | Locator includes EPUB CFI in locations |
| Spread/scroll mode | EPUBPreferences.scroll, .spread |

### 6.4 SwiftUI Bridge

```swift
struct EPUBReaderView: UIViewControllerRepresentable {
    let engine: ReaderEngine
    
    func makeUIViewController(context: Context) -> EPUBNavigatorViewController
    func updateUIViewController(_ vc: EPUBNavigatorViewController, context: Context)
}

struct PDFReaderView: UIViewControllerRepresentable {
    let engine: ReaderEngine
    
    func makeUIViewController(context: Context) -> PDFNavigatorViewController
    func updateUIViewController(_ vc: PDFNavigatorViewController, context: Context)
}
```

### 6.5 TTS (Text-to-Speech)

Replace Flutter's `flutter_tts` + `audio_service` with native:
```swift
@Observable final class TTSService {
    private let synthesizer = AVSpeechSynthesizer()
    
    func speak(text: String, language: String, rate: Float)
    func pause()
    func resume()
    func stop()
    
    // NowPlayingInfo for Lock Screen / Control Center
    private func updateNowPlaying()
}
```

---

## 7. PTAIServices — LLM, Tools, RAG, Memory, Translation

### 7.1 Unified Chat Model Protocol

```swift
protocol ChatModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedCapabilities: Set<ModelCapability> { get }
    
    func complete(_ request: ChatRequest) async throws -> ChatResponse
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamChunk, Error>
}

enum ModelCapability {
    case chat, vision, toolCalling, thinking, streaming
}

struct ChatRequest {
    let messages: [ChatMessage]
    let model: String
    let temperature: Double?
    let maxTokens: Int?
    let tools: [ToolDefinition]?
    let thinkingLevel: ThinkingLevel?
    let responseFormat: ResponseFormat?
}

struct ChatStreamChunk {
    let delta: ContentDelta          // text, toolCall, thinking
    let finishReason: FinishReason?
    let usage: TokenUsage?
}
```

### 7.2 Provider Implementations

| Provider | Key Features |
|----------|-------------|
| `OpenAIProvider` | GPT-4o/4, tool calling, vision, streaming |
| `AnthropicProvider` | Claude, extended thinking (thinking blocks), streaming |
| `GeminiProvider` | Gemini, includeThoughts toggle, streaming |
| `VolcengineArkProvider` | Volcengine Ark, multimodal, base64 images |
| `OpenAIResponsesProvider` | Responses API, previous_response_id, reasoning_summary |
| `CustomOpenAICompatibleProvider` | Any OpenAI-compatible endpoint |

### 7.3 Tool System (76 Tools)

```swift
protocol AITool: Sendable {
    static var name: String { get }
    static var description: String { get }
    static var parameterSchema: JSONSchema { get }
    static var category: ToolCategory { get }
    static var concurrencyPartition: String { get }  // for safe concurrent execution
    
    func execute(arguments: JSON, context: ToolContext) async throws -> ToolResult
}

enum ToolCategory {
    case bookLibrary       // bookshelf_lookup, books_tags_list, etc.
    case bookContent       // current_book_fulltext, chapter_content, etc.
    case annotation        // create_highlight, create_note
    case search            // semantic_search_current_book, semantic_search_library, book_content_search
    case readingHistory    // current_reading_metadata, reading_history
    case calendar          // calendar_list/get/create/update/delete
    case reminders         // reminders_list/get/create/update/delete/complete
    case utility           // current_time, calculator, fetch_url, web_search
    case agent             // spawn_sub_agent, shortcuts_run
    case memory            // memory_read, memory_write, memory_search
    case mindmap           // mindmap generation
}
```

**Tool Orchestrator:**
```swift
actor ToolOrchestrator {
    let approvalDelegate: ToolApprovalDelegate
    let annotationLedger: AnnotationLedger       // prevent duplicate highlights
    
    func execute(calls: [ToolCall], context: ToolContext) async throws -> [ToolResult] {
        // 1. Check approval policy per tool
        // 2. Partition by concurrency safety
        // 3. Execute safe tools concurrently, unsafe ones serially
        // 4. Return results with timing
    }
}
```

**Scene-aware filtering:**
- Reading scene: ~50% fewer tools (exclude calendar, reminders, web_search unless relevant)
- Chat scene: full tool set

### 7.4 Conversation Tree v2

```swift
struct ConversationTree: Codable {
    var rootId: String
    var nodes: [String: ConversationNode]     // id → node
    
    struct ConversationNode: Codable {
        let id: String
        let role: ChatRole
        let content: MessageContent
        let parentId: String?
        var childIds: [String]                 // branching: multiple children
        var activeChildIndex: Int              // which branch is active
        let metadata: NodeMetadata             // timestamp, model, tokens
    }
}
```

Features:
- Per-turn assistant variants (switch between regenerations)
- Rollback to old variant without losing subsequent turns
- Edit any user turn and branch from there
- Persistent across app restart

### 7.5 RAG (Retrieval-Augmented Generation)

```swift
struct EmbeddingService {
    let provider: ChatModelProvider           // reuse LLM provider for embeddings
    func embed(texts: [String]) async throws -> [[Float]]
}

struct SemanticSearchService {
    let db: AppDatabase
    let embedder: EmbeddingService
    
    func searchCurrentBook(query: String, bookId: Int64, topK: Int) async throws -> [SearchResult]
    func searchLibrary(query: String, topK: Int) async throws -> [SearchResult]
}

// Indexing queue
actor LibraryIndexQueue {
    func enqueue(bookId: Int64)
    func pause()
    func resume()
    func cancel()
    var progress: AsyncStream<IndexProgress> { get }
}
```

**Text chunking strategies:**
- Fixed-size with overlap
- Paragraph-based
- AI-assisted semantic chunking

**Search modes:**
- Vector similarity (cosine)
- FTS5 full-text search (BM25)
- Hybrid (FTS + vector + optional MMR reranking)

### 7.6 Memory System

```swift
struct MemoryStore {
    let basePath: URL                          // App documents/memory/
    
    // Files
    var dailyPath: URL { basePath/"daily.md" }
    var longTermPath: URL { basePath/"MEMORY.md" }
    var reviewInboxPath: URL { basePath/"review_inbox/" }
    
    func write(_ entry: MemoryEntry) async throws
    func read() async throws -> [MemoryEntry]
    func search(_ query: String) async throws -> [MemoryEntry]
}

struct MemoryWorkflowService {
    let store: MemoryStore
    let searchService: MemorySearchService
    let digestService: SessionDigestService
    let policy: MemoryWorkflowPolicy
    
    func processSessionEnd(messages: [ChatMessage]) async throws
    func candidateRanking(_ candidates: [MemoryCandidate]) -> [MemoryCandidate]
}
```

### 7.7 Translation Engine

```swift
protocol TranslationProvider: Sendable {
    func translate(text: String, from: Language, to: Language) async throws -> String
    func translateBatch(texts: [String], from: Language, to: Language) async throws -> [String]
}

// Implementations
struct AITranslator: TranslationProvider { ... }         // Uses ChatModelProvider
struct DeepLTranslator: TranslationProvider { ... }
struct GoogleTranslator: TranslationProvider { ... }
struct MicrosoftTranslator: TranslationProvider { ... }

// Full-text translation with per-book cache
actor FulltextTranslationEngine {
    func translateBook(bookId: Int64, provider: TranslationProvider) -> AsyncStream<TranslationProgress>
    func getCachedTranslation(bookId: Int64, segment: String) -> String?
    func clearCache(bookId: Int64) async
}
```

### 7.8 MCP (Model Context Protocol)

```swift
actor MCPClient {
    func connect(url: URL, transport: MCPTransport) async throws
    func listTools() async throws -> [MCPToolDefinition]
    func callTool(name: String, arguments: JSON) async throws -> MCPToolResult
    func disconnect() async
}

enum MCPTransport {
    case sse(url: URL)                         // Legacy HTTP+SSE
    case streamableHTTP(url: URL)              // Streamable HTTP
}
```

### 7.9 Sub-Agent System

```swift
struct SubAgentRunner {
    let chatService: ChatService
    
    func spawn(
        task: String,
        restrictedTools: Set<String>,          // subset of available tools
        parentContext: ChatContext
    ) -> AsyncThrowingStream<SubAgentEvent, Error>
}
```

### 7.10 KAIROS Proactive Assistant

```swift
@Observable final class KairosService {
    var dwellTime: TimeInterval = 0
    var suggestions: [KairosSuggestion] = []
    
    func monitorReading(locator: Locator) async
    func detectChapterCompletion() -> Bool
    func surfaceSuggestion(_ suggestion: KairosSuggestion)
}
```

### 7.11 Token/Cost Tracking

```swift
struct UsageTracker {
    func record(model: String, usage: TokenUsage)
    func totalCost(since: Date) -> Decimal
    func usageHistory() -> [UsageRecord]
    
    // Built-in pricing tables for 5 model families
    static let pricing: [String: ModelPricing]
}
```

---

## 8. PTUI — Shared SwiftUI Components

### 8.1 Design System

**Apple HIG principles:**
- SF Symbols for all icons (replaces icons_plus)
- System colors + custom AccentColor
- Dynamic Type support
- Dark Mode automatic via system
- Materials (`.ultraThinMaterial`, `.regularMaterial`) for glassmorphism
- Haptic feedback via `UIFeedbackGenerator` / `NSHapticFeedbackManager`

**Typography:**
```swift
enum PTTypography {
    static let title = Font.title
    static let headline = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    // Chinese: Source Han Serif SC for reading content
    static func readingFont(size: CGFloat) -> Font
}
```

**Color scheme:**
```swift
enum PTColors {
    static let accent = Color.accentColor                  // Tint color
    static let readingBackground = Color("ReadingBG")      // Custom
    static let highlightYellow = Color("HighlightYellow")
    static let highlightBlue = Color("HighlightBlue")
    static let highlightGreen = Color("HighlightGreen")
    static let highlightRed = Color("HighlightRed")
}
```

### 8.2 Reusable Components

| Component | Description |
|-----------|-------------|
| `BookCoverView` | Book cover with shadow and loading skeleton |
| `ChatBubble` | AI/User message bubble with markdown |
| `MarkdownView` | Rich markdown renderer for AI responses |
| `ThinkingDisclosure` | Collapsible thinking/answer/tools sections |
| `ToolApprovalTile` | Tool execution approval UI |
| `ProviderSelector` | AI provider/model picker |
| `AttachmentPicker` | Image + text file attachment UI |
| `HeatmapCalendar` | Reading streak heatmap |
| `StatisticTile` | Dashboard analytics tile |
| `SkeletonView` | Loading placeholder |
| `SearchBar` | Custom searchable overlay |
| `TagChip` | Tag pill with color |
| `ProgressRing` | Circular progress indicator |
| `EmptyStateView` | Empty collection placeholder |

### 8.3 Markdown Renderer

Replace `gpt_markdown` with native Swift:
- Use `AttributedString` (iOS 15+) for rich text
- Code blocks with syntax highlighting (TreeSitter or regex-based)
- LaTeX rendering via MathJax WKWebView (for math-heavy papers)
- Inline images
- Tables
- Collapsible `<think>` blocks

---

## 9. PTFeatures — Feature Modules

### 9.1 Navigation Architecture

**iOS:**
```swift
TabView {
    PapersView()        // tab 1: 论文
    BookshelfView()     // tab 2: 书架
    NotesView()         // tab 3: 笔记
    StatisticsView()    // tab 4: 统计
    AIChatView()        // tab 5: AI
    SettingsView()      // tab 6: 设置
}
```

**macOS:**
```swift
NavigationSplitView {
    List(selection: $selectedTab) {
        Label("Papers", systemImage: "doc.text")
        Label("Bookshelf", systemImage: "books.vertical")
        Label("Notes", systemImage: "note.text")
        Label("Statistics", systemImage: "chart.bar")
        Label("AI", systemImage: "bubble.left.and.text.bubble.right")
        Label("Settings", systemImage: "gear")
    }
} detail: {
    switch selectedTab { ... }
}
```

### 9.2 Feature Breakdown

**Papers (PaperTok):**
- Random paper feed with language selector (zh/en)
- Paper detail view (abstract, authors, links)
- Import paper to bookshelf
- Date-based browsing

**Bookshelf:**
- Grid/List toggle view
- Hierarchical group folders (drag-and-drop reorder)
- Book import (Files, iCloud, Share Sheet)
- Cover extraction
- AI-assisted reorganization
- Sort/filter by tags, date, progress

**Reader:**
- EPUB rendering (Readium)
- PDF rendering (Readium)
- Reading settings panel (font, theme, margins, page turn mode)
- Highlights, bookmarks, notes (color-coded)
- In-reader AI panel (iPad: resizable side panel, iPhone: sheet)
- Full-text search
- TOC navigation
- Reading progress bar
- TTS narration
- Inline full-text translation
- Image tap → AI analysis

**Notes:**
- Unified notes view across all books
- Search within notes
- Group by book
- Export

**Statistics:**
- Customizable dashboard tiles
- Heatmap calendar (reading streak)
- Daily reading trends
- Completion tracking
- Random daily highlight

**AI Chat:**
- Conversation list + detail
- Streaming responses with minimize UX
- Provider/model switching in-chat
- Thinking level selector
- Multimodal attachments (4 images + 3 text files)
- Conversation tree v2 (branching, variants, rollback)
- Edit any turn, regenerate
- Tool execution with approval UI
- Collapsible thinking/answer/tools sections
- Token/cost display

**Settings:**
- Appearance (theme, background images, accent color)
- Reading preferences (font, margins, page turn, chapter split rules)
- AI general (provider center, system prompt, quick prompts)
- AI image analysis (separate provider/model)
- AI library index (RAG management)
- AI tools (approval policies)
- AI memory settings
- MCP servers configuration
- Translation provider selection
- TTS/narrate settings
- Sync (WebDAV configuration)
- Storage (database size, cache management)
- Developer options (logs, vibration test)
- About

### 9.3 iPad AI Panel (Reading Page)

```
┌─────────────────────────────────────────────────────┐
│  ┌──────────────────────┐  ┌──────────────────────┐ │
│  │                      │  │   AI Chat Panel      │ │
│  │   EPUB Reader        │◄►│   (resizable)        │ │
│  │   (Readium)          │  │                      │ │
│  │                      │  │   - Messages         │ │
│  │                      │  │   - Streaming         │ │
│  │                      │  │   - Tool results     │ │
│  │                      │  │   - Minimize button  │ │
│  └──────────────────────┘  └──────────────────────┘ │
└─────────────────────────────────────────────────────┘
        Drag handle ◄► to resize
```

- Width persisted per-book
- Left/right side toggle
- Minimize: keeps generating in background while reading
- Smart auto-scroll on new content

---

## 10. Platform Integration

### 10.1 EventKit (Calendar & Reminders)

Direct Swift EventKit (no platform channel bridge needed):
```swift
actor EventKitService {
    private let store = EKEventStore()
    
    // Calendar
    func listCalendars() -> [EKCalendar]
    func listEvents(from: Date, to: Date) -> [EKEvent]
    func createEvent(_ event: EKEvent) throws
    func updateEvent(_ event: EKEvent, span: EKSpan) throws
    func deleteEvent(_ event: EKEvent, span: EKSpan) throws
    
    // Reminders
    func listReminderLists() -> [EKCalendar]
    func fetchReminders(in calendars: [EKCalendar]) async -> [EKReminder]
    func createReminder(_ reminder: EKReminder) throws
    func completeReminder(_ reminder: EKReminder) throws
}
```

### 10.2 App Intents (Shortcuts)

```swift
struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Message to PaperTok"
    
    @Parameter(title: "Message") var prompt: String
    @Parameter(title: "Images") var images: [IntentFile]?
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let response = try await AIService.shared.sendMessage(prompt, images: images)
        return .result(value: response)
    }
}
```

### 10.3 Share Extension

Separate target, Swift native:
- App Group container: `group.ai.papertok.paperreader`
- File structure: `<AppGroup>/share_handler/inbox/<eventId>/files/`
- Supports: text, URLs, images, files
- Routes to: AI chat, bookshelf import, or quick ask

### 10.4 Deep Links

```swift
// SwiftUI
.onOpenURL { url in
    DeepLinkRouter.handle(url)   // paperreader://reader/..., paperreader://shortcuts/ask
}
```

### 10.5 macOS-Specific

```swift
#if os(macOS)
struct MacCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Book...") { ... }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandMenu("Reading") {
            Button("Next Page") { ... }.keyboardShortcut(.rightArrow)
            Button("Previous Page") { ... }.keyboardShortcut(.leftArrow)
            Button("Toggle AI Panel") { ... }.keyboardShortcut("\\", modifiers: .command)
        }
    }
}
#endif
```

---

## 11. Localization

### Strategy
- Xcode String Catalogs (`.xcstrings`) — compile-time safe, Xcode native editor
- Migrate all 14 languages from Flutter ARB files
- Use `String(localized:)` API throughout

### Languages
en, zh-Hans, zh-Hant, de, es, fr, it, ja, ko, pt-BR, ro, ru, tr, ar (+ Mongolian script)

### Migration Process
1. Parse Flutter `app_en.arb` as reference
2. Generate `.xcstrings` catalog with all keys
3. Import translations from each `app_*.arb` file
4. Verify coverage against `untranslated_messages.txt`

---

## 12. Data Migration (Flutter → Swift)

For users upgrading from the Flutter version:

1. **Database:** Copy `anx_reader.db` from Flutter app container to Swift app container. GRDB reads same SQLite schema.
2. **Books:** EPUB/PDF files stored in app documents — copy via Files or iCloud backup.
3. **Settings:** Export from Flutter (WebDAV or encrypted backup), import in Swift.
4. **API Keys:** Manual re-entry (security: never auto-transfer secrets between apps).
5. **Memory:** Copy `memory/` directory (Markdown files are portable).

---

## 13. Third-Party Dependencies Summary

| Package | Purpose | Platform |
|---------|---------|----------|
| GRDB.swift | SQLite ORM + migrations | iOS + macOS |
| ReadiumShared | EPUB/PDF core models | iOS + macOS |
| ReadiumStreamer | Publication parsing | iOS + macOS |
| ReadiumNavigator | EPUB/PDF rendering | iOS (UIKit bridge for macOS) |
| Kingfisher | Image caching (covers, network images) | iOS + macOS |
| swift-markdown-ui | Markdown rendering alternative | iOS + macOS |
| KeychainAccess | Keychain wrapper | iOS + macOS |

All other functionality (HTTP, SSE, WebDAV, AI providers, translation) is custom-built using Foundation/URLSession.

---

## 14. Testing Strategy

| Layer | Testing Approach |
|-------|-----------------|
| PTCore | Unit tests: model encoding, DB migrations, DAO queries |
| PTNetworking | Unit tests: SSE parsing, endpoint building. Integration: mock server |
| PTReader | Integration tests: Readium publication parsing, locator conversion |
| PTAIServices | Unit tests: tool execution, prompt generation, conversation tree. Integration: mock LLM |
| PTUI | SwiftUI previews for all components |
| PTFeatures | UI tests: navigation flows, critical user journeys |
| App | End-to-end: import book → read → highlight → AI chat |

---

## 15. Build Configuration

| Config | Value |
|--------|-------|
| Bundle ID | `ai.papertok.paperreader` |
| App Group | `group.ai.papertok.paperreader` |
| Share Extension Bundle ID | `ai.papertok.paperreader.shareExtension` |
| URL Schemes | `paperreader`, `ShareMedia-ai.papertok.paperreader` |
| Minimum iOS | 17.0 |
| Minimum macOS | 14.0 |
| Swift Version | 5.9+ |
| Xcode | 15.0+ |

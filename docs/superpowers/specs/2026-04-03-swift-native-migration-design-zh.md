# PaperTok Reader — Flutter 迁移至 Swift 原生架构设计

**日期：** 2026-04-03
**状态：** 已批准
**范围：** 完整 1:1 功能迁移 + Apple 风格 UI 重新设计 + macOS 支持

---

## 1. 概述

将整个 PaperTok Reader Flutter 应用（551+ 个 Dart 文件，7.8 MB 源码）迁移至原生 Swift iOS/macOS 应用。所有功能 1:1 复现，UI 按照 Apple 人机界面指南使用 SwiftUI 重新设计。

### 关键决策

| 决策 | 选择 | 理由 |
|------|------|------|
| UI 框架 | SwiftUI + UIKit 混合 | SwiftUI 承担全部 UI，UIKit 桥接用于 EPUB/PDF 渲染 |
| EPUB 引擎 | Readium Swift SDK | 纯原生 Swift，社区维护，支持 macOS |
| 数据持久化 | GRDB.swift（SQLite） | 直接复用 Schema，支持 RAG 向量查询，性能最佳 |
| AI/LLM 层 | 自定义 URLSession + SSE | 完整掌控 76 个工具、非标准 Provider 及流式输出 |
| macOS 支持 | SwiftUI 多平台 App | 共享逻辑与 UI，用 `#if os()` 处理平台差异 |
| 状态管理 | @Observable（Observation 框架） | iOS 17+ 原生，替代 Riverpod |
| 仓库策略 | 同仓库孤立分支 `swift-native` | 全新起点，便于参考 Flutter 代码 |
| 架构 | 模块化 Swift Packages（6 个 Package） | 增量编译、可测试、依赖关系清晰 |
| 最低目标版本 | iOS 17.0 / macOS 14.0 | @Observable、SwiftData 共存及现代 SwiftUI 的必要条件 |
| 本地化 | Xcode String Catalogs（.xcstrings） | 14 种语言，编译时安全，Xcode 原生工具链 |

---

## 2. 项目结构

```
PaperTokReader/
├── PaperTokReader.xcworkspace
├── App/                                    # 多平台 App Target
│   ├── PaperTokReaderApp.swift            # @main 入口
│   ├── AppDelegate.swift                  # UIKit 生命周期（iOS）
│   ├── Info.plist
│   ├── Entitlements/
│   │   ├── iOS.entitlements               # App Groups、Keychain
│   │   └── macOS.entitlements             # App Groups、Keychain、Sandbox
│   ├── iOS/                               # iOS 专属代码
│   │   └── SceneDelegate.swift
│   ├── macOS/                             # macOS 专属代码
│   │   └── MacCommands.swift              # 菜单栏命令
│   ├── Resources/
│   │   ├── Assets.xcassets                # App 图标、颜色、图片
│   │   ├── Fonts/                         # 思源宋体 SC
│   │   ├── Localizable.xcstrings          # 14 种语言
│   │   └── BackgroundImages/              # 阅读背景图
│   └── Extensions/
│       ├── ShareExtension/                # iOS/macOS Share Extension Target
│       │   ├── ShareViewController.swift
│       │   ├── Info.plist
│       │   └── shareExtension.entitlements
│       └── AppIntents/                    # Shortcuts 意图
│           └── SendMessageIntent.swift
├── Packages/
│   ├── PTCore/
│   │   ├── Package.swift
│   │   ├── Sources/PTCore/
│   │   │   ├── Models/                    # Book、BookNote、Tag 等
│   │   │   ├── Database/                  # GRDB 配置、迁移、DAO
│   │   │   ├── Enums/                     # 所有枚举类型
│   │   │   ├── Config/                    # AppConfig、UserDefaults 封装
│   │   │   └── Utils/                     # 扩展、工具函数
│   │   └── Tests/PTCoreTests/
│   ├── PTNetworking/
│   │   ├── Package.swift
│   │   ├── Sources/PTNetworking/
│   │   │   ├── HTTP/                      # NetworkClient、Endpoint
│   │   │   ├── SSE/                       # SSEParser、SSEEvent
│   │   │   ├── WebDAV/                    # WebDAVClient、同步逻辑
│   │   │   └── PaperTok/                  # PaperTok REST API 客户端
│   │   └── Tests/PTNetworkingTests/
│   ├── PTReader/
│   │   ├── Package.swift
│   │   ├── Sources/PTReader/
│   │   │   ├── EPUB/                      # Readium EPUB 集成
│   │   │   ├── PDF/                       # Readium PDF 集成
│   │   │   ├── Common/                    # ReaderEngine、LocatorService
│   │   │   ├── Preferences/              # ReadingStyle、ReadingTheme
│   │   │   └── TTS/                       # AVSpeechSynthesizer 封装
│   │   └── Tests/PTReaderTests/
│   ├── PTAIServices/
│   │   ├── Package.swift
│   │   ├── Sources/PTAIServices/
│   │   │   ├── Providers/                 # OpenAI、Anthropic、Gemini 等
│   │   │   ├── Chat/                      # ChatService、ConversationTree
│   │   │   ├── Tools/                     # 76 个 AI 工具 + 编排器
│   │   │   ├── RAG/                       # Embeddings、向量搜索、索引
│   │   │   ├── Memory/                    # MemoryStore、摘要、搜索
│   │   │   ├── Translation/              # AI 翻译器
│   │   │   ├── Skills/                    # Skill 注册表、内置 Skill
│   │   │   ├── SubAgent/                  # 子 Agent 运行器
│   │   │   └── MCP/                       # MCP 客户端、JSON-RPC、工具注册表
│   │   └── Tests/PTAIServicesTests/
│   ├── PTUI/
│   │   ├── Package.swift
│   │   ├── Sources/PTUI/
│   │   │   ├── Components/               # 按钮、卡片、标签、对话框
│   │   │   ├── Markdown/                 # Markdown 渲染器（AI 响应）
│   │   │   ├── Charts/                   # 阅读统计图表
│   │   │   ├── Theme/                    # 配色方案、字体排版
│   │   │   └── Modifiers/               # 自定义 ViewModifiers
│   │   └── Tests/PTUITests/
│   └── PTFeatures/
│       ├── Package.swift
│       ├── Sources/PTFeatures/
│       │   ├── Papers/                    # PaperTok 论文流、详情、导入
│       │   ├── Bookshelf/                # 书库、分组、导入、整理
│       │   ├── Reader/                    # 阅读页、AI 面板、设置
│       │   ├── Notes/                     # 笔记列表、搜索、导出
│       │   ├── Statistics/               # 仪表盘、热力图、趋势
│       │   ├── AIChat/                    # 聊天 UI、历史记录、Provider 切换
│       │   ├── Settings/                  # 所有设置子页面
│       │   ├── Search/                    # 全文搜索
│       │   ├── Onboarding/               # 引导页
│       │   ├── Share/                     # 分享处理、路由
│       │   └── Navigation/               # Tab/侧边栏路由
│       └── Tests/PTFeaturesTests/
└── vendor/                                # 如有需要，存放 Fork 的依赖
```

---

## 3. Package 依赖关系图

```
App
 └── PTFeatures
      ├── PTUI ──────────→ PTCore
      ├── PTAIServices ──→ PTNetworking ──→ PTCore
      ├── PTReader ──────→ PTCore
      └── (direct) ──────→ PTCore
```

**依赖规则：**
- PTCore：仅依赖 GRDB.swift（零其他外部依赖）
- PTNetworking：仅依赖 PTCore
- PTReader：PTCore + ReadiumOPDS + ReadiumShared + ReadiumNavigator + ReadiumStreamer
- PTAIServices：PTCore + PTNetworking
- PTUI：仅依赖 PTCore
- PTFeatures：依赖以上所有 Package
- App：PTFeatures + 平台框架（EventKit、AppIntents 等）

---

## 4. PTCore — 数据模型、数据库与配置

### 4.1 数据库（GRDB.swift）

Schema 版本 7，与 Flutter SQLite Schema 完全一致，实现零成本数据迁移：

**数据表：**
| 数据表 | 主键 | 描述 |
|--------|------|------|
| tb_books | id（自增） | 书籍元数据、文件路径、进度、封面 |
| tb_notes | id（自增） | 高亮、书签、笔记及 CFI 位置信息 |
| tb_themes | id（自增） | 阅读主题（背景色/文字颜色） |
| tb_styles | id（自增） | 阅读样式（字体、边距、间距） |
| tb_reading_time | id（自增） | 每日阅读时长记录 |
| tb_tags | id（自增） | 书籍标签/分类 |
| tb_groups | id（自增） | 书架文件夹层级（parent_id 外键） |

AI 相关附加表：
| 数据表 | 描述 |
|--------|------|
| ai_conversations | 对话树 v2（每个对话存储 JSON blob） |
| ai_embeddings | RAG 向量嵌入（book_id、chunk_id、vector BLOB） |
| ai_memory_index | 记忆搜索索引（文本 + 嵌入向量） |

**迁移策略：**
- 使用 DatabaseMigrator 进行编号迁移 v1–v7
- 未来迁移从 v8 开始递增
- 从 Flutter 升级的用户：将 `anx_reader.db` 复制到 Swift 应用容器，运行待执行的迁移

### 4.2 数据模型

所有模型均为 Swift 结构体，遵循 `Codable`、`FetchableRecord`、`PersistableRecord`、`Identifiable`、`Sendable` 协议。

**核心模型（从 44 个 Dart 模型映射）：**
- `Book` — 元数据、文件路径、阅读进度
- `BookNote` — 标注，含 CFI、颜色、类型（高亮/书签/笔记）
- `ReadingTime` — 每日时长追踪
- `Tag`、`BookTag` — 分类标签
- `TbGroup` — 书架文件夹层级
- `ReadTheme` — 视觉主题（颜色）
- `BookStyle` — 每本书的阅读偏好（字体、边距、间距）
- `AiConversation` — 对话树 v2，支持分支
- `AiMessage` — 单条消息，含角色、内容、工具调用、思考过程
- `AiProviderConfig` — Provider 配置（端点、API 密钥、模型）
- `AiToolApproval` — 每个工具的审批策略
- `AttachmentItem` — 多模态附件（图片/文本，base64/路径）
- `SyncState` — WebDAV 同步状态
- `PaperTokPaper` — 学术论文元数据
- `ChapterSplitRule` — 自定义章节边界正则表达式
- `SharePromptPreset` — 分享路由预设

### 4.3 配置

```swift
// 通过 AppStorage + App Group UserDefaults 实现全局配置
enum AppConfig {
    static let suiteName = "group.ai.papertok.paperreader"
    static let defaults = UserDefaults(suiteName: suiteName)!
    
    // AI 设置
    @AppStorage("ai_provider_id", store: defaults) static var aiProviderId = "openai"
    @AppStorage("ai_model_id", store: defaults) static var aiModelId = "gpt-4o"
    @AppStorage("ai_system_prompt", store: defaults) static var aiSystemPrompt = ""
    @AppStorage("ai_thinking_level", store: defaults) static var aiThinkingLevel = 0
    
    // 阅读设置
    @AppStorage("default_font_size", store: defaults) static var defaultFontSize = 18.0
    @AppStorage("page_turn_mode", store: defaults) static var pageTurnMode = "swipe"
    
    // 同步设置
    @AppStorage("webdav_url", store: defaults) static var webdavURL = ""
    @AppStorage("webdav_username", store: defaults) static var webdavUsername = ""
    // API 密钥存储在 Keychain 中，不存储在 UserDefaults 中
}
```

### 4.4 Keychain

API 密钥存储在 iOS/macOS Keychain 中（替代 Flutter 的加密 SharedPreferences）：
```swift
struct KeychainService {
    static func save(key: String, value: String) throws
    static func load(key: String) throws -> String?
    static func delete(key: String) throws
}
```

### 4.5 状态管理

使用 `@Observable`（Observation 框架，iOS 17+）替代 Riverpod：

| Flutter（Riverpod） | Swift（@Observable） |
|---------------------|---------------------|
| `StateNotifierProvider` | `@Observable class ViewModel` |
| `FutureProvider` | ViewModel 中的 `async func` |
| `StreamProvider` | `AsyncSequence` / `AsyncStream` |
| `ref.watch()` | SwiftUI 自动追踪 `@Observable` 属性 |
| `ref.read()` | 直接属性访问 |
| `ProviderScope` | `@Environment` + `.environment()` 修饰符 |

通过 SwiftUI Environment 进行依赖注入：
```swift
@Observable final class BookshelfViewModel { ... }

// 在 App 中
ContentView()
    .environment(BookshelfViewModel(db: appDatabase))
    .environment(AIChatViewModel(aiService: aiService))
```

---

## 5. PTNetworking — HTTP、SSE、WebDAV

### 5.1 网络客户端

```swift
// 替代 Dio
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

### 5.2 SSE 流解析器

```swift
// 用于 LLM 流式输出的 Server-Sent Events 解析器
struct SSEEvent {
    let event: String?    // 事件类型
    let data: String      // 载荷（JSON）
    let id: String?
    let retry: Int?
}

struct SSEParser {
    /// 将 URLSession.AsyncBytes 解析为 SSE 事件
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error>
}
```

功能特性：
- 15 秒心跳检测（防止代理断开连接）
- JSON 修复层，处理 LLM 截断输出
- 自动重连，携带 last-event-id

### 5.3 WebDAV 客户端

```swift
actor WebDAVClient {
    func propfind(path: String) async throws -> [RemoteFile]
    func get(path: String) async throws -> Data
    func put(path: String, data: Data) async throws
    func delete(path: String) async throws
    func mkcol(path: String) async throws
    
    // 认证方式
    enum Auth {
        case basic(user: String, password: String)
        case digest(user: String, password: String, realm: String, nonce: String)
    }
}
```

同步策略：
- AI 设置快照：整文件以较新时间戳为准（时间戳比较）
- 同步载荷中排除 `api_key`
- 同步触发时机：应用前后台切换、手动触发

### 5.4 PaperTok API 客户端

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

## 6. PTReader — Readium EPUB/PDF 引擎

### 6.1 依赖项

- `ReadiumShared` — 核心模型（Publication、Locator、Link）
- `ReadiumStreamer` — 出版物解析（EPUB/PDF）
- `ReadiumNavigator` — 渲染引擎（EPUBNavigatorViewController、PDFNavigatorViewController）
- `ReadiumOPDS` — 可选，用于 OPDS 目录支持

### 6.2 阅读引擎

```swift
@Observable
final class ReaderEngine {
    let publication: Publication
    var currentLocator: Locator
    var readingProgress: Double
    var tableOfContents: [Link]
    
    // 导航器（UIKit，桥接至 SwiftUI）
    let epubNavigator: EPUBNavigatorViewController
    // 或
    let pdfNavigator: PDFNavigatorViewController
}
```

### 6.3 功能映射

| 功能 | Readium API |
|------|-------------|
| 打开 EPUB | Streamer.open(asset:) → Publication |
| 打开 PDF | Streamer.open(asset:) → Publication |
| 页面导航 | Navigator.go(to: Locator) |
| 当前位置 | Navigator.currentLocation → Locator |
| 进度 | Locator.locations.totalProgression |
| 目录 | Publication.tableOfContents |
| 全文搜索 | Publication.search(query:) → SearchIterator |
| 文本选择 | Navigator.delegate（选择回调） |
| 高亮 | DecorationStyle + Navigator.apply(decorations:) |
| 书签 | 将 Locator 保存到数据库 |
| 自定义 CSS | EPUBPreferences（字号、字体、主题、边距等） |
| 图片 | Navigator delegate 处理图片点击事件 |
| CFI 支持 | Locator 在 locations 中包含 EPUB CFI |
| 双页/滚动模式 | EPUBPreferences.scroll、.spread |

### 6.4 SwiftUI 桥接

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

### 6.5 PDF 增强内容桥接（新增）

```swift
// 统一内容访问接口，适用于 EPUB 和 PDF
protocol BookContentBridge: Sendable {
    func extractChapterContent(href: String) async throws -> String
    func extractFullText() async throws -> String
    func searchContent(query: String) async throws -> [ContentSearchResult]
}

// PDF 专用实现
struct PDFContentBridge: BookContentBridge {
    let document: PDFDocument                     // PDFKit
    
    func extractPageText(page: Int) -> String     // PDFPage.string
    func extractFullText() async throws -> String // 所有页面文本拼接
    func ocrPage(page: Int) async throws -> String // Vision VNRecognizeTextRequest 用于扫描版 PDF
    func segmentByOutline() -> [PDFChapter]       // 按 PDF 书签/大纲拆分
}
```

PDF 内容现在可供所有 AI 工具、RAG 索引和翻译功能使用 — 与 EPUB 完全一致。

### 6.6 TTS（文本转语音）

使用原生方案替代 Flutter 的 `flutter_tts` + `audio_service`：
```swift
@Observable final class TTSService {
    private let synthesizer = AVSpeechSynthesizer()
    
    func speak(text: String, language: String, rate: Float)
    func pause()
    func resume()
    func stop()
    
    // 更新锁屏/控制中心的 NowPlayingInfo
    private func updateNowPlaying()
}
```

---

## 7. PTAIServices — LLM、工具、RAG、记忆、翻译

### 7.1 统一聊天模型协议

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
    let delta: ContentDelta          // text、toolCall、thinking
    let finishReason: FinishReason?
    let usage: TokenUsage?
}
```

### 7.2 Provider 实现

| Provider | 主要功能 |
|----------|----------|
| `OpenAIProvider` | GPT-4o/4，工具调用、视觉、流式输出 |
| `AnthropicProvider` | Claude，扩展思考（thinking blocks）、流式输出 |
| `GeminiProvider` | Gemini，includeThoughts 开关、流式输出 |
| `VolcengineArkProvider` | 火山引擎 Ark，多模态，base64 图片 |
| `OpenAIResponsesProvider` | Responses API，previous_response_id、reasoning_summary |
| `CustomOpenAICompatibleProvider` | 任意 OpenAI 兼容端点 |

### 7.3 工具系统（76 个工具）

```swift
protocol AITool: Sendable {
    static var name: String { get }
    static var description: String { get }
    static var parameterSchema: JSONSchema { get }
    static var category: ToolCategory { get }
    static var concurrencyPartition: String { get }  // 用于安全并发执行
    
    func execute(arguments: JSON, context: ToolContext) async throws -> ToolResult
}

enum ToolCategory {
    case bookLibrary       // bookshelf_lookup、books_tags_list 等
    case bookContent       // current_book_fulltext、chapter_content 等
    case annotation        // create_highlight、create_note
    case search            // semantic_search_current_book、semantic_search_library、book_content_search
    case readingHistory    // current_reading_metadata、reading_history
    case calendar          // calendar_list/get/create/update/delete
    case reminders         // reminders_list/get/create/update/delete/complete
    case utility           // current_time、calculator、fetch_url、web_search
    case agent             // spawn_sub_agent、shortcuts_run
    case memory            // memory_read、memory_write、memory_search
    case mindmap           // 思维导图生成
}
```

**工具编排器：**
```swift
actor ToolOrchestrator {
    let approvalDelegate: ToolApprovalDelegate
    let annotationLedger: AnnotationLedger       // 防止重复高亮
    
    func execute(calls: [ToolCall], context: ToolContext) async throws -> [ToolResult] {
        // 1. 检查每个工具的审批策略
        // 2. 按并发安全性分组
        // 3. 安全的工具并发执行，不安全的串行执行
        // 4. 返回结果及耗时信息
    }
}
```

**场景感知过滤：**
- 阅读场景：减少约 50% 的工具（排除日历、提醒、网页搜索，除非与上下文相关）
- 聊天场景：完整工具集

### 7.4 对话树 v2

```swift
struct ConversationTree: Codable {
    var rootId: String
    var nodes: [String: ConversationNode]     // id → 节点
    
    struct ConversationNode: Codable {
        let id: String
        let role: ChatRole
        let content: MessageContent
        let parentId: String?
        var childIds: [String]                 // 分支：多个子节点
        var activeChildIndex: Int              // 当前活跃分支
        let metadata: NodeMetadata             // 时间戳、模型、token 数
    }
}
```

功能特性：
- 每轮助手回复的变体切换（在不同的重新生成结果间切换）
- 回滚到旧变体时不丢失后续对话轮次
- 编辑任意用户轮次并从该处分支
- 跨应用重启持久化

### 7.5 RAG（检索增强生成）

```swift
struct EmbeddingService {
    let provider: ChatModelProvider           // 仅远程 API（Ollama 已移除 — 在 iOS 上不可行）
    func embed(texts: [String]) async throws -> [[Float]]
    // 回退方案：当未配置嵌入向量 Provider 时使用 FTS5 全文搜索
}

struct SemanticSearchService {
    let db: AppDatabase
    let embedder: EmbeddingService
    
    func searchCurrentBook(query: String, bookId: Int64, topK: Int) async throws -> [SearchResult]
    func searchLibrary(query: String, topK: Int) async throws -> [SearchResult]
}

// 索引队列
actor LibraryIndexQueue {
    func enqueue(bookId: Int64)
    func pause()
    func resume()
    func cancel()
    var progress: AsyncStream<IndexProgress> { get }
}
```

**文本分块策略：**
- 固定大小 + 重叠窗口
- 基于段落
- AI 辅助语义分块

**搜索模式：**
- 向量相似度（余弦相似度）
- FTS5 全文搜索（BM25）
- 混合模式（FTS + 向量 + 可选 MMR 重排序）

### 7.6 记忆系统

```swift
struct MemoryStore {
    let basePath: URL                          // App documents/memory/
    
    // 文件
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

### 7.7 翻译引擎（纯 AI）

```swift
// 单一 AI 翻译方案 — 不使用第三方 API（DeepL、Google、Microsoft 已移除）
struct AITranslator: Sendable {
    let chatProvider: ChatModelProvider
    
    func translate(text: String, from: Language, to: Language) async throws -> String
    func translateBatch(texts: [String], from: Language, to: Language) async throws -> [String]
}

// 全文翻译，支持按书缓存
actor FulltextTranslationEngine {
    let translator: AITranslator
    
    func translateBook(bookId: Int64) -> AsyncStream<TranslationProgress>
    func getCachedTranslation(bookId: Int64, segment: String) -> String?
    func clearCache(bookId: Int64) async
}
```

### 7.8 MCP（模型上下文协议）

```swift
actor MCPClient {
    func connect(url: URL, transport: MCPTransport) async throws
    func listTools() async throws -> [MCPToolDefinition]
    func callTool(name: String, arguments: JSON) async throws -> MCPToolResult
    func disconnect() async
}

enum MCPTransport {
    case sse(url: URL)                         // 传统 HTTP+SSE
    case streamableHTTP(url: URL)              // Streamable HTTP
}
```

### 7.9 子 Agent 系统

```swift
struct SubAgentRunner {
    let chatService: ChatService
    
    func spawn(
        task: String,
        restrictedTools: Set<String>,          // 可用工具的子集
        parentContext: ChatContext
    ) -> AsyncThrowingStream<SubAgentEvent, Error>
}
```

### 7.10 KAIROS 主动式助手

```swift
@Observable final class KairosService {
    var dwellTime: TimeInterval = 0
    var suggestions: [KairosSuggestion] = []
    
    func monitorReading(locator: Locator) async
    func detectChapterCompletion() -> Bool
    func surfaceSuggestion(_ suggestion: KairosSuggestion)
}
```

### 7.11 Token/费用追踪

```swift
struct UsageTracker {
    func record(model: String, usage: TokenUsage)
    func totalCost(since: Date) -> Decimal
    func usageHistory() -> [UsageRecord]
    
    // 内置 5 个模型系列的定价表
    static let pricing: [String: ModelPricing]
}
```

---

## 8. PTUI — 共享 SwiftUI 组件

### 8.1 设计系统

**Apple HIG 设计原则：**
- SF Symbols 用于所有图标（替代 icons_plus）
- **莫兰迪色系**作为主设计语言（低饱和度莫兰迪色系）
- Dynamic Type 支持
- 深色模式跟随系统自动切换（莫兰迪深色变体）
- 材质效果（`.ultraThinMaterial`、`.regularMaterial`）实现毛玻璃拟态
- 触觉反馈通过 `UIFeedbackGenerator` / `NSHapticFeedbackManager` 实现
- 所有设置页面：原生 `Form` + `Section` + `List` 布局

**字体排版：**
```swift
enum PTTypography {
    static let title = Font.title
    static let headline = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    // 中文：阅读内容使用思源宋体 SC
    static func readingFont(size: CGFloat) -> Font
}
```

**莫兰迪色系调色板：**
```swift
enum PTColors {
    // 莫兰迪主色调（柔和、低饱和度、优雅）
    static let morandiRose = Color(hex: "#C4A4A0")        // 烟粉色
    static let morandiSage = Color(hex: "#A8B5A2")        // 鼠尾草绿
    static let morandiBlue = Color(hex: "#9AABB9")        // 柔雾蓝
    static let morandiSand = Color(hex: "#C8B9A6")        // 暖沙色
    static let morandiLavender = Color(hex: "#B5A8C4")    // 雾紫色
    static let morandiGray = Color(hex: "#B0A8A0")        // 暖灰色
    
    // 功能色（莫兰迪色调）
    static let accent = Color("MorandiAccent")             // 主强调色
    static let readingBackground = Color("ReadingBG")
    static let highlightYellow = Color(hex: "#D4C5A0")    // 莫兰迪黄
    static let highlightBlue = Color(hex: "#9AABB9")      // 莫兰迪蓝
    static let highlightGreen = Color(hex: "#A8B5A2")     // 莫兰迪绿
    static let highlightRed = Color(hex: "#C4A4A0")       // 莫兰迪玫瑰
    static let highlightPurple = Color(hex: "#B5A8C4")    // 莫兰迪薰衣草
    
    // 语义色
    static let cardBackground = Color("CardBG")            // 微浮表面
    static let sectionHeader = Color("SectionHeader")      // 柔和文字色
}
```

### 8.2 可复用组件

| 组件 | 描述 |
|------|------|
| `BookCoverView` | 书籍封面，带阴影和加载骨架屏 |
| `ChatBubble` | AI/用户消息气泡，支持 Markdown |
| `MarkdownView` | 富文本 Markdown 渲染器，用于 AI 响应 |
| `ThinkingDisclosure` | 可折叠的思考/回答/工具区域 |
| `ToolApprovalTile` | 工具执行审批 UI |
| `ProviderSelector` | AI Provider/模型选择器 |
| `AttachmentPicker` | 图片 + 文本文件附件 UI |
| `HeatmapCalendar` | 阅读连续打卡热力图 |
| `StatisticTile` | 仪表盘数据分析磁贴 |
| `SkeletonView` | 加载占位符 |
| `SearchBar` | 自定义搜索叠加层 |
| `TagChip` | 带颜色的标签胶囊 |
| `ProgressRing` | 圆形进度指示器 |
| `EmptyStateView` | 空集合占位视图 |

### 8.3 Markdown 渲染器

使用原生 Swift 替代 `gpt_markdown`：
- 使用 `AttributedString`（iOS 15+）进行富文本渲染
- 代码块语法高亮（基于 TreeSitter 或正则表达式）
- LaTeX 渲染通过 MathJax WKWebView 实现（适用于数学密集型论文）
- 内联图片
- 表格
- 可折叠 `<think>` 块

---

## 9. PTFeatures — 功能模块

### 9.1 导航架构

**iOS：**
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

**macOS：**
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

### 9.2 功能详解

**论文（PaperTok）：**
- 随机论文流，带语言选择器（中/英）
- 论文详情页（摘要、作者、链接）
- 导入论文到书架
- 按日期浏览

**书架：**
- 网格/列表视图切换
- 层级分组文件夹（拖拽排序）
- 双模式书籍导入：
  - 沙盒导入（文件、iCloud、Share Sheet — 复制到应用容器）
  - 目录扫描（Security-Scoped Bookmarks — 原位读取，无需复制）
  - 文件系统监控，自动发现新书
- 封面提取
- AI 辅助重新整理
- 按标签、日期、进度排序/筛选

**阅读器：**
- EPUB 渲染（Readium）
- PDF 渲染（Readium）
- 阅读设置面板（字体、主题、边距、翻页模式）
- 高亮、书签、笔记（彩色编码）
- 阅读器内 AI 面板（iPad：可调整大小的侧面板，iPhone：底部弹出面板）
- 全文搜索
- 目录导航
- 阅读进度条
- TTS 朗读
- 内联全文翻译
- 图片点击 → AI 分析

**笔记：**
- 跨所有书籍的统一笔记视图
- 笔记内搜索
- 按书籍分组
- 导出

**统计：**
- 可自定义仪表盘磁贴
- 热力图日历（阅读打卡）
- 每日阅读趋势
- 完成度追踪
- 每日随机高亮回顾

**AI 聊天：**
- 对话列表 + 详情
- 流式响应，支持最小化 UX
- 聊天中切换 Provider/模型
- 思考层级选择器
- 多模态附件（4 张图片 + 3 个文本文件）
- 对话树 v2（分支、变体、回滚）
- 编辑任意轮次、重新生成
- 工具执行审批 UI
- 可折叠思考/回答/工具区域
- Token/费用显示

**设置：**
- 外观（主题、背景图、强调色）
- 阅读偏好（字体、边距、翻页模式、章节拆分规则）
- AI 通用（Provider 中心、系统提示词、快捷提示词）
- AI 图片分析（独立 Provider/模型）
- AI 书库索引（RAG 管理）
- AI 工具（审批策略）
- AI 记忆设置
- MCP 服务器配置
- 翻译 Provider 选择
- TTS/朗读设置
- 同步（WebDAV 配置）
- 存储（数据库大小、缓存管理）
- 开发者选项（日志、振动测试）
- 关于

### 9.3 iPad AI 面板（阅读页）

```
┌─────────────────────────────────────────────────────┐
│  ┌──────────────────────┐  ┌──────────────────────┐ │
│  │                      │  │   AI 聊天面板        │ │
│  │   EPUB 阅读器        │◄►│   （可调整大小）     │ │
│  │   （Readium）        │  │                      │ │
│  │                      │  │   - 消息             │ │
│  │                      │  │   - 流式输出         │ │
│  │                      │  │   - 工具结果         │ │
│  │                      │  │   - 最小化按钮       │ │
│  └──────────────────────┘  └──────────────────────┘ │
└─────────────────────────────────────────────────────┘
        拖拽手柄 ◄► 调整大小
```

- 宽度按书持久化
- 左/右侧切换
- 最小化：后台继续生成，同时阅读不受影响
- 新内容到来时智能自动滚动

---

## 10. 平台集成

### 10.1 EventKit（日历与提醒事项）

直接使用 Swift EventKit（无需平台通道桥接）：
```swift
actor EventKitService {
    private let store = EKEventStore()
    
    // 日历
    func listCalendars() -> [EKCalendar]
    func listEvents(from: Date, to: Date) -> [EKEvent]
    func createEvent(_ event: EKEvent) throws
    func updateEvent(_ event: EKEvent, span: EKSpan) throws
    func deleteEvent(_ event: EKEvent, span: EKSpan) throws
    
    // 提醒事项
    func listReminderLists() -> [EKCalendar]
    func fetchReminders(in calendars: [EKCalendar]) async -> [EKReminder]
    func createReminder(_ reminder: EKReminder) throws
    func completeReminder(_ reminder: EKReminder) throws
}
```

### 10.2 AppIntents（快捷指令）

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

独立 Target，纯 Swift 原生：
- App Group 容器：`group.ai.papertok.paperreader`
- 文件结构：`<AppGroup>/share_handler/inbox/<eventId>/files/`
- 支持内容类型：文本、URL、图片、文件
- 路由目标：AI 聊天、书架导入 或 快速提问

### 10.4 深度链接

```swift
// SwiftUI
.onOpenURL { url in
    DeepLinkRouter.handle(url)   // paperreader://reader/...、paperreader://shortcuts/ask
}
```

### 10.5 macOS 专属功能

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

## 11. 本地化

### 策略
- Xcode String Catalogs（`.xcstrings`）— 编译时安全，Xcode 原生编辑器
- 从 Flutter ARB 文件迁移全部 14 种语言
- 全面使用 `String(localized:)` API

### 支持语言
en、zh-Hans、zh-Hant、de、es、fr、it、ja、ko、pt-BR、ro、ru、tr、ar（+ 蒙古文字）

### 迁移流程
1. 解析 Flutter `app_en.arb` 作为参考基准
2. 生成包含所有键的 `.xcstrings` 目录
3. 从各 `app_*.arb` 文件导入翻译
4. 对照 `untranslated_messages.txt` 验证覆盖率

---

## 12. 数据迁移（Flutter → Swift）

面向从 Flutter 版本升级的用户：

1. **数据库：** 将 `anx_reader.db` 从 Flutter 应用容器复制到 Swift 应用容器。GRDB 可读取相同的 SQLite Schema。
2. **书籍：** EPUB/PDF 文件存储在应用文档目录中 — 通过"文件"App 或 iCloud 备份复制。
3. **设置：** 从 Flutter 导出（通过 WebDAV 或加密备份），在 Swift 中导入。
4. **API 密钥：** 需手动重新输入（安全考虑：应用间绝不自动传输密钥）。
5. **记忆：** 复制 `memory/` 目录（Markdown 文件具有可移植性）。

---

## 13. 第三方依赖汇总

| 包名 | 用途 | 平台 |
|------|------|------|
| GRDB.swift | SQLite ORM + 迁移 | iOS + macOS |
| ReadiumShared | EPUB/PDF 核心模型 | iOS + macOS |
| ReadiumStreamer | 出版物解析 | iOS + macOS |
| ReadiumNavigator | EPUB/PDF 渲染 | iOS（macOS 通过 UIKit 桥接） |
| Kingfisher | 图片缓存（封面、网络图片） | iOS + macOS |
| swift-markdown-ui | Markdown 渲染替代方案 | iOS + macOS |
| KeychainAccess | Keychain 封装 | iOS + macOS |

其他所有功能（HTTP、SSE、WebDAV、AI Provider、翻译）均基于 Foundation/URLSession 自行构建。

---

## 14. 测试策略

| 层级 | 测试方法 |
|------|----------|
| PTCore | 单元测试：模型编码、数据库迁移、DAO 查询 |
| PTNetworking | 单元测试：SSE 解析、端点构建。集成测试：Mock 服务器 |
| PTReader | 集成测试：Readium 出版物解析、Locator 转换 |
| PTAIServices | 单元测试：工具执行、Prompt 生成、对话树。集成测试：Mock LLM |
| PTUI | SwiftUI 预览覆盖所有组件 |
| PTFeatures | UI 测试：导航流程、关键用户路径 |
| App | 端到端测试：导入书籍 → 阅读 → 高亮 → AI 聊天 |

---

## 15. 构建配置

| 配置项 | 值 |
|--------|-----|
| Bundle ID | `ai.papertok.paperreader` |
| App Group | `group.ai.papertok.paperreader` |
| Share Extension Bundle ID | `ai.papertok.paperreader.shareExtension` |
| URL Schemes | `paperreader`、`ShareMedia-ai.papertok.paperreader` |
| 最低 iOS 版本 | 17.0 |
| 最低 macOS 版本 | 14.0 |
| Swift 版本 | 5.9+ |
| Xcode | 15.0+ |

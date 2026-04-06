# Swift 原生迁移 — 整体进度追踪

**最后更新：** 2026-04-06  
**分支：** `swift-native`  
**最新 TestFlight 构建：** v1.0.0 (build 6408) — 已上传 ASC，等待处理

---

## 阶段总览

| 阶段 | 计划文档 | 状态 | 说明 |
|------|----------|------|------|
| Phase 1：PTCore | `2026-04-03-phase1-foundation-ptcore.md` | ✅ 完成 | 数据模型、GRDB、BookDAO、45 个测试 |
| Phase 2：PTNetworking | `2026-04-03-phase2-networking-ptnetworking.md` | ✅ 完成 | NetworkClient、SSEParser、WebDAVClient |
| Phase 3：PTReader | `2026-04-03-phase3-reader-ptreader.md` | ✅ 完成 | PDFContentBridge、ReadingPreferences、TTSService |
| Phase 4：PTUI | `2026-04-03-phase4-ui-ptui.md` | ✅ 完成 | MorandiPalette、AppSpacing、PTButton、PTCard |
| Phase 5：PTAIServices | `2026-04-03-phase5-ai-ptaiservices.md` | 🔄 进行中 | OpenAI ✅；Anthropic ⏳ |
| Phase 6：PTFeatures | `2026-04-03-phase6-features-ptfeatures.md` | 🔄 进行中 | ViewModel 层 ✅；SwiftUI Views 待合并 |
| 书籍导入 + PDF 阅读器 | `2026-04-04-book-import-pdf-reader.md` | ✅ 完成 | 全功能 BookshelfScreen + PDFReaderView |
| Phase 7：Settings / Notes / Stats UI | `2026-04-04-phase7-settings-notes-statistics-ui.md` | ⏳ 待实现 | — |
| Phase 8：EPUB 阅读器 | `2026-04-04-phase8-epub-reader.md` | ⏳ 待实现 | Readium SDK 集成 |
| Phase 9：AI Chat UI | `2026-04-04-phase9-ai-chat-ui.md` | ⏳ 待实现 | 聊天界面、Provider 切换 |
| Phase 10：AI 工具（46 个） | `2026-04-04-phase10-ai-tools.md` | ⏳ 待实现 | 书架/笔记/搜索/记忆工具 |
| Phase 11：Papers 页 | `2026-04-04-phase11-papers-page.md` | ⏳ 待实现 | 学术论文 Feed |
| Phase 12：平台集成 | `2026-04-04-phase12-platform-integration.md` | ⏳ 待实现 | Share Extension、App Intents、WebDAV 同步 |

---

## 代码质量修复（2026-04-06）

经过系统代码审核，发现并修复了以下 13 个问题：

### ✅ Critical（4 项）

| # | 问题 | 修复方案 |
| --- | --- | --- |
| C1 | ToolOrchestrator 数据竞争 | 改为 `actor`，tools 快照传入 TaskGroup |
| C2 | ViewModel `@unchecked Sendable` 不安全 | 全部 6 个 ViewModel 改为 `@MainActor` |
| C3 | PDFContentBridge 包裹非线程安全 PDFDocument | 改为 `@MainActor` |
| C4 | OpenAIProvider 吞掉 Keychain 错误 | `try?` 改为 `do/catch`，区分"无 Key"和"访问失败" |

### ✅ Warning（9 项）

| # | 问题 | 修复方案 |
| --- | --- | --- |
| W1 | PDFReaderView Coordinator 未移除 NotificationCenter observer | 添加 `deinit`（iOS + macOS 各自） |
| W2 | OAIToolParameters 类型简单无法表示 JSON Schema | 新增 `OAIPropertySchema`（type/description/enum） |
| W3+W4 | SSEParser 逐字节解析，多字节 UTF-8 乱码 | 改用 `AsyncBytes.lines`，正确处理 CJK/emoji |
| W5 | 数据库缺少外键约束和索引 | 添加 6 个 FK + 6 个索引（notes/reading_time/book_tags） |
| W6 | BookDAO.search LIKE 通配符注入 | 转义 `%`/`_`/`\` |
| W7 | BookImportService MD5 全量读内存 | 改为 1 MB 分块流式计算 |
| W8 | Security-scoped resource 可能泄漏 | ContentView 改用 `defer` 确保释放 |
| W9 | ConversationTree 强制解包 | `!` 改为 `if let` |

---

## 当前源文件状态

### ✅ PTCore（45 个测试全部通过）

| 文件 | 内容 |
|------|------|
| `Models/Book.swift` | 书籍模型，CodingKeys 与 Flutter DB 兼容 |
| `Models/BookNote.swift` | 笔记/高亮/书签 |
| `Models/BookStyle.swift` | 每本书的阅读样式 |
| `Models/ReadTheme.swift` | 阅读主题（背景/文字颜色） |
| `Models/ReadingTime.swift` | 每日阅读时长追踪 |
| `Models/Tag.swift`, `BookTag.swift` | 标签系统 |
| `Models/TbGroup.swift` | 书架文件夹层级 |
| `Database/AppDatabase.swift` | GRDB + Schema v7 + FK 约束 + 6 个索引 |
| `Database/BookDAO.swift` | CRUD + LIKE 转义搜索 + MD5 去重 |
| `Database/BookNoteDAO.swift` | 笔记查询 |
| `Database/BookStyleDAO.swift` | 样式持久化 |
| `Database/GroupDAO.swift` | 书架文件夹 |
| `Database/ReadThemeDAO.swift` | 主题持久化 |
| `Database/ReadingTimeDAO.swift` | 阅读时长记录 |
| `Database/TagDAO.swift` | 标签管理 |
| `Config/AppConfig.swift` | UserDefaults 包装 |
| `Config/KeychainService.swift` | API Key 安全存储 |
| `Utils/DateFormatting.swift` | 日期格式化工具 |

### ✅ PTNetworking（SSE 已修复 UTF-8）

| 文件 | 内容 |
|------|------|
| `HTTP/NetworkClient.swift` | URLSession actor |
| `HTTP/Endpoint.swift` | 请求描述符 |
| `HTTP/NetworkError.swift` | 网络错误类型 |
| `SSE/SSEParser.swift` | `AsyncBytes.lines` 正确 UTF-8 解析 |
| `SSE/SSEEvent.swift` | SSE 事件结构 |
| `WebDAV/WebDAVClient.swift` | PROPFIND/GET/PUT/DELETE |
| `PaperTok/PaperTokAPI.swift` | REST 客户端 |

### ✅ PTReader（@MainActor 安全）

| 文件 | 内容 |
|------|------|
| `PDF/PDFContentBridge.swift` | `@MainActor`，PDFKit 安全 |
| `PDF/PDFChapter.swift` | 章节结构 |
| `Common/BookContentBridge.swift` | 统一内容协议 |
| `Common/ContentSearchResult.swift` | 搜索结果模型 |
| `Common/HighlightStyle.swift` | Morandi 标注样式 |
| `Preferences/ReadingPreferences.swift` | @Observable 偏好 |
| `TTS/TTSService.swift` | AVSpeechSynthesizer 封装 |

### ✅ PTUI

| 文件 | 内容 |
|------|------|
| `Theme/MorandiPalette.swift` | 12 色 + 语义色 + 暗色 |
| `Theme/AppSpacing.swift` | 间距系统 |
| `Theme/AppTypography.swift` | 字体规范 |
| `Components/PTButton.swift` | 四种样式 |
| `Components/PTCard.swift` | 卡片容器 |
| `Components/PTChip.swift` | 标签 Chip |
| `Components/PTSearchBar.swift` | 搜索栏 |
| `Modifiers/PTModifiers.swift` | `.ptCard()` 等 |

### 🔄 PTAIServices（OpenAI 完成；Anthropic 待实现）

| 文件 | 状态 | 内容 |
|------|------|------|
| `Providers/ChatModelProvider.swift` | ✅ | 协议 + `ToolDefinition`（含参数 Schema） |
| `Providers/ModelCapability.swift` | ✅ | 能力枚举 |
| `Providers/ProviderError.swift` | ✅ | 类型化错误 |
| `Providers/OpenAIProvider.swift` | ✅ | SSE/tools/vision/自定义 base URL；Keychain 错误传播 |
| `Providers/AnthropicProvider.swift` | ❌ 待实现 | Messages API + extended thinking + tool use |
| `Chat/ChatMessage.swift` | ✅ | 消息类型 |
| `Chat/ConversationTree.swift` | ✅ | 分支对话树；移除强制解包 |
| `Chat/TokenUsage.swift` | ✅ | Token 计数 |
| `Tools/AITool.swift` | ✅ | 工具协议 |
| `Tools/ToolContext.swift` | ✅ | 执行上下文 |
| `Tools/ToolOrchestrator.swift` | ✅ | `actor`，并发安全 |
| `Translation/AITranslationService.swift` | ✅ | AI 翻译封装 |

### 🔄 PTFeatures（ViewModel 完成；SwiftUI Views 待合并）

| 文件 | 状态 | 内容 |
|------|------|------|
| `Navigation/AppTab.swift` | ✅ | 6 个 Tab |
| `Bookshelf/BookshelfViewModel.swift` | ✅ | `@MainActor`，加载/搜索/排序/删除/导入 |
| `Bookshelf/BookImportService.swift` | ✅ | MD5 流式 + 文件复制 + PDF 元数据 |
| `Reader/ReaderViewModel.swift` | ✅ | `@MainActor`，PDF 加载/翻页/TOC/进度 |
| `Reader/PDFReaderView.swift` | ✅ | PDFKit wrapper + deinit 修复 |
| `Notes/NotesViewModel.swift` | ✅ | `@MainActor` |
| `Statistics/StatisticsViewModel.swift` | ✅ | `@MainActor` |
| `AIChat/AIChatViewModel.swift` | ✅ | `@MainActor` |
| `Settings/SettingsViewModel.swift` | ✅ | `@MainActor` |
| Notes SwiftUI View | ⏳ 待合并 | worktree 中 |
| Statistics SwiftUI View | ⏳ 待合并 | worktree 中 |
| Settings SwiftUI View | ⏳ 待合并 | worktree 中 |
| AIChat SwiftUI View | ⏳ 待合并 | worktree 中 |

### ✅ App Target

| 文件 | 内容 |
|------|------|
| `PaperTokReaderApp.swift` | `@main` 入口，GRDB 初始化 |
| `ContentView.swift` | MainTabView + BookshelfScreen + PDFReaderView；security-scoped `defer` 修复 |
| `Resources/Assets.xcassets/AppIcon.appiconset/` | 1024×1024 图标 |
| `Entitlements/iOS.entitlements` | App Groups + Keychain |

### ✅ 构建基础设施

| 文件 | 内容 |
|------|------|
| `fastlane/Fastfile` | TestFlight 自动化（build number 单调递增） |
| `fastlane/Appfile` | App 标识 |
| `fastlane/Pluginfile` | 插件占位 |
| `Gemfile` / `Gemfile.lock` | fastlane 2.228.0 |
| `project.yml` | XcodeGen 配置 |

---

## 测试覆盖汇总

| Package | 测试数 | 状态 |
|---------|--------|------|
| PTCore | 45 | ✅ 全部通过 |
| PTNetworking | ~12 | ✅ 全部通过 |
| PTReader | ~8 | ✅ 全部通过 |
| PTUI | 5 | ✅ 全部通过 |
| PTAIServices | 15 | ✅ 全部通过 |
| PTFeatures | 12 | ✅ 全部通过 |
| **合计** | **~97** | ✅ 全部通过 |

---

## TestFlight 历史

| 版本 | Build | 日期 | 说明 |
| --- | --- | --- | --- |
| 1.0.0 | 6408 | 2026-04-06 | 首个原生 Swift 构建；Phase 1-6 基础 + PDF 阅读器 |

---

## 下一步优先级

### 🔴 高优先级

1. **AnthropicProvider**（Messages API + SSE + extended thinking + tool use）
2. **合并 SwiftUI Views**（Notes、Statistics、Settings、AIChat 在 worktree）

### 🟡 中优先级

1. **Phase 7：Settings / Notes / Statistics / AIChat 完整 UI**
2. **Phase 8：EPUB 阅读器**（Readium Swift SDK 集成）

### 🟢 后续规划

1. **Phase 9：AI Chat UI**（消息气泡、Provider 切换、流式显示）
2. **Phase 10：46 个 AI 工具**（书架/笔记/搜索/记忆/文档工具）
3. **Phase 11：Papers 学术论文 Feed**
4. **Phase 12：平台集成**（Share Extension、App Intents、WebDAV 同步、macOS 优化）

---

## 已知技术债

| 问题 | 影响 | 优先级 |
| --- | --- | --- |
| AnthropicProvider 未实现 | AI 功能只有 OpenAI 提供商 | 🔴 高 |
| worktree SwiftUI Views 未合并 | 书架以外 4 个 tab 显示占位符 | 🟡 中 |
| Phase 6 缺少 Highlights/Bookmarks UI | 笔记功能仅后端，无 UI | 🟡 中 |
| `eraseDatabaseOnSchemaChange=true` 在 DEBUG | 开发时 Schema 变化会清空数据 | ℹ️ 低（预期行为） |
| UserDefaults 未使用 App Group（AppConfig 只定义 suiteName） | 跨扩展共享数据未启用 | ℹ️ 低 |

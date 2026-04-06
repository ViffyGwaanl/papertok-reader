# Swift 原生迁移 — 整体进度追踪

**最后更新：** 2026-04-06
**分支：** `swift-native`

---

## 阶段总览

| 阶段 | 计划文档 | 状态 | 说明 |
|------|----------|------|------|
| Phase 1：PTCore | `2026-04-03-phase1-foundation-ptcore.md` | ✅ 完成 | 数据模型、GRDB、BookDAO、所有测试 |
| Phase 2：PTNetworking | `2026-04-03-phase2-networking-ptnetworking.md` | ✅ 完成 | NetworkClient、SSEParser、WebDAVClient |
| Phase 3：PTReader | `2026-04-03-phase3-reader-ptreader.md` | ✅ 完成 | PDFContentBridge、ReadingPreferences、TTSService |
| Phase 4：PTUI | `2026-04-03-phase4-ui-ptui.md` | ✅ 完成 | MorandiPalette、AppSpacing、PTButton、PTCard |
| Phase 5：PTAIServices | `2026-04-03-phase5-ai-ptaiservices.md` | 🔄 进行中 | 基础协议已完成；OpenAIProvider ✅；AnthropicProvider ⏳ |
| Phase 6：PTFeatures | `2026-04-03-phase6-features-ptfeatures.md` | 🔄 进行中 | ViewModel 层 ✅；部分 UI 在 worktree ⏳ |
| 书籍导入 + PDF 阅读器 | `2026-04-04-book-import-pdf-reader.md` | ✅ 完成 | 全功能书架导入 UI + PDFKit 阅读器 |
| Phase 8：EPUB 阅读器 | `2026-04-04-phase8-epub-reader.md` | ⏳ 待实现 | Readium SDK 集成 |
| Phase 9：AI Chat UI | `2026-04-04-phase9-ai-chat-ui.md` | ⏳ 待实现 | 聊天界面、Provider 切换 |
| Phase 10：AI 工具（46 个） | `2026-04-04-phase10-ai-tools.md` | ⏳ 待实现 | 书架/笔记/搜索/记忆工具 |
| Phase 11：Papers 页 | `2026-04-04-phase11-papers-page.md` | ⏳ 待实现 | 学术论文 Feed |
| Phase 12：平台集成 | `2026-04-04-phase12-platform-integration.md` | ⏳ 待实现 | Share Extension、App Intents、WebDAV 同步 |

---

## 当前 swift-native 分支实际文件状态

### ✅ PTCore（45 个测试）

| 文件 | 内容 |
|------|------|
| `Models/Book.swift` | 书籍模型，CodingKeys 与 Flutter 数据库兼容 |
| `Models/BookNote.swift` | 笔记/高亮/书签 |
| `Models/BookStyle.swift` | 每本书的阅读样式 |
| `Models/ReadTheme.swift` | 阅读主题（背景/文字颜色） |
| `Models/ReadingTime.swift` | 每日阅读时长追踪 |
| `Models/Tag.swift`, `BookTag.swift` | 标签系统 |
| `Models/TbGroup.swift` | 书架文件夹层级 |
| `Database/AppDatabase.swift` | GRDB 初始化 + Schema v7 迁移 |
| `Database/BookDAO.swift` | CRUD + 搜索 + 软删除 + **fetchByMD5**（去重） |
| `Database/BookNoteDAO.swift` | 笔记查询 |
| `Database/BookStyleDAO.swift` | 样式持久化 |
| `Database/GroupDAO.swift` | 书架文件夹 |
| `Database/ReadThemeDAO.swift` | 主题持久化 |
| `Database/ReadingTimeDAO.swift` | 阅读时长记录 |
| `Database/TagDAO.swift` | 标签管理 |
| `Config/AppConfig.swift` | UserDefaults 包装 |
| `Config/KeychainService.swift` | API Key 安全存储 |
| `Utils/DateFormatting.swift` | 日期格式化工具 |

### ✅ PTNetworking

| 文件 | 内容 |
|------|------|
| `HTTP/NetworkClient.swift` | URLSession actor，支持 JSON/raw/上传/下载/bytes |
| `HTTP/Endpoint.swift` | 请求描述符（URL、方法、头、体） |
| `HTTP/NetworkError.swift` | 网络错误类型 |
| `SSE/SSEParser.swift` | AsyncThrowingStream 事件解析 |
| `SSE/SSEEvent.swift` | SSE 事件结构 |
| `WebDAV/WebDAVClient.swift` | PROPFIND/GET/PUT/DELETE |
| `PaperTok/PaperTokAPI.swift` | PaperTok REST 客户端 |

### ✅ PTReader

| 文件 | 内容 |
|------|------|
| `PDF/PDFContentBridge.swift` | PDFKit 文本提取 + OCR 回退 + 目录解析 |
| `PDF/PDFChapter.swift` | 章节结构 + 页面范围 href |
| `Common/BookContentBridge.swift` | 统一内容访问协议（EPUB/PDF） |
| `Common/ContentSearchResult.swift` | 搜索结果模型 |
| `Common/HighlightStyle.swift` | Morandi 色系标注样式 |
| `Preferences/ReadingPreferences.swift` | 字体/主题/翻页模式偏好（@Observable） |
| `TTS/TTSService.swift` | AVSpeechSynthesizer 封装 |

### ✅ PTUI

| 文件 | 内容 |
|------|------|
| `Theme/MorandiPalette.swift` | Morandi 色系（12 色 + 语义色 + 暗色模式） |
| `Theme/AppSpacing.swift` | 间距常量系统 |
| `Theme/AppTypography.swift` | 字体规范 |
| `Components/PTButton.swift` | 四种样式按钮（primary/secondary/destructive/ghost） |
| `Components/PTCard.swift` | 卡片容器 |
| `Components/PTChip.swift` | 标签 Chip |
| `Components/PTSearchBar.swift` | 搜索栏 |
| `Modifiers/PTModifiers.swift` | `.ptCard()`, `.ptSectionHeader()`, `.ptDivider()` |

### 🔄 PTAIServices（部分完成）

| 文件 | 状态 | 内容 |
|------|------|------|
| `Providers/ChatModelProvider.swift` | ✅ | 协议 + ChatRequest/Response/StreamChunk |
| `Providers/ModelCapability.swift` | ✅ | 能力枚举（chat/vision/toolCalling/thinking/streaming） |
| `Providers/ProviderError.swift` | ✅ | 类型化错误（auth/rateLimited/serverError 等） |
| `Providers/OpenAIProvider.swift` | ✅ | 完整实现（SSE/tools/自定义 base URL） |
| `Providers/AnthropicProvider.swift` | ⏳ | **待实现**（Messages API + extended thinking + tool use） |
| `Chat/ChatMessage.swift` | ✅ | 消息类型系统 |
| `Chat/ConversationTree.swift` | ✅ | 分支对话树 |
| `Chat/TokenUsage.swift` | ✅ | Token 计数 + 费用估算 |
| `Tools/AITool.swift` | ✅ | 工具协议 + 分类 + 风险等级 |
| `Tools/ToolContext.swift` | ✅ | 执行上下文 |
| `Tools/ToolOrchestrator.swift` | ✅ | 并发工具执行引擎 |
| `Translation/AITranslationService.swift` | ✅ | AI 翻译封装 |

### 🔄 PTFeatures（部分完成）

| 文件 | 状态 | 内容 |
|------|------|------|
| `Navigation/AppTab.swift` | ✅ | 6 个 Tab 枚举（Papers/Bookshelf/Notes/Stats/AI/Settings） |
| `Bookshelf/BookshelfViewModel.swift` | ✅ | 加载/搜索/排序/删除/**importBook** |
| `Bookshelf/BookImportService.swift` | ✅ | 文件复制/MD5 去重/PDF 元数据/封面生成/DB 保存 |
| `Reader/ReaderViewModel.swift` | ✅ | PDF 加载/翻页/目录/进度持久化 |
| `Reader/PDFReaderView.swift` | ✅ | PDFKit UIViewRepresentable（iOS）/ NSViewRepresentable（macOS） |
| `Notes/NotesViewModel.swift` | ✅ | 笔记搜索/按书筛选 |
| `Statistics/StatisticsViewModel.swift` | ✅ | 阅读统计 |
| `AIChat/AIChatViewModel.swift` | ✅ | ConversationTree 管理，发送消息 stub |
| `Settings/SettingsViewModel.swift` | ✅ | AppConfig 读写 |
| Notes SwiftUI View | ⏳ 待合并 | 在 claude/ worktree 中已完成 |
| Statistics SwiftUI View | ⏳ 待合并 | 在 claude/ worktree 中已完成 |
| Settings SwiftUI View | ⏳ 待合并 | 在 claude/ worktree 中已完成 |
| AIChat SwiftUI View | ⏳ 待合并 | 在 claude/ worktree 中已完成 |

### ✅ App Target

| 文件 | 内容 |
|------|------|
| `PaperTokReaderApp.swift` | `@main` 入口，GRDB 数据库初始化 |
| `ContentView.swift` | MainTabView + **BookshelfScreen**（含导入按钮、书架列表、进度条） + **PDFReaderView** 跳转 |
| `Resources/Assets.xcassets/AppIcon.appiconset/` | TestFlight 1024×1024 图标 |
| `Entitlements/iOS.entitlements` | App Groups + Keychain |

---

## 测试覆盖汇总

| Package | 测试数 | 状态 |
|---------|--------|------|
| PTCore | 45 | ✅ 全部通过 |
| PTNetworking | ~12 | ✅ 全部通过 |
| PTReader | ~8 | ✅ 全部通过 |
| PTUI | 2 | ✅ 全部通过 |
| PTAIServices | ~15 | ✅ 全部通过 |
| PTFeatures | 12 | ✅ 全部通过 |

---

## 下一步优先级

1. 🔴 **AnthropicProvider**（Messages API + SSE + extended thinking + tool use）
2. 🔴 **OpenAIProvider / AnthropicProvider 单元测试**（请求序列化、SSE 解析）
3. 🟡 **合并 Notes / Statistics / Settings / AIChat SwiftUI View**
4. 🟡 **EPUB 阅读器**（Phase 8，Readium SDK）
5. 🟢 **AI Chat UI**（Phase 9）
6. 🟢 **46 个 AI 工具**（Phase 10）

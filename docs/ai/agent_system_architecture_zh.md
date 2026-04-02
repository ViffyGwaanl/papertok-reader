# PaperTok Reader — AI Agent 系统架构与优化记录

> 更新时间：2026-04-01
> 状态：Phase 0-3 已完成（全部集成），Phase 4 计划中

---

## 1. 架构总览

```
用户输入
  │
  ▼
AiChat (Riverpod, keepAlive)
  │── PromptBudgetingService (token 预算)
  │── ConversationCompressor (LLM 摘要压缩) ← new
  │── LangchainAiRegistry
  │     ├── 场景过滤 (AiToolScene: reading/library/global/system)
  │     ├── 工具按字母序排列 (prompt cache)
  │     └── 构建 LangchainPipeline (model + tools + systemMessage)
  │
  ▼
CancelableLangchainRunner.streamAgent()
  │── ToolApprovalDelegate (回调, 不依赖 Flutter UI) ← refactored
  │── SSE 心跳 (15s, 防移动端代理断连) ← new
  │── ToolOrchestrator (并发/串行分区执行) ← new
  │── AiUsageTracker (token/成本追踪) ← new
  │
  ▼
RepositoryTool<I,O>.run()
  │── BookContentCache (LRU, MD5 变更检测) ← new
  │── AnnotationLedger (标注台账) ← new
  │── JsonRepair (修复截断 JSON) ← new
  │
  ▼
Stream<String> → AiChatStream Widget → 渲染
```

---

## 2. 已完成的优化（2026-04-01）

### Phase 0: 架构修复

| 编号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| P0-A | **Service/UI 解耦** — `CancelableLangchainRunner` 不再依赖 `flutter/material.dart`；工具审批通过 `ToolApprovalDelegate` 回调注入 | `lib/service/ai/tool_approval_delegate.dart` (new) `lib/widgets/ai/tool_approval_dialog.dart` (new) `lib/service/ai/langchain_runner.dart` (mod) `lib/service/ai/index.dart` (mod) | ✅ Done |
| P0-B | **工具字母序排列** — 稳定 prompt cache 命中率 | `lib/service/ai/langchain_registry.dart` (mod) | ✅ Done |
| P0-C | **SSE 心跳** — 15s 周期，防止移动端代理关闭空闲 SSE 流 | `lib/service/ai/langchain_runner.dart` (mod) | ✅ Done |

### Phase 1: 核心增强

| 编号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| P1-A | **富 AiToolContext** — 注入 `currentBookId`, `currentBookTitle`, `currentChapterId`, `selectedText`, `conversationId`, `locale` 等 | `lib/service/ai/tools/ai_tool_registry.dart` (mod) | ✅ Done |
| P1-B | **场景感知工具过滤** — `AiToolScene` 枚举 + `_sceneOverrides` 元数据表；阅读时不注入 calendar/reminders，书架时不注入 chapter content | `lib/enums/ai_tool_scene.dart` (new) `lib/service/ai/tools/ai_tool_registry.dart` (mod) `lib/service/ai/langchain_registry.dart` (mod) | ✅ Done |
| P1-C | **并发工具执行引擎** — `ToolOrchestrator` 实现 Claude Code 风格的并发/串行分区调度 + `_Semaphore` 限流 | `lib/service/ai/tool_orchestrator.dart` (new) | ✅ Done |
| P1-D | **CreateHighlightTool + CreateNoteTool** — 写工具，支持 AI 在书内创建高亮和笔记 | `lib/service/ai/tools/create_highlight_tool.dart` (new) `lib/service/ai/tools/create_note_tool.dart` (new) `lib/service/ai/tools/input/create_highlight_input.dart` (new) `lib/service/ai/tools/input/create_note_input.dart` (new) | ✅ Done |

### Phase 2: 上下文智能化 + 基础设施

| 编号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| P2-A | **LLM 摘要式上下文压缩** — 替代简单截断；85% 上下文使用率触发；熔断机制（3 次失败后降级） | `lib/service/ai/conversation_compressor.dart` (new) | ✅ Done |
| P2-B | **章节内容缓存** — LRU (20 slots) + MD5 变更检测；避免同一章节反复传输 | `lib/service/ai/book_content_cache.dart` (new) | ✅ Done |
| P2-C | **动态 max_tokens 策略** — 默认 8K（覆盖 >99% 响应）；触及上限自动升级到 32K | `lib/service/ai/max_tokens_strategy.dart` (new) | ✅ Done |
| P2-D | **JSON 修复层** — 处理 LLM 截断 JSON（未闭合引号/括号/尾逗号/markdown 代码块） | `lib/service/ai/tools/util/json_repair.dart` (new) | ✅ Done |
| P2-E | **Annotation Ledger** — 追踪 AI 当前对话中创建的高亮/笔记，注入 system prompt 防重复标注 | `lib/service/ai/annotation_ledger.dart` (new) | ✅ Done |
| P2-F | **Token/成本追踪** — 输入/输出/缓存 token 计数 + 内置 5 家模型定价 | `lib/service/ai/ai_usage_tracker.dart` (new) | ✅ Done |

---

## 3. 新文件清单

```
lib/
├── enums/
│   └── ai_tool_scene.dart                    ← 工具场景枚举
├── service/ai/
│   ├── tool_approval_delegate.dart           ← 审批回调抽象
│   ├── tool_orchestrator.dart                ← 并发执行引擎
│   ├── conversation_compressor.dart          ← LLM 摘要压缩
│   ├── book_content_cache.dart               ← 章节缓存
│   ├── max_tokens_strategy.dart              ← 动态 max_tokens
│   ├── annotation_ledger.dart                ← 标注台账
│   ├── ai_usage_tracker.dart                 ← 成本追踪
│   └── tools/
│       ├── create_highlight_tool.dart        ← 高亮创建工具
│       ├── create_note_tool.dart             ← 笔记创建工具
│       ├── input/
│       │   ├── create_highlight_input.dart
│       │   └── create_note_input.dart
│       └── util/
│           └── json_repair.dart              ← JSON 修复
└── widgets/ai/
    └── tool_approval_dialog.dart             ← UI 侧审批对话框
```

---

## 4. 工具场景分配表

| 场景 | 工具 | 数量 |
|------|------|------|
| `global` | calculator, current_time, fetch_url, memory_* | 7 |
| `reading` | book_content_search, current_book_toc, current_chapter_content, chapter_content_by_href, current_book_fulltext, current_reading_metadata, resolve_cfi, semantic_search_current_book, mindmap, create_highlight, create_note, notes_search | 12 |
| `library` | bookshelf_lookup, bookshelf_organize, notes_search, reading_history, semantic_search_library, tags_list, books_tags_list, apply_book_tags, calendar_*, reminders_*, shortcuts_run | ~25 |

效果：阅读场景 system prompt 从 ~40 个工具定义降到 ~19 个，约节省 50% 工具 token。

---

## 5. 并发安全标记

| 类别 | 工具 | isConcurrencySafe |
|------|------|-------------------|
| 只读 | 所有搜索/查询/TOC/metadata 工具 | `true` (默认) |
| 写入 | bookshelf_organize, apply_book_tags, create_highlight, create_note, memory_append, memory_replace | `false` |
| 破坏 | calendar write/delete, reminders write/delete, shortcuts_run | `false` |

---

## 6. 已完成：Phase 3 集成（2026-04-01）

所有 Phase 2 创建的模块已接入主 agent 执行流程：

| 编号 | 任务 | 集成位置 | 状态 |
|------|------|----------|------|
| P3-A | **ToolOrchestrator → streamAgent** | `langchain_runner.dart` 工具循环重构为两阶段：审批(顺序) → 执行(并发/串行分区) | ✅ Done |
| P3-B | **ConversationCompressor → index.dart** | `_generateStream()` 中 agent 模式下，上下文 >85% 时 LLM 摘要压缩 | ✅ Done |
| P3-C | **BookContentCache → chapter_content_by_href** | `chapter_content_by_href_tool.dart` 使用 LRU 缓存，重复请求返回 `[unchanged]` | ✅ Done |
| P3-D | **AiUsageTracker → runner** | `streamAgent()` 每次 API 调用后记录 token；每次工具执行后记录 tool call | ✅ Done |
| P3-E | **AnnotationLedger → write tools + prompt** | `create_highlight/create_note` 保存后写入 ledger；system prompt 追加 ledger section | ✅ Done |
| P3-F | **MaxTokensStrategy → streamAgent** | 默认 8K cap + `finishReason` 检测 → 自动升级到 32K | ✅ Done |
| P3-G | **JsonRepair → _hydrateToolArguments** | JSON 解析失败时尝试 `repairJson()` 修复截断 | ✅ Done |

### 修改的核心文件

| 文件 | 改动内容 |
|------|----------|
| `langchain_runner.dart` | +3 import；+`_maxTokensEscalated` 字段；streamAgent 添加 `usageTracker` 参数；工具循环重构为两阶段（审批 → 并发执行）；`_hydrateToolArguments` 添加 JSON repair；`cancel()` 重置 escalation |
| `index.dart` | +2 import；+session-level `_sessionTrackers` / `_compressionFailures`；agent 路径添加 compression check；`streamAgent` 传入 tracker |
| `langchain_registry.dart` | +1 import；`_buildAgentSystemMessage` 添加 `annotationLedger` 参数并注入 prompt |
| `ai_tool_registry.dart` | `AiToolContext` 添加 `bookContentCache` + `annotationLedger` 字段 |
| `chapter_content_by_href_tool.dart` | 添加 `cache` 参数；`run()` 中检查 `isUnchanged` 并返回 `[unchanged]` |
| `create_highlight_tool.dart` | 添加 `ledger` 参数；保存后调用 `ledger.addHighlight()` |
| `create_note_tool.dart` | 添加 `ledger` 参数；保存后调用 `ledger.addNote()` |

---

## 7. 未来计划（Phase 4）

### 差异化功能（远期）

| 编号 | 任务 | 说明 | 优先级 |
|------|------|------|--------|
| P4-0 | **Sub-Agent 系统** | `SpawnResearchAgentTool`：主 Agent 生成轻量子 Agent（explore / summarize / verify），各自独立上下文。 | P2 |
| P4-A | **Skills 系统** | 可安装提示模板（YAML 格式）：`paper_analyzer`, `flashcard_generator`, `debate_partner` 等。用户可自定义和导入。 | P3 |
| P4-B | **研讨会模式** | 多视角 AI 讨论：针对同一问题生成 3 个不同立场的 AI 回复（批判/支持/中立），汇总后呈现。借鉴 OpenMAIC 的 Director-Agent 分离架构。 | P4 |
| P4-C | **KAIROS 主动阅读助手** | 监听阅读进度事件；当用户在同一段落停留 >30s 时主动提问；完成一章后自动显示摘要卡片。可配置主动程度。 | P4 |
| P4-D | **离线 Embedding** | 集成本地 embedding 模型作为离线 fallback，支持增量索引。 | P4 |
| P4-E | **Web Search Tool** | 基于搜索引擎的 `web_search` 工具，可配置 Google Scholar / Semantic Scholar API。 | P3 |

---

## 8. 设计参考

本次优化参考了以下项目的架构设计：

### Claude Code 2.1.88（源码分析报告 `参考/claude-code-2.1.88-深度分析报告.md`）
- **StreamingToolExecutor**: 流式响应中一旦 tool_use JSON 完整即刻执行
- **toolOrchestration**: `isConcurrencySafe` 并发分区策略
- **autoCompact**: LLM 摘要式上下文压缩 + 熔断器
- **prompt cache**: 工具定义排序稳定性
- **dynamic max_tokens**: 8K 默认 → 64K 升级
- **AgentTool / Sub-agents**: 探索型/验证型/计划型子代理
- **Skills 系统**: 轻量级可安装能力扩展

### OpenMAIC (THU-MAIC)
- **Director-Agent 分离**: 轻量路由节点 + 独立 persona agent
- **allowedActions 能力门控**: 角色级工具权限
- **SSE 心跳 15s**: 防止中间代理断连
- **JSON 修复层**: LLM 结构化输出容错
- **Whiteboard Ledger**: 标注台账概念 → AnnotationLedger

### claw-code (instructkr)
- **ToolPermissionContext deny-list**: 工具审批模式
- **Session compaction with turn threshold**: 按轮次而非 token 触发压缩
- **Typed streaming event protocol**: 结构化事件流
- **Fork/Resume sub-agents**: 子 agent 生命周期管理

---

## 9. 与旧计划文档的对照

旧文档 `参考/PaperTok_Agent_Implementation_Plan.md` 提出了 6 个 Phase，以"从零构建 Agent 系统"为前提。实际实现已走了 LangChain 路线，大部分 Phase 1-2 的目标已由 LangChain + 现有工具系统实现。

| 旧计划 | 当前状态 |
|--------|----------|
| Phase 0: 代码审计 | ✅ 审计完成（未生成独立文档，直接用于指导开发） |
| Phase 1: 自研 AgentTool/ToolRegistry/AgentLoop | ✅ 由 LangChain 实现；本次补充了 ToolOrchestrator / ToolApprovalDelegate / AiToolScene |
| Phase 2: 核心工具集 | ✅ 已有 40+ 工具；本次补充 CreateHighlight + CreateNote |
| Phase 3: 系统提示与上下文管理 | ✅ 已有 system prompt 生成；本次补充 ConversationCompressor |
| Phase 4: UI 集成 | ✅ 已有 tool_step_tile / ai_chat_stream；成本追踪 UI 待集成 |
| Phase 5: 上下文智能管理 | ✅ 本次补充 BookContentCache / MaxTokensStrategy |
| Phase 6: 测试与 QA | ⏳ 工具单元测试仍需补充 |

**旧文档建议保留在 `参考/` 目录作为历史记录，不再作为执行指南。**

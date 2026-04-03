# PaperTok Reader — AI Agent 系统架构与优化记录

> 更新时间：2026-04-03
> 状态：Phase 0-4 已完成（含设置 UI + L10n + Bug 修复），Phase 5 计划中

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
  │── ToolApprovalDelegate (回调, 不依赖 Flutter UI)
  │── SSE 心跳 (15s, 防移动端代理断连)
  │── ToolOrchestrator (并发/串行分区执行)
  │── AiUsageTracker (token/成本追踪) → UI 显示
  │── SubAgentRunner (子 Agent 独立上下文) ← P4 new
  │
  ▼
RepositoryTool<I,O>.run()
  │── BookContentCache (LRU, MD5 变更检测)
  │── AnnotationLedger (标注台账)
  │── JsonRepair (修复截断 JSON)
  │── WebSearchTool (DDG + Serper) ← P4 new
  │── SpawnSubAgentTool (研究/总结/验证) ← P4 new
  │
  ▼
Stream<String> → AiChatStream Widget → 渲染
  │── Token 使用量显示 (aiChatUsageSummaryProvider) ← P4 new
  │── Skills 选择器 (技能面板) ← P4 new
  │── KAIROS 提示 (主动阅读助手) ← P4 new
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
| `global` | calculator, current_time, fetch_url, web_search, spawn_sub_agent, memory_* | 9 |
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
| 特殊 | spawn_sub_agent（串行，防止并发子 Agent 资源竞争） | `false` |

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

## 7. 已完成：Phase 4 差异化功能（2026-04-01）

| 编号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| P4-UI | **Token/成本 UI 显示** — 流式结束后在输入框上方展示 token 用量和费用估算 | `providers/ai_chat.dart` (mod) `widgets/ai/ai_chat_stream.dart` (mod) | ✅ Done |
| P4-E | **Web Search Tool** — 双策略搜索：Serper API (配置 Key) / DuckDuckGo Lite (免 Key fallback)；HTML 解析提取 title+url+snippet | `tools/web_search_tool.dart` (new) `tools/input/web_search_input.dart` (new) | ✅ Done |
| P4-0 | **Sub-Agent 系统** — `SubAgentRunner` 复用 `CancelableLangchainRunner` 创建独立上下文子 Agent；3 种类型：`research`/`summarize`/`verify`，各自受限工具集；禁止递归；max 15 步 | `sub_agent_runner.dart` (new) `tools/spawn_sub_agent_tool.dart` (new) `tools/input/spawn_sub_agent_input.dart` (new) | ✅ Done |
| P4-A | **Skills 系统** — 6 个内置技能模板（paper_analyzer / flashcard_generator / debate_partner / vocab_extractor / reading_companion / seminar_mode）；通过 Prefs 持久化激活状态；system prompt 动态追加技能指令 | `skills/ai_skill.dart` (new) `skills/ai_skill_registry.dart` (new) `langchain_registry.dart` (mod) | ✅ Done |
| P4-B | **研讨会模式** — 作为 Skills 系统中的 `seminar_mode` 技能实现；系统提示强制 3 段式回复：🔴 批判视角 / 🟢 支持视角 / 🔵 综合评估 | 包含在 `skills/ai_skill_registry.dart` | ✅ Done |
| P4-C | **KAIROS 主动阅读助手** — `KairosService` 监听 `currentReadingProvider`；`Timer.periodic(5s)` 检测同一 CFI 停留超阈值（30s/20s/10s，可配级别）；触发浮动 Chip 提示；点击后预填 prompt 打开 AI 聊天 | `kairos/kairos_service.dart` (new) `providers/kairos_provider.dart` (new) `page/reading_page.dart` (mod) | ✅ Done |
| P4-D | **本地/离线 Embedding** — `ai_embeddings_service.dart` 新增 Ollama 本地端点支持（`/api/embeddings` + OpenAI `/v1/embeddings` 双格式）；`isAvailable` 静态检测；Prefs 新增 `localEmbeddingEndpoint` / `localEmbeddingModel` 配置 | `rag/ai_embeddings_service.dart` (mod) `config/shared_preference_provider.dart` (mod) | ✅ Done |

### Phase 4 新文件清单

```
lib/
├── providers/
│   └── kairos_provider.dart                  ← KAIROS 状态
├── service/ai/
│   ├── sub_agent_runner.dart                ← 子 Agent 运行器
│   ├── skills/
│   │   ├── ai_skill.dart                    ← 技能模型
│   │   └── ai_skill_registry.dart           ← 技能注册表 (6 内置)
│   ├── kairos/
│   │   └── kairos_service.dart              ← 主动阅读服务
│   └── tools/
│       ├── web_search_tool.dart             ← 网络搜索工具
│       ├── spawn_sub_agent_tool.dart        ← 子 Agent 工具
│       └── input/
│           ├── web_search_input.dart
│           └── spawn_sub_agent_input.dart
```

### Phase 4 修改的文件

| 文件 | 改动内容 |
|------|----------|
| `providers/ai_chat.dart` | +`aiChatUsageSummaryProvider`；`_finalizeStreaming` 写入 tracker summary |
| `widgets/ai/ai_chat_stream.dart` | +token 用量行 (icon + text)；+技能选择器按钮 (PopupMenuButton) |
| `service/ai/langchain_registry.dart` | +skills import；`_buildPipeline` 读取 `activeAiSkillId` 并传入；`_buildAgentSystemMessage` 追加 skill prompt |
| `service/ai/langchain_ai_config.dart` | +`registryIdentifierForProvider()` 静态方法 |
| `service/ai/tools/ai_tool_registry.dart` | +2 import (web_search, spawn_sub_agent)；`_definitions` 添加两个新工具；`_nonConcurrentTools` 添加 `spawn_sub_agent` |
| `service/rag/ai_embeddings_service.dart` | +`isAvailable` 静态属性；+`_embedViaLocalEndpoint()` 支持 Ollama + OpenAI 格式 |
| `config/shared_preference_provider.dart` | +`activeAiSkillId` / `kairosLevel` / `localEmbeddingEndpoint` / `localEmbeddingModel` 属性 |
| `page/reading_page.dart` | +KairosService 初始化/销毁；+位置更新 feed；+浮动 Chip 提示覆盖层 |

### Phase 4 补充：设置 UI 集成（2026-04-02）

在 AI 设置页面新增"AI Features"区块，为所有 Phase 4 功能提供可发现的配置入口：

| 编号 | 任务 | 文件 | 状态 |
|------|------|------|------|
| P4-S1 | **KAIROS 级别选择器** — 底部弹出选单，4 级选择（Off/Light 30s/Medium 20s/Eager 10s） | `page/settings_page/ai.dart` (mod) | ✅ Done |
| P4-S2 | **Skills 选择器** — 底部弹出选单，列出 6 个内置技能 + None，含图标和描述 | `page/settings_page/ai.dart` (mod) | ✅ Done |
| P4-S3 | **Web Search API Key** — AlertDialog 输入 Serper.dev Key，存入 provider config map | `page/settings_page/ai.dart` (mod) | ✅ Done |
| P4-S4 | **Local Embedding 配置** — AlertDialog 输入端点 URL + 模型名，支持 Clear/Save | `page/settings_page/ai.dart` (mod) | ✅ Done |

### Phase 4 构建发布修复（2026-04-02）

iOS release archive 过程中发现并修复的编译问题：

| 问题 | 修复 |
|------|------|
| `ConversationCompressor` 缺少 `PromptValue` import | 添加 `import 'package:langchain_core/prompts.dart'` |
| `BaseChatModelOptions.copyWith` 不支持 `maxTokens` 参数 | 移除该参数（已在 config 初始化时设置） |
| `AiSkill` 类型在 `langchain_registry.dart` 中未导入 | 添加 `import 'package:anx_reader/service/ai/skills/ai_skill.dart'` |
| 动态 `IconData()` 构造导致 tree-shaking 失败 | 改用 `Icons.auto_fix_high` 常量 |
| freezed `BgimgType` switch 表达式不穷尽 | 添加 `_ =>` 通配符 case |

### Phase 4 补充：全量中文本地化（2026-04-02）

为 Phase 4 所有新增 UI 文字补全 zh / zh-CN 适配；同步修复 zh.arb 对 Phase 0-3 部分条目的遗漏：

| 范围 | 新增 L10n 条目数 | 说明 |
|------|-----------------|------|
| Phase 4 新增（3 ARB 文件） | 53 条 | KAIROS picker × 9、Skills picker × 6、技能名称 × 12、Web Search 对话框 × 5、Local Embedding 对话框 × 6、杂项 × 15 |
| zh.arb 补全（仅 zh.arb） | 17 条 | settingsAiDebug*、settingsAiPadPanel*、settingsAiDockSide*、settingsAiQuickPrompts* |

代码层改动：
- `ai.dart`：AI Features 区块全部 `const Text('...')` → `Text(l10n.*)` ；新增 `_localizedSkillName/Desc(context, id?)` helper
- `ai_chat_stream.dart`：Skills tooltip、No Skill popup → L10n；新增 `_localizedSkillName/Desc(context, skill)` helper

### Phase 4 补充：Bug 修复与代码清理（2026-04-03）

代码审查发现 Phase 3 集成中 3 个未正确接线的模块，已全部修复：

| Bug | 根因 | 修复 |
|-----|------|------|
| **ConversationCompressor 压缩结果丢弃** | `index.dart` 调用 `compress()` 后，返回的 `result.messages` 从未赋值回 `historyMessages`，导致压缩消耗 token 但摘要被丢弃 | 新增 `compressedHistory` 变量，压缩成功时赋值，传入 `streamAgent(history: compressedHistory)` |
| **AnnotationLedger 无会话级持久化** | `AiToolContext` 在每次 `_buildPipeline()` 时重新创建，导致 ledger 在同一对话的不同 turn 间丢失 | 在 `index.dart` 新增 `_sessionLedgers` (Map)；`AiToolContext` 新增 `externalAnnotationLedger` 参数；通过 `resolve()` → `_buildPipeline()` 注入 |
| **MaxTokensStrategy 检测但未应用** | `_maxTokensEscalated` 标志被正确设置，但 `BaseChatModelOptions.copyWith()` 不支持 `maxTokens` 参数，无法在迭代间动态调整 | 移除死逻辑（检测代码 + 字段 + 未使用的 import）；maxTokens 由用户配置直接控制 |

其他清理：
- 移除 `langchain_runner.dart` 中残留的注释掉的旧 thinking-mode 代码
- `contextWindowSize` 从硬编码 128000 改为从 `config.maxTokens` 读取，fallback 128K

---

## 8. 未来计划（Phase 5）

| 编号 | 任务 | 说明 | 优先级 |
|------|------|------|--------|
| P5-A | **用户自定义 Skills** | 支持用户导入/编辑 YAML 格式技能模板；技能市场概念 | P3 |
| P5-B | **KAIROS 章节完成检测** | 完成一章后自动弹出摘要卡片（基于 percentage 检测） | P3 |
| P5-C | **Token 使用历史图表** | 按日/周/月统计 token 消耗和费用趋势 | P4 |
| P5-D | **Sub-Agent 并行执行** | Sub-Agent 资源池化（串行复用，限制移动端内存） | P3 |
| P5-E | **工具单元测试** | 核心工具的输入验证和逻辑单元测试 | P2 |
| P5-F | **Streaming Tool Execution** | 工具 JSON 完整即刻执行，不等整个响应完成 | P3 |

#### 移动端可行性说明

| 路线图项 | 可行性 | 备注 |
|----------|--------|------|
| PDF OCR (MinerU) | 需服务端 | MinerU 是 Python 库，无法在 iOS/Android 运行；替代方案：云 OCR API 或仅用 PDF outline 分章 |
| Streaming Tool Execution | 高复杂度 | 受限于 LangChain Dart 架构——当前等整个 response 完成后才解析 tool_use JSON |
| Sub-Agent 并行 | 有风险 | 每个 sub-agent 独占 LLM stream + 内存；4GB 设备 OOM 风险；建议保持串行 |
| 本地 Embedding | 需 LAN | 模型无法在设备上运行，需 LAN/远程 Ollama 服务器；当前实现已支持 LAN 连接 |

---

## 9. 设计参考

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

## 10. 与旧计划文档的对照

旧文档 `参考/PaperTok_Agent_Implementation_Plan.md` 提出了 6 个 Phase，以"从零构建 Agent 系统"为前提。实际实现已走了 LangChain 路线，大部分 Phase 1-2 的目标已由 LangChain + 现有工具系统实现。

| 旧计划 | 当前状态 |
|--------|----------|
| Phase 0: 代码审计 | ✅ 审计完成（未生成独立文档，直接用于指导开发） |
| Phase 1: 自研 AgentTool/ToolRegistry/AgentLoop | ✅ 由 LangChain 实现；本次补充了 ToolOrchestrator / ToolApprovalDelegate / AiToolScene |
| Phase 2: 核心工具集 | ✅ 已有 40+ 工具；本次补充 CreateHighlight + CreateNote |
| Phase 3: 系统提示与上下文管理 | ✅ 已有 system prompt 生成；本次补充 ConversationCompressor |
| Phase 4: UI 集成 | ✅ 已有 tool_step_tile / ai_chat_stream；成本追踪 UI 已集成 (P4-UI) |
| Phase 5: 上下文智能管理 | ✅ 本次补充 BookContentCache / MaxTokensStrategy |
| Phase 6: 测试与 QA | ⏳ 工具单元测试仍需补充 |

**旧文档建议保留在 `参考/` 目录作为历史记录，不再作为执行指南。**

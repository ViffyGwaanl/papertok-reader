# Current Capability Map

> 目的：让后续 agent 在动手前知道 PaperTok Reader 已经有什么、应该复用什么、缺口在哪里。

## 1. AI Chat / Provider / Skills

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| AI Chat streaming | `aiChatProvider` 已负责 streaming 生命周期，UI 最小化不应打断生成。 | Seminar session 需要结构化事件、角色输出和恢复状态。 | E01, E07 |
| Provider Center | 已支持内置/自定义 provider、模型切换、Responses 兼容开关。 | Seminar 需要角色预算、成本上限、provider 能力矩阵。 | E01, E06 |
| Skills | 已有 `seminar_mode`、reading companion、flashcard 等 prompt skill。 | `seminar_mode` 仍是 prompt-only，不是服务层 orchestrator。 | E01, E06 |

锚点：

- `lib/providers/ai_chat.dart`
- `lib/service/ai/langchain_registry.dart`
- `lib/service/ai/langchain_runner.dart`
- `lib/service/ai/skills/ai_skill_registry.dart`

## 2. Sub-Agent / Tool Orchestration

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| `SubAgentRunner` | 已有 `research / summarize / verify` 受限子 agent，禁止递归。 | Seminar 需要固定角色、白名单工具、预算和中间事件。 | E01, E06 |
| `spawn_sub_agent` | 主 agent 可委派聚焦任务。 | 默认无 UI 审批，不能直接写用户资产。 | E01, E06 |
| `ToolOrchestrator` | 已有并发/串行工具调度。 | 需要明确 Seminar 中只读检索可并行，写入必须串行审批。 | E01, E06, E07 |

锚点：

- `lib/service/ai/sub_agent_runner.dart`
- `lib/service/ai/tools/spawn_sub_agent_tool.dart`
- `lib/service/ai/tool_orchestrator.dart`
- `lib/service/ai/tools/ai_tool_registry.dart`

## 3. Annotation / Notes / Memory

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| `AnnotationLedger` | 能记录当前会话 AI 创建的高亮/笔记，防重复。 | Seminar 需要 Shared Whiteboard，记录 claim、evidence、disagreement、open question。 | E00, E01 |
| Create Highlight/Note tools | AI 已能创建高亮和笔记，且有工具审批链路。 | KnowledgeCard 不应直接复用 note 作为唯一模型，需要独立 review 状态。 | E03, E05 |
| Memory Review Inbox | 已有候选写入、rationale、源跳转思路。 | 需要扩展到 KnowledgeCard、复习题、ConceptGraph 用户确认关系。 | E03, E05 |

锚点：

- `lib/service/ai/annotation_ledger.dart`
- `lib/service/ai/tools/create_highlight_tool.dart`
- `lib/service/ai/tools/create_note_tool.dart`
- `lib/service/memory/memory_workflow_service.dart`

## 4. Library RAG / RAPTOR / GraphRAG

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| Library RAG | `semantic_search_library` 已提供跨书库 hybrid retrieval 和 `paperreader://reader/open?...` 跳转。 | 需要把 evidence 结构作为 SourceRef 输入，统一供 Seminar/Card/Graph 使用。 | E00, E01, E02, E03 |
| `ai_index.db` | 存放可重建索引、chunk、job、RAG/Graph 相关表。 | 用户资产不能放进可重建索引层；未来迁移必须从当前版本递增。 | E02, E04, E08 |
| RAPTOR/GraphRAG 雏形 | 已有全局层表和 builder 方向。 | 需要产品化 Gate：证据、重建、旧 DB 升级、失败恢复。 | E02, E04 |

锚点：

- `lib/service/rag/semantic_search_library.dart`
- `lib/service/rag/ai_index_schema.dart`
- `lib/service/rag/ai_book_indexer.dart`
- `lib/service/rag/ai_global_index_builder.dart`
- `docs/superpowers/specs/2026-05-28-library-rag-optimization-design.md`

## 5. Deep Links / Backup / Sync

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| Reader deep link | `paperreader://reader/open?...` 已是书内跳转规范。 | 所有卡片、图节点、Seminar claim 都要统一 SourceRef。 | E00, E03, E04, E07 |
| AI settings sync | WebDAV 同步 AI 设置，不包含 API key。 | Knowledge assets 需要 per-entity sync，而非 settings-style newer-wins。 | E08 |
| Backup/restore | 已支持 memory 和 `ai_index.db` 可选包含。 | 未来要区分用户资产、AI draft、派生索引和密钥策略。 | E05, E08 |

锚点：

- `docs/ai/ai_settings_sync_webdav.md`
- `docs/ai/backup_restore_icloud.md`
- `docs/ai/rag_memory_plan_zh.md`

## 6. 全局缺口

- 缺少统一 `SourceRef`，导致 RAG evidence、note、memory、card、conversation 的引用形态分散。
- 缺少 KnowledgeCard 用户资产模型，AI 产出难以跨 chat、review、复习复用。
- `seminar_mode` 仍是 prompt skill，不具备 OpenMAIC 式角色编排、whiteboard、action protocol。
- ConceptGraph 还需要明确哪些是派生缓存、哪些是用户确认资产。
- 文档中存在传统 phase/roadmap 混写，不能直接给 agent team 执行。


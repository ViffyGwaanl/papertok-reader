# Current Capability Map

> 目的：让后续 agent 在动手前知道 PaperTok Reader 已经有什么、应该复用什么、缺口在哪里。

## 1. AI Chat / Provider / Skills

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| AI Chat streaming | `aiChatProvider` 已负责通用聊天 streaming 生命周期；本分支新增 `AiSeminarRuntimeService`，可把 role-by-role Seminar 输出为 evidence、role turn、whiteboard、synthesis 事件。 | Seminar 的成本记录、后台持久续跑和更细粒度 provider capability matrix 仍需接入。 | E01, E07 |
| Provider Center | 已支持内置/自定义 provider、模型切换、Responses 兼容开关。 | Seminar 需要角色预算、成本上限、provider 能力矩阵。 | E01, E06 |
| Skills | 已有 `seminar_mode`、reading companion、flashcard 等 prompt skill；本分支新增 AI Seminar 服务层编排、真实模型流式 role runtime、Shared Whiteboard UI、Review handoff、`CustomSkillContract` strict JSON/Map schema parser，以及阅读页选中文本 -> `研讨` 的结构化入口。 | 自定义 Skill 导入界面、角色预算和 provider 能力矩阵还需要接入治理模型。 | E01, E06, E07 |

锚点：

- `lib/providers/ai_chat.dart`
- `lib/service/ai/langchain_registry.dart`
- `lib/service/ai/langchain_runner.dart`
- `lib/service/ai/skills/ai_skill_registry.dart`

## 2. Sub-Agent / Tool Orchestration

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| `SubAgentRunner` | 已有 `research / summarize / verify` 受限子 agent，禁止递归；本分支新增 AI Seminar role executor 可注入服务，且服务层校验 role/evidence 合约，runtime UI 已能取消和重试。 | 预算记录和跨 provider capability matrix 仍需接入 UI/runtime。 | E01, E06 |
| `spawn_sub_agent` | 主 agent 可委派聚焦任务。 | 默认无 UI 审批，不能直接写用户资产。 | E01, E06 |
| `ToolOrchestrator` | 已有并发/串行工具调度；本分支新增 permission matrix、sub-agent policy、custom skill runtime injection gate 的可测试模型。 | 取消、超时和成本记录还需要和真实运行时事件打通。 | E01, E06, E07 |

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
| KnowledgeCard local store | 本分支新增 `KnowledgeCardStore`，可把 AI 候选卡持久化到 `.knowledge/knowledge_cards_v1.json`，重复候选不覆盖用户内容，ReviewItem 决策可回写 card；统一 Review Inbox UI 已能批准、忽略、应用 KnowledgeCard 审批项；阅读页选中文本、图片解析结果、RAG/GraphRAG evidence、AI Chat 回答和 Seminar candidate card 都可写入待审卡；Seminar candidate card 和 reader-grounded AI Chat card 可携带 `conceptRefs`，用户 Apply 后进入 ConceptGraph 候选链路。 | AI Chat 回答必须由用户点击回答旁 `知识卡` 才写入；回答旁已显示可跳转/不可用来源状态；从选中文本打开 AI 时可保留精确 reader SourceRef，并随 `conversationV2` 历史持久化；如果用户把预填草稿改成无关问题，或只是碰巧包含短公共片段，则本轮不保存旧 reader SourceRef；没有该字段的旧历史只保留 conversation provenance，不用当前阅读位置伪造 reader grounding；纯聊天 card 不生成 `conceptRefs`，AI Chat 不直接写 ConceptGraph。 | E03, E05, E08 |
| Memory Review Inbox | 已有候选写入、rationale、源跳转思路；本分支新增统一 `ReviewItemStore`、`ReviewInboxController`、`reviewInboxProvider` 和 `ReviewInboxPage`，可展示并处理 KnowledgeCard、ConceptGraph relation、Seminar synthesis、Memory、Flashcard 等审批项；选中文本 KnowledgeCard、Seminar synthesis、Seminar candidate card 和 Seminar reviewSuggestion flashcard 已能进入统一 Review Inbox；flashcard candidate Apply 后可进入 Spaced Review。 | Seminar synthesis 本身只支持 approve/dismiss，不做泛型 apply；Memory source-specific apply adapter 仍需接入。 | E03, E04, E05 |

锚点：

- `lib/service/ai/annotation_ledger.dart`
- `lib/service/ai/tools/create_highlight_tool.dart`
- `lib/service/ai/tools/create_note_tool.dart`
- `lib/service/memory/memory_workflow_service.dart`

## 4. Library RAG / RAPTOR / GraphRAG

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| Library RAG | `semantic_search_library` 已提供跨书库 hybrid retrieval、`paperreader://reader/open?...` 跳转和 SourceRef evidence；RAPTOR/GraphRAG summary 只作为 `derivedSummary/derivedLayer` 检索提示，正式 evidence snippet 使用书内 chunk 原文；ConceptGraph 空态已可显式触发本地文本 RAG，把 traceable chunk evidence 写成 pending KnowledgeCard 或 draft graph relation，其中 KnowledgeCard 入口还要求 evidence 带可保存 chunk snippet。 | 需要把 derived summary 的 UI 展示和正式 evidence 视觉层级接入 AI 面板。 | E00, E01, E02, E03 |
| `ai_index.db` | 存放可重建索引、chunk、job、RAG/Graph 相关表；当前分支事实为 `kAiIndexDbVersion = 10`。 | 用户资产不能放进可重建索引层；后续迁移必须从当前版本递增。 | E02, E04, E08 |
| ConceptGraph local store | 本分支新增 `ConceptGraphStore`，可持久化 `.knowledge/concept_graph_v1.json`，构建 Concept Dossier，检测 orphan node / broken edge，并按 policy 限制局部探索深度和每层宽度；ConceptGraph relation 已能通过 ReviewItem apply 才进入正式 ownership；`ConceptGraphExplorerPage` 已提供 Settings -> AI 和阅读页选中文本 -> `图谱/Graph` 可见入口；KnowledgeCard apply、带 conceptRefs 的 Seminar candidate card apply、带 conceptRefs 的 reader-grounded AI Chat card apply，以及带 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result 可生成 draft graph candidates；空态 `Create draft candidate` 可显式触发关闭 query embedding、vector fallback、rerank 的本地文本 RAG -> producer -> ReviewItem handoff；选中概念后可看到局部图谱摘要，包含中心概念、直接关系、二跳节点、evidence link 数量和 draft/formal 状态。 | 复杂无限画布、缩放手势和跨书外部知识扩展不在本切片；AI Chat 仍不直接调用 RAG/GraphRAG producer。 | E04, E05, E07, E08 |
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
| Reader deep link | `paperreader://reader/open?...` 已是书内跳转规范；本分支新增 SourceRef -> `PaperReaderReaderIntent` 和 `PaperReaderSourceJumpAudit`，可统一检查 jumpable、unavailable、unresolved refs。 | 需要把 audit 结果接入 KnowledgeCard、ReviewItem、Seminar claim、Concept Dossier 和 UI 错误恢复。 | E00, E03, E04, E07 |
| AI settings sync | WebDAV 同步 AI 设置，不包含 API key；KnowledgeSyncPolicy 已递归排除常见 secret-like payload keys。 | Knowledge assets 需要 per-entity sync，而非 settings-style newer-wins。 | E08 |
| Knowledge asset sync boundary | `KnowledgeSyncEnvelope` 已区分 `ai-draft`、`knowledge-card`、`derived-index`；`KnowledgeSyncPolicy` 默认排除 draft、derived cache 和含 secret-like payload 的 envelope；`KnowledgeCardStore` 中 draft/pending 不按用户资产同步，applied 且有 evidence 的卡片才进入 knowledge-card envelope。 | 真正的同步/冲突恢复管线还需要 per-entity merge、Review 冲突 UI 和 export manifest 接入。 | E08 |
| Backup/restore | 已支持 memory 和 `ai_index.db` 可选包含。 | 未来要区分用户资产、AI draft、派生索引和密钥策略。 | E05, E08 |

锚点：

- `docs/ai/ai_settings_sync_webdav.md`
- `docs/ai/backup_restore_icloud.md`
- `docs/ai/rag_memory_plan_zh.md`

## 6. 全局缺口

- 统一 `SourceRef` 核心模型已存在；仍需把所有 UI 输出、sync/export manifest 和旧 note/memory 路径完全接到同一证据链。
- KnowledgeCard 模型、本地 store、Review adapter、统一 Review Inbox UI、reader selection 入口、图片分析结果入口、RAG/GraphRAG evidence 入口、AI Chat 回答显性 `知识卡` handoff、AI Chat 回答旁来源状态提示、AI Chat reader SourceRef 历史持久化、AI Chat 无关改写和短公共片段 SourceRef 降级、AI Chat reader-grounded `conceptRefs` handoff、Seminar candidate handoff、Seminar flashcard handoff、spaced review scheduler 和导出入口已有可测试切片；仍需把旧 note/memory 路径完全接到同一 SourceRef 审计 UI。
- `seminar_mode` 已有服务层编排、Evidence Broker、role turn validation、whiteboard handoff、结构化 runtime UI、真实模型流式事件、取消/重试、Review handoff 和阅读页选中入口；仍需成本记录、后台持久续跑和更强 provider capability matrix。
- Custom Skill contract 已有 schema version、parser、validator、权限声明和 runtime injection gate；仍需导入 UI、fixture 管理和 provider 能力界面。
- ConceptGraph 模型、本地 store、KnowledgeCard producer、Seminar candidate conceptRefs handoff、reader-grounded AI Chat conceptRefs handoff、RAG/GraphRAG derived result producer、空态显性 action、局部探索、局部图谱摘要、统一 Review relation adapter、Explorer UI 和阅读页选中文本入口已有可测试切片；复杂无限画布、缩放手势和跨书外部知识扩展不在本切片。
- 旧历史文档中仍存在传统 phase/roadmap 混写；agent team 应以本目录的 `Epic -> Capability -> Agent Task -> Gate -> Acceptance` 文档为执行入口，旧文档只作为历史锚点。

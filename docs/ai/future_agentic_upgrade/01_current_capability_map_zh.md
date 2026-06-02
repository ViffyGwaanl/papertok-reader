# Current Capability Map

> 目的：让后续 agent 在动手前知道 PaperTok Reader 已经有什么、应该复用什么、缺口在哪里。

## 1. AI Chat / Provider / Skills

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| AI Chat streaming | `aiChatProvider` 已负责通用聊天 streaming 生命周期；本分支新增 `AiSeminarRuntimeService`，可把 role-by-role Seminar 输出为 evidence、role turn、whiteboard、synthesis 事件，并在 Seminar runtime state 中持久化 provider diagnostics、provider-reported token usage、本地 token usage fallback、本地 role/run token budget、pricing metadata 驱动的估算美元成本 cap、billing snapshot / reconciliation UI、单 Seminar 本机 `Background job` snapshot、同入口本机恢复缓存和 provider/model/pricing 匹配时的 traceable evidence checkpoint resume；已有 completed role prefix 会跳过，空 completed role 但已有 traceable evidence 时会从首个缺失角色重新生成。AI Chat Add-to-Chat sheet 已有 `AI 研讨会` 功能卡，点击后在当前 AI Chat 页面内展开 `AiSeminarRuntimePanel`，并向 `conversationV2` 写入轻量 `AiSeminarRunCardMeta` + fallback assistant message；历史重载后可渲染 `AI 研讨会` 卡片并点击恢复 inline runtime；阅读页选中文本 `研讨` 已迁到阅读页 AI Chat 内嵌 Seminar 面板，保留 reader SourceRef 且不改 `activeAiSkillId`；AI Chat inline panel、可见任务卡 snapshot 和卡内送审已按 `seminarSessionId` 使用 scoped runtime；不同 scoped runtime 的模型调用由本机 coordinator 串行化，不并发外发 Seminar；Seminar settings 已能保存每个角色的显示名和 custom prompt，并在新 session 的 role prompt 中注入；`AiSeminarDirectorState` 第一片已能随 runtime state 保存轮次、已完成角色、证据账本、白板账本、分歧、用户插话和下一步 intent，completed run 有 open question 时标记 `askUser`、有 disagreement 且仍有轮次预算时标记 `refreshEvidence`，status banner 会显示主持人下一步；`askUser` 状态下用户可输入回复、选择目标角色或请求重新找证据/整理总结，回复只进入 `lastUserIntervention`；选择“让角色回应”会调用目标角色生成 follow-up turn，并用现有 evidence 和全部 prior turns 更新 synthesis；选择“重新找证据”会重新调用 evidence broker、重跑角色并更新 synthesis，同时递增 `evidenceRefreshCount`；选择“整理总结”会用现有 evidence 和 turns 执行本地 synthesis，并把 Director 收束为 `end`；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会自动重新检索 evidence、重跑角色，并在刷新后仍有分歧且预算耗尽时转为 `askUser`。 | 完整 AI Chat Seminar run message part 的证据/角色/分歧/白板/总结/离线送审子视图、独立详情页共享 scoped store、run-scoped composer 子视图、完整 Director loop 调度、角色启用状态、证据策略、工具范围配置、Seminar OS/background execution gate、旧 stream 原地续传、queued job 重启确认和 provider 发票导入 adapter 仍需接入。 | E01, E07 |
| Provider Center | 已支持内置/自定义 provider、模型切换、Responses 兼容开关；`ChatOpenAIResponses` 已能在第三方 Responses 网关明确拒绝 `previous_response_id` 时自动降级重试，不影响正常 server-side continuation provider；`AiSeminarProviderContextService` 已能读取当前 provider/model、本地 capability cache、context/max output、Tools/Vision/Thinking 状态和 pricing metadata，并把 provider/model/pricing source 捕获为 Seminar billing context；`AiUsageTracker` 可接收 provider/SDK 回传的 token usage；当前 schema 没有 streaming 字段时显示 `Streaming unknown`，并在缺少 pricing metadata 时显示成本未知原因。 | Seminar 还需要多 job/background execution capability、正式 streaming capability 字段、provider invoice import adapter 和 provider capability 中的 `previous_response_id` 长期兼容标记。 | E01, E06 |
| Skills | 已有 `seminar_mode`、reading companion、flashcard 等 prompt skill；本分支新增 AI Seminar 服务层编排、真实模型流式 role runtime、Shared Whiteboard UI、Review handoff、provider readiness UI、provider token usage UI、本地 token budget guardrails、estimated USD run cost cap、billing reconciliation UI、本机 background job status、`CustomSkillContract` strict JSON/Map schema parser、`CustomSkillStore`、Settings -> AI -> `Custom skills` 导入入口、Active Skill 合并和 LangChain runtime 工具收窄，以及阅读页选中文本 -> `研讨` 的结构化入口。 | 多任务后台队列、provider 发票导入和 provider 能力界面还需要接入治理模型。 | E01, E06, E07 |

锚点：

- `lib/providers/ai_chat.dart`
- `lib/service/ai/langchain_registry.dart`
- `lib/service/ai/langchain_runner.dart`
- `lib/service/ai/skills/ai_skill_registry.dart`

## 2. Sub-Agent / Tool Orchestration

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| `SubAgentRunner` | 已有 `research / summarize / verify` 受限子 agent，禁止递归；本分支新增 AI Seminar role executor 可注入服务，且服务层校验 role/evidence 合约，runtime UI 已能取消、重试、本地 token budget 停止、provider token usage 显示、估算美元成本 cap 和本机 background job status。 | 多任务后台队列、价格版本/账单对账和跨 provider capability matrix 仍需接入 UI/runtime。 | E01, E06 |
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
| Memory Review Inbox | 已有候选写入、rationale、源跳转思路；本分支新增统一 `ReviewItemStore`、`ReviewInboxController`、`reviewInboxProvider` 和 `ReviewInboxPage`，可展示并处理 KnowledgeCard、ConceptGraph relation、Seminar synthesis、Memory、Flashcard 等审批项；选中文本 KnowledgeCard、Seminar synthesis、Seminar candidate card 和 Seminar reviewSuggestion flashcard 已能进入统一 Review Inbox；flashcard candidate Apply 后可进入 Spaced Review；Memory source-specific apply/dismiss adapter 已接入本地 Markdown memory 写入边界；Memory home、daily memory、long-term memory 独立浏览页已接只读 SourceRef 投影、evidence list、jump audit 和不可跳原因；旧 BookNote/highlight 列表和搜索结果已接 SourceRef audit UI。 | Seminar synthesis 本身只支持 approve/dismiss，不做泛型 apply；Memory browse SourceRef 是从已应用 MemoryCandidate 只读投影，不把来源 metadata 写回 Markdown。 | E03, E04, E05 |

锚点：

- `lib/service/ai/annotation_ledger.dart`
- `lib/service/ai/tools/create_highlight_tool.dart`
- `lib/service/ai/tools/create_note_tool.dart`
- `lib/service/memory/memory_workflow_service.dart`

## 4. Library RAG / RAPTOR / GraphRAG

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| Library RAG | `semantic_search_library` 已提供跨书库 hybrid retrieval、`paperreader://reader/open?...` 跳转和 SourceRef evidence；`semantic_search_current_book` 已改为分页扫描、bounded topK、winner-only 正文加载、page-batched JSON fallback、全局串行、每页向量 scoring backend seam、默认 background isolate scoring、取消 token、progress callback、bounded FTS/BM25 候选预筛和 synthetic large-book scan acceptance，避免一次性加载当前书全部 chunk 正文/JSON，并降低阅读页长循环占用 UI isolate 的概率；书库 exact backend 扫描阶段不再读取正文大字段；native vector shadow rows 可由旧索引升级入口补建；默认 backend 已改成 ANN -> native -> exact，Vec1/sqlite-vec function 和 per-provider/model/dim ANN 表存在且完整时优先走 `AiVec1VectorSearchBackend`，否则合并/降级 native SQL seam 与 compact exact backend；删除书籍会清理对应 RAPTOR/GraphRAG 派生层、native vector shadow rows、Vec1 ANN 行和 meta；RAPTOR/GraphRAG summary 只作为 `derivedSummary/derivedLayer` 检索提示，正式 evidence snippet 使用书内 chunk 原文；ConceptGraph 空态已可显式触发本地文本 RAG，把 traceable chunk evidence 写成 pending KnowledgeCard 或 draft graph relation，其中 KnowledgeCard 入口还要求 evidence 带可保存 chunk snippet。 | 需要把 derived summary 的 UI 展示和正式 evidence 视觉层级接入 AI 面板；current-book search 已有 FTS/BM25 候选预筛和向量后端 seam，但移动端 sqlite-vec/Vec1 extension/package、可恢复 ANN build job 和 provider/model 失效还不是发布级能力。 | E00, E01, E02, E03 |
| `ai_index.db` | 存放可重建索引、chunk、job、RAG/Graph 相关表；当前分支事实为 `kAiIndexDbVersion = 12`；新增 `ai_vector_index_rows` / `ai_vector_index_meta` native vector shadow layer；`AiVec1VectorIndexBuilder` 可从 shadow rows 按 provider/model/dim 建立独立 Vec1 virtual table，并写入 `vec1-ann` meta；`AiVectorIndexPurger` 让 `clearBook` 显式清理派生图谱和向量层残留；`AiLibraryIndexPage` 已有 `ANN 向量索引` tile，可检查 Vec1/sqlite-vec 加载状态、ANN group/row 缺口并触发可取消构建；当前书 hot scan 不再读取 `text/raw_text/embedding_json`，旧 JSON fallback 按页读取，向量解码和 cosine scoring 默认按页进入 background isolate；current-book search 会使用 `ai_chunks_fts` 只取候选 id，并在 FTS5 缺失、MATCH 失败、候选过期或无候选时回退完整分页扫描；synthetic large-book acceptance 覆盖候选命中时只扫描 candidate limit；`AiVectorRecallOverlapGate` 可用于候选 ANN/native backend 与 exact backend 的 topK 重合率验收。 | 用户资产不能放进可重建索引层；后续迁移必须从当前版本递增；真实 ANN/sqlite-vec/Vec1 package/extension adapter、平台打包、可恢复 ANN build job 和 provider/model 失效仍未完成。 | E02, E04, E08 |
| ConceptGraph local store | 本分支新增 `ConceptGraphStore`，可持久化 `.knowledge/concept_graph_v1.json`，构建 Concept Dossier，检测 orphan node / broken edge，并按 policy 限制局部探索深度和每层宽度；ConceptGraph relation 已能通过 ReviewItem apply 才进入正式 ownership；`ConceptGraphExplorerPage` 已提供 Settings -> AI 和阅读页选中文本 -> `图谱/Graph` 可见入口；KnowledgeCard apply、带 conceptRefs 的 Seminar candidate card apply、带 conceptRefs 的 reader-grounded AI Chat card apply，以及带 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result 可生成 draft graph candidates；空态 `Create draft candidate` 可显式触发关闭 query embedding、vector fallback、rerank 的本地文本 RAG -> producer -> ReviewItem handoff；选中概念后可看到轻量节点-连线 canvas 和局部图谱摘要，包含中心概念、直接关系、二跳节点、evidence link 数量和 draft/formal 状态；Settings Explorer 可列出已有全局层的已索引书并直接展示只读全书自动图谱，阅读页入口可直接展示当前书全局层派生图谱。 | 复杂无限画布、缩放手势和跨书外部知识扩展不在本切片；Settings 书籍选择只读派生缓存，不补建索引、不写正式图谱；AI Chat 仍不直接调用 RAG/GraphRAG producer。 | E04, E05, E07, E08 |
| RAPTOR/GraphRAG 雏形 | 已有全局层表和 `AiGlobalIndexBuilder`；`Settings -> AI Index / Library Index` 已提供 `全局层索引` 检查和补建入口，可用已有 chunk 为旧 chunk-only 索引书籍生成 RAPTOR 全局摘要层、RAPTOR chunk links 和当前 deterministic GraphRAG 派生层，支持进度、取消和失败提示；缺少 graph node 的中文书只要 RAPTOR 全局层存在，不会被反复标记为缺失。 | 当前补建仍是前台设置页任务，不是后台 job ledger；Graph term extractor 对纯中文概念节点仍弱；ANN/sqlite-vec/Vec1 后端和复杂全书图谱画布仍未完成。 | E02, E04 |

锚点：

- `lib/service/rag/semantic_search_library.dart`
- `lib/service/rag/semantic_search_current_book.dart`
- `lib/service/rag/ai_index_schema.dart`
- `lib/service/rag/ai_book_indexer.dart`
- `lib/service/rag/ai_global_index_builder.dart`
- `docs/superpowers/specs/2026-05-28-library-rag-optimization-design.md`

## 5. Deep Links / Backup / Sync

| 项 | 当前可复用 | 缺口 | 下游 Epic |
| --- | --- | --- | --- |
| Reader deep link | `paperreader://reader/open?...` 已是书内跳转规范；本分支新增 SourceRef -> `PaperReaderReaderIntent` 和 `PaperReaderSourceJumpAudit`，可统一检查 jumpable、unavailable、unresolved refs；Review Inbox、Spaced Review、ConceptGraph、BookNote/highlight tile 和 Memory 独立浏览页已复用 jump audit，缺失书内锚点时显示不可跳原因。 | 新增 UI 输出必须先定义 source-specific unavailable/unresolved 状态。 | E00, E03, E04, E07 |
| AI settings sync | WebDAV 同步 AI 设置，不包含 API key；KnowledgeSyncPolicy 已递归排除常见 secret-like payload keys。 | Knowledge assets 需要 per-entity sync，而非 settings-style newer-wins。 | E08 |
| Knowledge asset sync boundary | `KnowledgeSyncEnvelope` 已区分 `ai-draft`、`knowledge-card`、`derived-index`；`KnowledgeSyncPolicy` 默认排除 draft、derived cache 和含 secret-like payload 的 envelope；`KnowledgeRemoteMergePlanner` 可对 local/remote/base envelope 做只读三路 diff，用 canonical per-envelope fingerprint 输出 unchanged/incoming/outgoing/conflict，不受 `updatedAt` newer-wins 影响；`KnowledgeCardStore` 中 draft/pending 不按用户资产同步，applied 且有 evidence 的卡片才进入 knowledge-card envelope；Knowledge sync/export 已能写安全 sync bundle、读取远端 bundle preview、提供 `Check remote changes` 前台只读检查、显示远端同步状态、把远端冲突送入 Review、把安全远端 incoming KnowledgeCard 降级为 pending Review、把安全远端 review history 降级为 pending Review、把安全远端 KnowledgeCard conflict 暂存到 staged conflict store，ReviewItem 写入失败时回滚 staged entry，并在远端无 incoming/conflict 时通过带 rollback snapshot 和 ETag/CAS 条件写 guard 的 remote writeback executor 写回安全 sync bundle；写回失败会恢复旧远端 bundle 或删除半写入的新 bundle，并在状态面板显示 rollback 结果。 | 同步管线还需要跨设备后台同步任务状态、故障恢复视图和 release promotion。 | E08 |
| Backup/restore | 已支持 memory 和 `ai_index.db` 可选包含。 | 未来要区分用户资产、AI draft、派生索引和密钥策略。 | E05, E08 |

锚点：

- `docs/ai/ai_settings_sync_webdav.md`
- `docs/ai/backup_restore_icloud.md`
- `docs/ai/rag_memory_plan_zh.md`

## 6. 全局缺口

- 统一 `SourceRef` 核心模型已存在；Review Inbox、Spaced Review、ConceptGraph、BookNote/highlight、Memory 独立浏览页和 sync/export manifest 已接到同一证据链；新增 UI 输出仍必须显式定义 source-specific unavailable/unresolved 状态。
- KnowledgeCard 模型、本地 store、Review adapter、统一 Review Inbox UI、reader selection 入口、图片分析结果入口、RAG/GraphRAG evidence 入口、AI Chat 回答显性 `知识卡` handoff、AI Chat 回答旁来源状态提示、AI Chat reader SourceRef 历史持久化、AI Chat 无关改写和短公共片段 SourceRef 降级、AI Chat reader-grounded `conceptRefs` handoff、Seminar candidate handoff、Seminar flashcard handoff、spaced review scheduler、Memory 独立浏览 SourceRef audit、旧 BookNote/highlight SourceRef audit UI 和导出入口已有可测试切片。
- `seminar_mode` 已有服务层编排、Evidence Broker、role turn validation、whiteboard handoff、结构化 runtime UI、真实模型流式事件、取消/重试、Review handoff、provider readiness/cost unknown UI、provider token usage 记录和显示、本地 token usage fallback、本地 role/run token budget、pricing metadata 驱动的估算美元成本 cap、角色显示名/custom prompt 设置、DirectorState 可恢复账本、open question / disagreement next-intent policy、用户插话 capture、intent routing、askRole follow-up turn execution、用户触发的 refreshEvidence 重检索/重跑角色、disagreement 预算内自动 refresh 和 synthesize 本地收束、单 Seminar 本机 background job snapshot、同书/同问题本机 state 恢复、provider/model/pricing 匹配时的 traceable evidence checkpoint resume、阅读页选中入口和 AI Chat 轻量历史入口卡片；仍需完整结构化 AI Chat run card、OpenMAIC-style rebuttal loop、角色启用/证据策略/工具范围治理、OS/background execution gate、旧 stream 原地续传、queued job 重启确认和真实账单对账。
- Custom Skill contract 已有 schema version、parser、validator、权限声明、导入 UI、fixture 示例、Active Skill 合并和 runtime injection gate；仍需 provider 能力界面。
- ConceptGraph 模型、本地 store、KnowledgeCard producer、Seminar candidate conceptRefs handoff、reader-grounded AI Chat conceptRefs handoff、RAG/GraphRAG derived result producer、空态显性 action、局部探索、局部图谱摘要、Settings 全书自动图谱书籍选择、阅读页全书派生图谱预览、统一 Review relation adapter、Explorer UI 和阅读页选中文本入口已有可测试切片；复杂无限画布、缩放手势和跨书外部知识扩展不在本切片。
- 旧历史文档中仍存在传统 phase/roadmap 混写；agent team 应以本目录的 `Epic -> Capability -> Agent Task -> Gate -> Acceptance` 文档为执行入口，旧文档只作为历史锚点。

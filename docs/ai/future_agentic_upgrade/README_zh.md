# PaperTok Reader Future Agentic Upgrade

> 状态：Ready  
> 用途：给 AI agent team 执行的长期升级规格，而不是按人日、月份或季度排期的人类 roadmap。

本目录把 PaperTok Reader 的未来 AI 学习能力整理成可执行的工程文档体系。所有工作按 `Epic -> Capability -> Agent Task -> Gate -> Acceptance` 组织，任何任务在进入实现前都必须明确输入真相、输出产物、允许改动范围、禁止事项、验证命令和 reviewer gate。

## 1. 阅读顺序

1. `00_product_north_star_zh.md`：产品北极星和外部项目融合方式。
2. `01_current_capability_map_zh.md`：现有 PaperTok 能力、可复用模块和缺口。
3. `02_agent_execution_model_zh.md`：AI agent 执行模型、任务模板和禁止写法。
4. `03_epic_index_zh.md`：全部 Epic 的 DAG 依赖图。
5. `implementation_status_zh.md`：本分支代码 artifact、gate 和验证证据。
6. `04_user_facing_activation_plan_zh.md`：用户现在从哪里用、当前还不能用什么、入口任务验收状态和下一步 agent task。
7. `epics/`：每条能力线的执行规格。
8. `gates/`：跨 Epic 复用的质量、安全、资源和 rescue review gate。

## 2. 状态词

| 状态 | 含义 |
| --- | --- |
| `Draft` | 方向清楚，但还不能直接交给 agent 实现。 |
| `Ready` | 依赖、输入、输出、范围、验证和 acceptance 都已锁定。 |
| `Blocked` | 缺少上游任务、数据、工具、设计决策或外部条件。 |
| `In Review` | 实现已完成，正在做 reviewer/rescue gate。 |
| `Accepted` | 通过验收，证据可追溯。 |
| `Deprecated` | 被新 Epic、Capability 或代码事实替代。 |

本目录自身为 `Ready`，表示文档体系和 Epic 规格可以被 agent team 使用。单个 Epic 的任务仍必须按该 Epic 的 task table、task execution defaults 和对应 gate 执行，不允许跳过 reviewer/rescue gate。

## 3. 执行单位

| 单位 | 定义 | 输出 |
| --- | --- | --- |
| `Epic` | 一条完整能力线，例如 AI Seminar、KnowledgeCard、ConceptGraph。 | 可独立追踪的能力文档。 |
| `Capability` | Epic 内可单独交付的用户或平台能力。 | 结构化接口、服务边界、UI 或数据流。 |
| `Agent Task` | 可交给一个 AI agent 执行的最小任务。 | 代码、测试、文档或验证证据。 |
| `Gate` | 进入或完成任务前必须满足的检查。 | 可复用 checklist 和命令。 |
| `Acceptance` | 证明任务完成的具体标准。 | 测试输出、DB 断言、UI 行为、deep link 或截图。 |

## 4. 全局原则

- 不写人日、月份、季度或传统排期，只写依赖、Gate 和 Acceptance。
- 不把 OpenMAIC、MarginNote、WikiLinks、Understand-Anything 当作可复制产品，只抽象可融合能力。
- PaperTok Reader 现有 AI/RAG/Memory 架构是主线，新增能力必须接入现有模块。
- AI 生成内容默认是 draft，必须带 provenance，写入用户资产前进入 Review 或由用户显式确认。
- `ai_index.db`、RAPTOR、GraphRAG 索引默认是可重建派生缓存；用户确认过的卡片、复习记录、笔记和记忆才是用户资产。
- API key 永不同步；外发正文给 LLM 或 embedding provider 必须有功能级开关或明确提示。

## 5. 当前用户可用性

本目录不是说“所有 Epic 都已产品化”。本节只放用户入口摘要；完整的功能使用路径、入口缺口、agent 任务和验收边界以 `04_user_facing_activation_plan_zh.md` 为准；代码级完成状态和验证命令以 `implementation_status_zh.md` 为准。

如果只打开本 README，需要按下面两层理解：

- 用户要找入口：看本节表格的“用户怎么用”列。
- agent 要继续接产品闭环：看 `04_user_facing_activation_plan_zh.md` 的每条用户路径、Gate、验证命令和 `UFA-*` task。

下表的“已接入”只表示当前分支已有代码和测试证据，不等于 `main`、TestFlight 或用户已安装版本可用；未产品化、未发布或仍缺闭环的内容统一列在“当前还不能用”。

| 能力 | 用户怎么用 | 状态 |
| --- | --- | --- |
| 选中文本生成知识卡 | 阅读页选中文本 -> `知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；widget 覆盖菜单入口可见、点击 `Card` 后调用 producer、无注入 context/creator 时走 reader context fallback resolver 和默认 `SelectionKnowledgeCardProducer()`，写出 pending KnowledgeCard/ReviewItem，显示 Review feedback 并关闭菜单。 |
| 图片解析生成知识卡 | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；ImageViewer 工具栏点击、可注入分析流、弹层 `Card` 点击、pending KnowledgeCard 和 pending ReviewItem 已有 widget/service 证据；图片解析结果只作为 pending KnowledgeCard，不自动写长期资产。 |
| 一键开启研讨 | 阅读页选中文本 -> `研讨`，或 `Settings -> AI -> Seminar Mode / 研讨会模式`。 | 本分支已接入结构化 AI Seminar runtime/UI：展示 evidence、role turns、Shared Whiteboard、synthesis，支持取消、失败重试，并可把 traceable synthesis、候选卡和候选 flashcard 送入 Review Inbox；页面级 widget 覆盖点击 `Send to Review` 后写入 pending synthesis/card/flashcard handoff；`Provider readiness` 区块会显示当前 provider、model、context/max output、Tools/Vision/Thinking 能力、Streaming 状态未知提示和成本状态；角色输出优先显示 provider 返回的 `Provider reported usage`，没有 provider usage metadata 时降级为 `Local token estimate` 和 `Provider billing may differ`；用户可在页面设置本地 `Role output token budget`、`Run token budget`，当 provider capability cache 带 pricing metadata 时还可设置估算 `Run cost cap USD`，超出本地 token 估算或估算美元 cap 后停止后续 Seminar 步骤；完成或中断的 Seminar state 会保存为本机恢复缓存，同一书籍/同一入口问题重新打开页面时显示 `Recovered local Seminar state`，换书或换选区会清掉旧 runtime/cache，running state 只恢复为 interrupted/retryable，不伪装后台继续执行；估算成本不是 provider 发票，不自动写长期资产。 |
| AI Chat 回答生成知识卡 | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入显性 message action；streaming 中 `知识卡` 按钮禁用且不会调用 producer；回答旁会显示 `可跳转来源` 或 `已标记不可用` 来源状态；从选中文本打开 AI 时保留精确 SourceRef，并随 `conversationV2` 历史持久化，历史重载后仍优先使用原始 reader SourceRef；如果用户把预填草稿改成无关问题，本轮不保存旧 reader SourceRef，短公共片段只靠碰巧包含不会保留精确 reader grounding；reader-grounded card 会带保守 `conceptRefs`；用户 Apply 后进入 draft ConceptGraph 候选和 pending relation ReviewItem。纯聊天只保留 conversation provenance，不直接写长期资产或正式 ConceptGraph。 |
| Review Inbox | `Settings -> AI -> Review inbox`。 | 已有统一 UI；待审项显示状态、类型、证据摘录、来源标题/位置、不可用来源原因和打开来源动作；内容依赖 producer 写入。 |
| Memory 候选审核 | AI Chat 回答旁 `Memory actions` -> `Add to Review inbox`，再到 `Settings -> AI -> Review inbox` 审核、批准、应用。 | 本分支已接入 Memory source-specific apply adapter：`MemoryWorkflowService.addToReviewInbox` 会同时写 MemoryCandidate 和统一 ReviewItem；Review Inbox 的 `Approve -> Apply` 会先通过 `MemoryWorkflowService.applyCandidate` 追加到目标 daily/long-term Markdown，再推进 ReviewItem；`Dismiss` 会同步 MemoryCandidate 且不写 memory；无书内跳转的 conversation memory 会带证据摘录和不可跳原因。不会写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| Memory 独立浏览来源审计 | 首页底部 `Memory / 记忆` tab 打开 daily/long-term memory 列表；该 tab 默认隐藏，可先到 `Settings -> Home navigation / 首页导航` 打开；有来源的条目显示 `traceable/unavailable/unresolved` 状态，进入详情可查看 `Evidence` 并 `Open source`。 | 本分支已接入 `MemoryEntrySourceRefAdapter`、Memory home row source audit chips、Memory detail evidence list 和 source opener；来源来自已应用 `MemoryCandidate` 的只读投影，只按实际写入的 `text/displayText` 与条目正文匹配，long-term `MEMORY.md` 按 H1 分段 body 匹配；可跳来源打开 `paperreader://reader/open?...`，conversation-only memory 显示不可跳原因；long-term H1 分段不能被批量删除/打标签，避免误操作整份 `MEMORY.md`；不往 Markdown memory 写隐藏来源元数据，不绕过 Review 写资产。 |
| 旧划线/笔记来源审计 | 打开书籍笔记列表或全局搜索命中的笔记条目，查看 `Evidence`、`traceable/unavailable` 状态；点击无有效 book anchor 的旧笔记会提示不可跳原因，不进入空跳转。 | 本分支已接入 BookNote/highlight SourceRef audit：`BookNoteSourceRefAdapter` 生成 highlight/note SourceRef，`BookNoteTile` 复用 `SourceRefEvidenceList` 和 `PaperReaderSourceJumpAudit` 显示证据、来源位置、不可跳原因；Notes 列表和搜索结果会传入书名作为 source title，有有效 `bookId + cfi` 的笔记保持原文跳转，无有效 book anchor 的旧笔记只显示 snackbar 原因。 |
| 自定义 Skill 导入 | `Settings -> AI -> Custom skills` 粘贴 governed JSON -> `Import skill`，再到 `Active Skill` 选择已启用的自定义 skill。 | 本分支已接入 `CustomSkillStore`、导入页面、Settings 入口和运行时 skill registry 合并；只接受 `CustomSkillContract(schemaVersion=1)`，导入时校验 unknown field、unknown scene、system scene、写工具、递归 sub-agent 和字段类型；运行时只暴露自定义 skill 声明过且通过 permission matrix 的只读工具，scene 不匹配时不注入 prompt，不加载 MCP 工具。禁用或校验失败的 skill 不进入 Active Skill 列表。 |
| 图谱可视化探索 | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、Settings 点击入口、阅读页选中文本入口、KnowledgeCard -> draft ConceptGraph producer 和空态 `Create draft candidate` 显性 action；可查看已有图谱、按选中文本筛选相关概念、查看局部图谱摘要、局部路径、证据、draft/formal 状态和 orphan/broken link。当前 producer 可从 `applied + traceable + conceptRefs` 的 KnowledgeCard 生成待审图谱关系；Seminar candidate card 和 reader-grounded AI Chat card 都可携带 `conceptRefs`，经 Review apply 后进入同一图谱候选链路；`Create draft candidate` 使用关闭 query embedding、vector fallback、rerank 的本地文本检索，只让带 traceable chunk SourceRef 的 RAG/GraphRAG derived search result 生成 draft concept relation 和 pending ReviewItem；空态动作会显示已进入 Review 或跳过原因。 |
| RAG/GraphRAG 结果生成知识卡 | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；使用同一条本地文本 library RAG search，关闭 query embedding、vector fallback、rerank，只把带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG 结果写成 pending KnowledgeCard，不写正式图谱或长期资产；写入后页面会提示已加入 Review inbox。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；知识卡或 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入 Settings 点击入口、队列、复习页、证据摘录预览、Again/Hard/Good/Easy 评分和来源跳转状态；已接 KnowledgeCard apply 和 Seminar reviewSuggestion -> flashcard candidate -> Review Inbox Apply UI -> Spaced Review。 |
| Sync Export / Remote Preview | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出、机器可读 sync bundle、创建入口、待审冲突发送到 Review Inbox 的入口、远端 sync bundle preview、远端 incoming KnowledgeCard 发送到 Review Inbox、远端冲突发送到 Review Inbox，以及受保护 `Upload sync bundle` 写出；默认只纳入已确认知识资产和复习历史，排除草稿、派生索引、API key 和待审冲突；provider 级闭环覆盖安全本地 KnowledgeCard 冲突从 export handoff 到 Review approve/apply，再解除 pending conflict 并重新进入 export included 集合；远端 preview 只读取配置的 SyncClient/WebDAV bundle，展示 remote/incoming/outgoing/conflict 计数；安全远端 incoming KnowledgeCard 会降级为 pending + AI draft，用户 Apply 后才成为本机资产；远端冲突一律只支持 dismiss/triage，不显示 approve/apply；上传前会检查远端 incoming/conflict，存在会阻止写出。自动跨设备合并和回滚执行器仍在剩余任务中。 |

## 6. 当前还不能用

下表是本分支没有产品化的边界。它们不是“隐藏入口”，也不应被解释成当前用户已经可以使用。

| 还不能用的能力 | 当前边界 | 下一步 agent task |
| --- | --- | --- |
| 完整云同步引擎 | 目前有本地安全 manifest、Markdown、HTML、Anki TSV、机器可读 sync bundle、远端 bundle preview、远端 incoming KnowledgeCard Review 导入、受保护 sync bundle 上传、远端冲突 Review triage handoff，以及安全 KnowledgeCard 冲突的本地 Review 恢复；还没有远端冲突 staging/import、双向自动合并、review history 导入和失败回滚执行器。 | 设计并实现远端冲突合并器、review history staging/import、rollback 和同步状态 UI。 |
| Seminar 后台续跑和真实账单对账 | Seminar runtime 已能流式、取消、重试、送 Review，并能显示 provider/model capability、成本未知原因、provider-reported token usage、本地 token 估算 fallback、本地 role/run token budget、pricing metadata 驱动的估算 `Run cost cap USD` 和本机 state 恢复；running state 重启后会降级为 interrupted/retryable。未接真正后台续跑，也不做 provider invoice reconciliation。 | 接入后台任务队列、重启续跑、移动资源 gate 和真实账单/价格版本对账说明。 |
| 复杂无限画布式图谱 | 当前 ConceptGraph 是局部探索、dossier 和本地摘要，不做无限画布、缩放手势或跨书外部知识扩展。 | 若要做画布，先定义移动端资源 gate、证据可见性和 graph asset ownership。 |
| 发布版可用 | 本表描述 `codex/future-agentic-upgrade` 分支，不代表 `main`、TestFlight 或用户已安装版本。 | 走 release promotion gate：合并、构建、回归、发布说明和用户迁移说明。 |

入口计划以 `04_user_facing_activation_plan_zh.md` 为准；`implementation_status_zh.md` 只记录代码和验证证据。

## 7. 历史锚点

旧文档保留为历史事实，不在本目录内重写：

- `docs/ai/ai_status_roadmap_zh.md`
- `docs/ai/agent_system_architecture_zh.md`
- `docs/ai/rag_memory_plan_zh.md`
- `docs/superpowers/specs/2026-05-28-library-rag-optimization-design.md`
- `docs/superpowers/plans/2026-05-28-library-rag-optimization.md`

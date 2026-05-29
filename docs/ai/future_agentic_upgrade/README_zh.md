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
6. `04_user_facing_activation_plan_zh.md`：用户现在从哪里用、哪些还没有入口、剩余入口任务怎样交给 agent。
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

| 能力 | 用户怎么用 | 状态 |
| --- | --- | --- |
| 选中文本生成知识卡 | 阅读页选中文本 -> `知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；widget 覆盖菜单入口可见、点击 `Card` 后调用 producer、显示 Review feedback 并关闭菜单。 |
| 图片解析生成知识卡 | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；图片解析结果只作为 pending KnowledgeCard，不自动写长期资产。 |
| 一键开启研讨 | 阅读页选中文本 -> `研讨`，或 `Settings -> AI -> Seminar Mode / 研讨会模式`。 | 本分支已接入结构化 AI Seminar runtime/UI：展示 evidence、role turns、Shared Whiteboard、synthesis，支持取消、失败重试，并可把 traceable synthesis、候选卡和候选 flashcard 送入 Review Inbox；页面级 widget 覆盖点击 `Send to Review` 后写入 pending synthesis/card/flashcard handoff；不自动写长期资产。 |
| AI Chat 回答生成知识卡 | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入显性 message action；回答旁会显示 `可跳转来源` 或 `已标记不可用` 来源状态；从选中文本打开 AI 时保留精确 SourceRef，并随 `conversationV2` 历史持久化，历史重载后仍优先使用原始 reader SourceRef；如果用户把预填草稿改成无关问题，本轮不保存旧 reader SourceRef，短公共片段只靠碰巧包含不会保留精确 reader grounding；reader-grounded card 会带保守 `conceptRefs`；用户 Apply 后进入 draft ConceptGraph 候选和 pending relation ReviewItem。纯聊天只保留 conversation provenance，不直接写长期资产或正式 ConceptGraph。 |
| Review Inbox | `Settings -> AI -> Review inbox`。 | 已有统一 UI；待审项显示状态、类型、证据摘录、来源标题/位置、不可用来源原因和打开来源动作；内容依赖 producer 写入。 |
| 图谱可视化探索 | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、阅读页选中文本入口、KnowledgeCard -> draft ConceptGraph producer 和空态 `Create draft candidate` 显性 action；可查看已有图谱、按选中文本筛选相关概念、查看局部图谱摘要、局部路径、证据、draft/formal 状态和 orphan/broken link。当前 producer 可从 `applied + traceable + conceptRefs` 的 KnowledgeCard 生成待审图谱关系；Seminar candidate card 和 reader-grounded AI Chat card 都可携带 `conceptRefs`，经 Review apply 后进入同一图谱候选链路；`Create draft candidate` 使用关闭 query embedding、vector fallback、rerank 的本地文本检索，只让带 traceable chunk SourceRef 的 RAG/GraphRAG derived search result 生成 draft concept relation 和 pending ReviewItem；空态动作会显示已进入 Review 或跳过原因。 |
| RAG/GraphRAG 结果生成知识卡 | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；使用同一条本地文本 library RAG search，关闭 query embedding、vector fallback、rerank，只把带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG 结果写成 pending KnowledgeCard，不写正式图谱或长期资产；写入后页面会提示已加入 Review inbox。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；知识卡或 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入队列、复习页、证据摘录预览、Again/Hard/Good/Easy 评分和来源跳转状态；已接 KnowledgeCard apply 和 Seminar reviewSuggestion -> flashcard candidate -> Review Inbox Apply UI -> Spaced Review。 |
| Sync Export | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出、创建入口和待审冲突发送到 Review Inbox 的入口；默认只纳入已确认知识资产和复习历史，排除草稿、派生索引、API key 和待审冲突；安全的 KnowledgeCard 冲突可在 Review Inbox 中由用户 approve/apply 后解除 pending conflict，含 secret、未知 schema、无可追踪来源或非 KnowledgeCard 的冲突仍只能 dismiss/triage。完整云同步引擎、per-entity remote sync 和远端冲突合并器仍在剩余任务中。 |

入口计划以 `04_user_facing_activation_plan_zh.md` 为准；`implementation_status_zh.md` 只记录代码和验证证据。

## 6. 历史锚点

旧文档保留为历史事实，不在本目录内重写：

- `docs/ai/ai_status_roadmap_zh.md`
- `docs/ai/agent_system_architecture_zh.md`
- `docs/ai/rag_memory_plan_zh.md`
- `docs/superpowers/specs/2026-05-28-library-rag-optimization-design.md`
- `docs/superpowers/plans/2026-05-28-library-rag-optimization.md`

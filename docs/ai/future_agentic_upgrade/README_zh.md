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
7. `user_decision_summary_zh.md`：用产品决策视角说明哪些功能能用、哪些是内部地基、长期大块要怎么做以及做成后的效果。
8. `epics/`：每条能力线的执行规格。
9. `gates/`：跨 Epic 复用的质量、安全、资源和 rescue review gate。

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

本目录不是说“所有 Epic 都已产品化”。本节只放用户入口摘要；完整的功能使用路径、入口缺口、agent 任务和验收边界以 `04_user_facing_activation_plan_zh.md` 为准；代码级完成状态和验证命令以 `implementation_status_zh.md` 为准；如果要判断哪些能力值得继续投入，先看 `user_decision_summary_zh.md`。

如果只打开本 README，需要按下面两层理解：

- 用户要找入口：看本节表格的“用户怎么用”列。
- agent 要继续接产品闭环：看 `04_user_facing_activation_plan_zh.md` 的每条用户路径、Gate、验证命令和 `UFA-*` task。

下表的“已接入”只表示当前分支已有代码和测试证据，不等于 `main`、TestFlight 或用户已安装版本可用；未产品化、未发布或仍缺闭环的内容统一列在“当前还不能用”。

入口命名补充：

- 阅读页 `知识卡 / 研讨 / 图谱 / AI` 出现在选中文本后的横向菜单中，窄屏可能需要横向滑动菜单。
- `Review Inbox` 既可能直接出现在 Settings 的 AI 区顶层，也可以从 `Settings -> AI` 子页进入。
- AI Chat 的 Memory 入口是回答旁的书签图标，tooltip 为 `Memory actions / 记忆操作`，菜单项是 `Add to review inbox / 加入待审核队列`。
- 图片知识卡入口不会在打开图片时直接出现；需要先点图片工具栏的魔法棒 `AI Image Analysis / AI图片解析`，等解析结果弹层出现后再点 `Card / 知识卡`。
- AI Chat 的回答必须生成完成后，回答旁 `知识卡` 才可点击；streaming 中保持禁用。
- AI Chat 里的 `AI 研讨会` 当前会在 AI 对话页内展开 Seminar runtime 面板，并在当前会话中写入一张轻量 `AI 研讨会` 入口卡片；这张卡片随 `conversationV2` 历史保存，重新打开历史后可点击恢复 inline runtime。`AiSeminarDirectorState` 已能随本机 runtime state 记录第一片 Director 账本，并能把 completed run 中的开放问题标为 `askUser`、分歧标为 `refreshEvidence`，页面会显示主持人下一步；`askUser` 状态下用户可以输入回复并选择让角色回应、重新找证据或整理总结，回复只作为 human intervention 保存，不进入 formal evidence；其中“让角色回应”已会调用所选角色生成 follow-up turn 并更新 synthesis，“重新找证据”已会重新检索 evidence、重跑角色并更新 synthesis，“整理总结”已会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；当 completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会在启动 queued job 前自动重新检索 evidence、重跑角色，并在新证据仍无法解决分歧且预算耗尽时转为 `askUser`；但“完整分歧反驳 loop、Chat 消息流中的多角色多轮 Director 结构化卡片、per-run 多实例隔离”仍列在当前还不能用，不应描述为已接入。
- `Custom skills` 已做中文适配；中文界面中对应 `自定义技能`，英文界面仍显示 `Custom skills`。
- Sync 冲突批量处理入口在 `Review inbox` 中：切到 `Approved` 状态和 `Sync conflict` 类型后，安全可应用冲突会显示 `Apply Sync conflict`；部分失败后保留失败项并显示 `Retry Sync conflict`。

| 能力 | 用户怎么用 | 状态 |
| --- | --- | --- |
| 选中文本生成知识卡 | 阅读页选中文本 -> `知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；widget 覆盖菜单入口可见、点击 `Card` 后调用 producer、无注入 context/creator 时走 reader context fallback resolver 和默认 `SelectionKnowledgeCardProducer()`，写出 pending KnowledgeCard/ReviewItem，显示 Review feedback 并关闭菜单。 |
| 图片解析生成知识卡 | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；ImageViewer 工具栏点击、可注入分析流、弹层 `Card` 点击、pending KnowledgeCard 和 pending ReviewItem 已有 widget/service 证据；图片解析结果只作为 pending KnowledgeCard，不自动写长期资产。 |
| 一键开启研讨 | 阅读页选中文本 -> `研讨`，`Settings -> AI -> Seminar Mode / 研讨会模式`，AI 对话页左下角 `+` -> `AI 研讨会`，或 AI 对话页 `+` -> `选择风格` -> `研讨会设置`。 | 本分支已接入结构化 AI Seminar runtime/UI：展示 evidence、role turns、Shared Whiteboard、synthesis，支持取消、失败重试，并可把 traceable synthesis、候选卡和候选 flashcard 送入 Review Inbox；阅读页选中文本 `研讨` 现在会打开阅读页 AI 对话面板，并在当前 AI 对话页内展开 `AiSeminarRuntimePanel`，不会再把 `activeAiSkillId` 改成 `seminar_mode`；AI 对话页 Add-to-Chat sheet 也有独立 `AI 研讨会` 功能卡，点击后在当前 AI 对话页内展开同一类面板，带入当前输入框问题，但不改用户当前 `Choose style / 选择风格`，并把一张轻量 `AI 研讨会` 入口卡片写入当前 AI Chat 历史；历史重载后该卡片仍可点击重新打开 inline runtime；内嵌面板可关闭，也可跳到完整 Seminar runtime page；`Choose style / 选择风格` 中的 `研讨会设置` 只打开 Seminar 配置页，不会把当前风格切成 `seminar_mode`；Seminar settings 已增加 `Role prompt profiles / 角色提示词设置`，可编辑 `critical/supportive/synthesizer/verifier` 的显示名和 custom prompt，新 session 会把这些 profile 注入角色 prompt，恢复缓存也会保留 profile；角色 prompt 是普通设置，用户不应把 API key 或密钥写进去；当前还不是包含证据、角色发言、分歧、白板、总结和送审子视图的完整 AI Chat 多轮 Director 结构化卡片。阅读页选中文本入口会把真实 reader `SourceRef`、CFI、jump link、snippet 带入 Seminar session，并作为优先 evidence seed；页面级 widget 覆盖点击 `Send to Review` 后写入 pending synthesis/card/flashcard handoff；`Provider readiness` 区块会显示当前 provider、model、context/max output、Tools/Vision/Thinking 能力、Streaming 状态未知提示和成本状态；角色输出优先显示 provider 返回的 `Provider reported usage`，没有 provider usage metadata 时降级为 `Local token estimate` 和 `Provider billing may differ`；用户可在页面设置本地 `Role output token budget`、`Run token budget`，当 provider capability cache 带 pricing metadata 时还可设置估算 `Run cost cap USD`，超出本地 token 估算或估算美元 cap 后停止后续 Seminar 步骤；每次终态 run 会保存 billing snapshot，页面显示 `Billing reconciliation`，把 usage snapshot、pricing source、估算成本和 provider invoice 对账状态分开展示，默认 `Not connected` 且明确不是 provider 发票；每次启动会保存本机 `Background job` snapshot，并在本机账本保留最近 Seminar job 记录；页面显示当前 job id/status，取消、完成、失败和 needs-evidence 都会写入终态；运行中再次点击 Start 会创建 queued job 并显示 `Seminar job queue`，当前 job 终态后串行启动下一条 queued job；取消 queued job 不会误取消当前运行；完成、中断或带 traceable evidence checkpoint 的 Seminar state 会保存为本机恢复缓存，同一书籍/同一入口问题重新打开页面时显示 `Recovered local Seminar state`，换书或换选区会清掉旧 runtime/cache；重启时如果存在可追踪 evidence、provider/model/pricing 仍匹配且 completed turns 是合法连续前缀，会复用已保存 evidence，从第一个缺失角色继续；已有 completed role 不重跑，缺 tokenUsage 的 checkpoint turn 会补本地估算再进入最终 usage/cost；只有半截 active stream 时丢弃 partial 并重新生成缺失角色；checkpoint 无效、evidence 不可追踪、provider 已切换或 queued job 会降级为 `interrupted/retryable`；不继续旧 LLM stream，也不伪装 OS 后台执行；不自动写长期资产。 |
| AI Chat 回答生成知识卡 | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入显性 message action；阅读页选中文本 `AI` 按钮已有点击级测试覆盖打开 chat draft 并传 reader SourceRef，无有效 anchor 时不伪造 grounding；streaming 中 `知识卡` 按钮禁用且不会调用 producer；AI 回答流式文本更新会合并到 160ms UI flush 窗口，阅读页底部 AI 面板隐藏或多 tab 非活动 chat 时降到约 1000ms，从可见切到隐藏会重排已排队短 flush，并在重新可见时立即补刷 pending 文本，降低生成中阅读页滚动/翻页重建压力；关闭 streaming tab 会取消该 tab 的 generation subscription/timer；回答旁会显示 `可跳转来源` 或 `已标记不可用` 来源状态；从选中文本打开 AI 时保留精确 SourceRef，并随 `conversationV2` 历史持久化，历史重载后仍优先使用原始 reader SourceRef；如果用户把预填草稿改成无关问题，本轮不保存旧 reader SourceRef，短公共片段只靠碰巧包含不会保留精确 reader grounding；reader-grounded card 会带保守 `conceptRefs`；用户 Apply 后进入 draft ConceptGraph 候选和 pending relation ReviewItem。纯聊天只保留 conversation provenance，不直接写长期资产或正式 ConceptGraph。 |
| Responses 兼容模型提问 | `Settings -> AI -> Provider Center` 选择 OpenAI Responses 兼容 provider；`Use previous_response_id continuation` 可以保持开启。 | 本分支已接入运行时兼容降级：如果第三方 Responses 网关明确返回 `Unsupported parameter: previous_response_id`，当前请求会自动重建为不带 `previous_response_id` 的 replay body 并重试一次；正常支持 `previous_response_id` 的 provider 仍走 server-side continuation；非 `previous_response_id` 的 HTTP 400 不会被吞掉或误重试。 |
| 书库 Hybrid RAG 召回 | AI Chat、Seminar library fallback、agent tool 或 ConceptGraph 空态中调用 `semantic_search_library`。 | 本分支已把书库 RAG 从“文本无命中才走 vector fallback”推进到“FTS/BM25 精确文本召回 + 向量后端语义召回共同进入候选池”：只要允许 query embedding，`AiVectorSearchBackend` 会参与候选召回，结果 JSON 增加 `usedVectorRecall` 诊断；FTS 命中时 `usedVectorFallback=false`，但向量召回仍可让纯语义命中的 chunk 进入最终 hybrid/MMR/rerank 排序。当前默认 backend 是 ANN -> native -> exact：如果数据库已加载 Vec1/sqlite-vec 能力且对应 provider/model/dim 的 ANN 表完整，会优先用 `AiVec1VectorSearchBackend` 做语义召回，只 hydrate ANN winner 正文；如果 Vec1 不可用、ANN 表缺失或 shadow layer 不完整，会合并/降级到 native SQL seam 与 compact exact backend。exact backend 扫描阶段不取 `text/raw_text/context_text/embedding_json`，只为 top winner hydrate 正文，旧索引缺 `embedding_blob` 时按命中页批量回查 JSON fallback。本行是 extension-ready ANN 后端接入，不代表移动端已打包 sqlite-vec/Vec1 或完成发布级 ANN build job。 |
| 当前书语义检索资源保护 | 阅读页搜索、AI Seminar current-book evidence、`semantic_search_current_book` 工具会使用当前书语义索引；阅读页新搜索、清空搜索或离开页面会取消旧 semantic search，搜索进度会显示在目录搜索进度条。 | 本分支已把当前书向量搜索从一次性加载全书 chunk 改为分页扫描：扫描阶段不取 `text/raw_text/embedding_json`，只为命中结果回查正文；老索引缺少 `embedding_blob` 时按页批量回查 JSON fallback；搜索全局串行，向量页 scoring 通过 backend seam 进入默认 background isolate；服务层暴露取消 token 和 progress callback，并合并快速分页 progress 通知，只保留首个、间隔刷新、取消和最终进度；搜索会优先用 `ai_chunks_fts` 做 bounded FTS/BM25 候选预筛，只扫描候选 vector row；FTS5 不可用、MATCH 失败或无候选时，阅读页 fallback 扫描上限为 1024 行，Seminar evidence 和 agent tool fallback 扫描上限为 2048 行，达到上限时返回带 message 的降级结果；阅读页会取消 stale query，工具超时会取消底层 token，降低 OOM、发烫和翻页掉帧风险。 |
| 旧索引全局层补建 | `Settings -> AI Index / Library Index` -> `全局层索引` -> `补建`。 | 本分支已接入旧 chunk-only 索引补建：扫描已索引书籍，找出缺少 RAPTOR 全局层的书，用已有 chunk 生成 book-level summary、RAPTOR links 和当前 deterministic GraphRAG 派生层，不重新生成 embedding；页面显示检查、缺失数量、补建进度、取消按钮和完成/取消/失败提示；取消后未处理的书会保留为缺失，用户可再次补建；中文书籍即使当前 deterministic graph node 很少，只要 RAPTOR 全局层已存在，就不会被反复标记为缺失。 |
| 旧索引向量层升级 | `Settings -> AI Index / Library Index` -> `向量索引升级` -> `升级`。 | 本分支已接入 native vector shadow layer 前置入口：把旧书库索引中已有的 `embedding_blob` 或旧 `embedding_json` 转成紧凑 float32 shadow rows，写入 `ai_vector_index_rows` / `ai_vector_index_meta`；页面会显示缺失书籍数、完整准备书籍数、升级进度、取消按钮和完成/取消提示；不重新生成 embedding。默认检索后端会先尝试 Vec1 ANN 表，再降级到 native SQL seam 和 compact exact backend；`AiVec1VectorIndexBuilder` 已能按 provider/model/dim 从 shadow rows 重建独立 Vec1 virtual table，并写入 `vec1-ann` meta。当前 UI 入口只补 shadow rows，不会自动打包或构建 Vec1 ANN 表。 |
| Review Inbox | `Settings -> AI -> Review inbox`。 | 已有统一 UI；Settings 顶层 AI 区和 `Settings -> AI` 子页两条路径都有点击级导航测试；待审项显示状态、类型、证据摘录、来源标题/位置、不可用来源原因和打开来源动作；内容依赖 producer 写入。 |
| Memory 候选审核 | AI Chat 回答旁书签图标 `Memory actions / 记忆操作` -> `Add to Review inbox / 加入待审核队列`，再到 `Settings -> AI -> Review inbox` 审核、批准、应用。 | 本分支已接入 Memory source-specific apply adapter，并补齐回答旁书签 popup 的点击级测试：`MemoryWorkflowService.addToReviewInbox` 会同时写 MemoryCandidate 和统一 ReviewItem；streaming 中或空回答不会写 memory candidate；Review Inbox 的 `Approve -> Apply` 会先通过 `MemoryWorkflowService.applyCandidate` 追加到目标 daily/long-term Markdown，再推进 ReviewItem；`Dismiss` 会同步 MemoryCandidate 且不写 memory；无书内跳转的 conversation memory 会带证据摘录和不可跳原因。不会写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| Memory 独立浏览来源审计 | 首页底部 `Memory / 记忆` tab 打开 daily/long-term memory 列表；该 tab 默认隐藏，可先到 `Settings -> Home navigation / 首页导航` 打开；有来源的条目显示 `traceable/unavailable/unresolved` 状态，进入详情可查看 `Evidence` 并 `Open source`。 | 本分支已接入 `MemoryEntrySourceRefAdapter`、Memory home row source audit chips、Memory detail evidence list 和 source opener；来源来自已应用 `MemoryCandidate` 的只读投影，只按实际写入的 `text/displayText` 与条目正文匹配，long-term `MEMORY.md` 按 H1 分段 body 匹配；可跳来源打开 `paperreader://reader/open?...`，conversation-only memory 显示不可跳原因；long-term H1 分段不能被批量删除/打标签，避免误操作整份 `MEMORY.md`；不往 Markdown memory 写隐藏来源元数据，不绕过 Review 写资产。 |
| 旧划线/笔记来源审计 | 打开书籍笔记列表或全局搜索命中的笔记条目，查看 `Evidence`、`traceable/unavailable` 状态；点击无有效 book anchor 的旧笔记会提示不可跳原因，不进入空跳转。 | 本分支已接入 BookNote/highlight SourceRef audit：`BookNoteSourceRefAdapter` 生成 highlight/note SourceRef，`BookNoteTile` 复用 `SourceRefEvidenceList` 和 `PaperReaderSourceJumpAudit` 显示证据、来源位置、不可跳原因；Notes 列表和搜索结果会传入书名作为 source title，有有效 `bookId + cfi` 的笔记保持原文跳转，无有效 book anchor 的旧笔记只显示 snackbar 原因。 |
| 自定义 Skill 导入 | `Settings -> AI -> 自定义技能 / Custom skills` 粘贴 governed JSON -> `导入技能 / Import skill`，再到 `当前技能 / Active Skill` 选择已启用的自定义 skill。 | 本分支已接入 `CustomSkillStore`、导入页面、Settings 入口、Active Skill picker 点击级选择测试、中文界面适配和运行时 skill registry 合并；只接受 `CustomSkillContract(schemaVersion=1)`，导入时校验 unknown field、unknown scene、system scene、写工具、递归 sub-agent 和字段类型；运行时只暴露自定义 skill 声明过且通过 permission matrix 的只读工具，scene 不匹配时不注入 prompt，不加载 MCP 工具。禁用或校验失败的 skill 不进入 Active Skill 列表。 |
| 图谱可视化探索 | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、Settings 点击入口、阅读页选中文本入口、KnowledgeCard -> draft ConceptGraph producer 和空态 `Create draft candidate` 显性 action；可查看已有图谱、按选中文本筛选相关概念、查看局部节点-连线图、局部图谱摘要、局部路径、证据、draft/formal 状态和 orphan/broken link；从阅读页带书籍上下文进入时，页面还会读取当前书 `ai_graph_nodes / ai_graph_edges` 全局层，显示只读 `全书派生图谱 / Full-book derived graph` 预览。当前 producer 可从 `applied + traceable + conceptRefs` 的 KnowledgeCard 生成待审图谱关系；Seminar candidate card 和 reader-grounded AI Chat card 都可携带 `conceptRefs`，经 Review apply 后进入同一图谱候选链路；全书派生图谱只展示带 chunk SourceRef 的 derived-cache 节点和关系，不写正式 `ConceptGraphStore`、不进入 Review、不外发正文；`Create draft candidate` 使用关闭 query embedding、vector fallback、rerank 的本地文本检索，只让带 traceable chunk SourceRef 的 RAG/GraphRAG derived search result 生成 draft concept relation 和 pending ReviewItem；空态动作会显示已进入 Review 或跳过原因。 |
| RAG/GraphRAG 结果生成知识卡 | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡` -> `Settings -> AI -> Review inbox` 审核。 | 本分支已接入；使用同一条本地文本 library RAG search，关闭 query embedding、vector fallback、rerank，只把带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG 结果写成 pending KnowledgeCard，不写正式图谱或长期资产；写入后页面会提示已加入 Review inbox。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；知识卡或 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入 Settings 点击入口、队列、复习页、证据摘录预览、Again/Hard/Good/Easy 评分和来源跳转状态；已接 KnowledgeCard apply 和 Seminar reviewSuggestion -> flashcard candidate -> Review Inbox Apply UI -> Spaced Review。 |
| Sync Export / Remote Preview | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出、机器可读 sync bundle、创建入口、远端同步状态面板、待审冲突发送到 Review Inbox 的入口、远端 sync bundle preview、`Check remote changes / 检查远端变更` 前台只读检查、`Run safe remote sync / 运行安全远端同步` 前台一键安全编排、远端 incoming KnowledgeCard 发送到 Review Inbox、远端 review history 发送到 Review Inbox、远端冲突 triage 发送到 Review Inbox、安全远端 KnowledgeCard 冲突暂存到 Review Inbox、支持 optional base 的只读 remote merge planner、本机 remotePath baseline 持久化，以及带 rollback snapshot 和 ETag/CAS 条件写保护的 remote writeback executor；默认只纳入已确认知识资产和复习历史，排除草稿、派生索引、API key 和待审冲突；provider 级闭环覆盖安全本地 KnowledgeCard 冲突从 export handoff 到 Review approve/apply，再解除 pending conflict 并重新进入 export included 集合；远端状态面板显示 `Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed` 和下一步动作；`Check remote changes` 只读取远端 bundle 并显示 incoming/conflict 摘要和只读提示，不上传、不应用、不发送 Review；远端 preview 读取配置的 SyncClient/WebDAV bundle，并在存在同 remotePath 的上次成功上传 baseline 时做三方 diff；无 baseline、baseline 损坏、路径不匹配、重复 ID、future schema 或 unsafe payload 会降级为保守 preview；`Run safe remote sync` 会先 preview，存在 incoming/conflict blocker 时只把安全远端 incoming、review history、staged KnowledgeCard conflict 和 preview-only conflict 批量送入 Review，不执行上传；无 blocker 时才走受保护 writeback；安全远端 incoming KnowledgeCard 会降级为 pending + AI draft，安全远端 review history 会降级为 pending ReviewItem，安全远端 KnowledgeCard 冲突会先写入 staged conflict store，用户 Apply 后才替换为本机已确认知识卡，ReviewItem 写入失败会回滚 staged entry；旧的远端冲突 triage 入口仍只支持 dismiss，不显示 approve/apply；写回前会检查远端 incoming/conflict，存在会阻止写出；写回使用 `If-Match` 或 `If-None-Match`，远端在 preview 后变化或创建时会停止上传并提示重新 preview；provider 不暴露 ETag/CAS 时会拒绝覆盖并显示 concurrency guard unavailable；写回成功后才更新本机 baseline，写回失败会恢复旧远端 bundle 或删除半写入的新 bundle，并在页面显示 rollback 状态。 |

## 6. 当前还不能用

下表是本分支没有产品化的边界。它们不是“隐藏入口”，也不应被解释成当前用户已经可以使用。

| 还不能用的能力 | 当前边界 | 下一步 agent task |
| --- | --- | --- |
| 完整云同步引擎 | 目前有本地安全 manifest、Markdown、HTML、Anki TSV、机器可读 sync bundle、远端 bundle preview、`Check remote changes` 前台只读远端检查、远端同步状态面板、`Run safe remote sync` 前台安全编排、远端 incoming KnowledgeCard Review 导入、远端 review history Review 导入、远端冲突 Review triage handoff、安全远端 KnowledgeCard 冲突 staged Review 恢复、安全 KnowledgeCard 冲突的本地 Review 恢复、Review Inbox 已审核安全冲突批量 apply/retry、只读 remote merge planner、本机 remotePath baseline 持久化、带 rollback snapshot 的 remote writeback executor，以及 WebDAV ETag/CAS 条件写防并发覆盖；还没有跨设备后台同步任务和 release promotion。 | 继续拆跨设备后台同步和发布版迁移 gate。 |
| AI Chat 内嵌多轮 Seminar | AI Chat 已有 `AI 研讨会` 功能卡、当前页内嵌 `AiSeminarRuntimePanel`、轻量历史入口卡片、完整 runtime page 跳转和 `研讨会设置` 入口；Seminar settings 已可编辑角色显示名和 custom prompt；`AiSeminarDirectorState` 第一片已进入 runtime state 和本机恢复 JSON，可记录轮次、已完成角色、证据账本、白板账本、分歧 id、用户插话和下一步 intent；completed run 留下 open question 时会把下一步标为 `askUser`，留下 disagreement 且仍有轮次预算时会标为 `refreshEvidence`，status banner 会显示主持人下一步；`askUser` 状态下页面提供用户回复输入框、目标角色选择、让角色回应、重新找证据和整理总结动作；用户点击“让角色回应”后会把回复保存为 human intervention，再调用所选角色生成 follow-up turn 并更新 synthesis；用户点击“重新找证据”后会保存 human intervention、重新检索 evidence、重跑角色并更新 synthesis；用户点击“整理总结”后会保存 human intervention，用现有 evidence/turns 执行本地 synthesis 并把 Director 收束为 `end`，用户回复不进入 formal evidence；当 completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会自动刷新 evidence、重跑角色并更新 synthesis，刷新后仍有分歧且预算耗尽时转为 `askUser`。还没有完整 AI Chat message part 的证据/角色/分歧/白板/总结/送审子视图，也没有完整反驳轮、角色启用状态、证据策略或工具范围配置。 | 继续执行 `UFA-C02-T18` 到 `UFA-C02-T22` 的剩余部分：role profile 剩余策略、完整 rebuttal loop、结构化 Chat run card 子视图和 per-run 多实例隔离。 |
| Seminar OS 后台执行、queued job 重启确认和 provider 发票导入 | Seminar runtime 已能流式、取消、重试、送 Review，并能显示 provider/model capability、成本未知原因、provider-reported token usage、本地 token 估算 fallback、本地 role/run token budget、pricing metadata 驱动的估算 `Run cost cap USD`、billing snapshot / reconciliation UI、本机 state 恢复、当前 `Background job` snapshot、最近本机 job 账本和本机串行 queued job scheduler；running state 重启后如果已有可追踪 evidence 且 provider/model/pricing 仍匹配当前配置，会保留 job id、复用已保存 evidence，并从第一个缺失角色继续；已有 completed role prefix 会跳过不重跑，只有 active partial stream 时丢弃 partial 并重新生成缺失角色；checkpoint 无效、evidence 不可追踪、provider 已切换或 queued job 会标记为 interrupted/retryable。当前没有并发并行 Seminar，没有 OS/background execution gate，没有旧 LLM stream 原地续传，也没有连接 provider invoice import API，页面会把 invoice reconciliation 标为 `Not connected` 或显示失败原因。 | 继续拆 OS/background execution gate、queued job 重启确认和 provider idempotency；真实 provider invoice import 需要另建 provider-specific adapter、鉴权和只读账单导入 gate。 |
| sqlite-vec/ANN 实验后端 | 当前书搜索已经完成分页、串行、取消、background isolate scoring、progress 合并、stale query 丢弃、bounded FTS/BM25 候选预筛、前台/tool fallback scan budget 和 synthetic large-book scan acceptance；书库 RAG 已经改成 hybrid recall pipeline，向量后端不再只是文本 miss 后的兜底；exact fallback backend 扫描阶段也不再加载正文大字段；当前 `kAiIndexDbVersion = 12`，已有 `ai_vector_index_rows/meta` shadow schema、旧索引向量层升级入口、Vec1 table builder、`vec1-ann` meta、ANN -> native -> exact 默认 backend 和 `AiVectorRecallOverlapGate`。它仍不是已打包的 sqlite-vec/Vec1 生产能力：当前代码会在 Vec1 function/table 存在时使用 ANN，否则自动降级；移动端 extension/package、可取消 ANN build job、删除书清理和 provider/model 失效还没产品化。 | 下一步拆真实 sqlite-vec/Vec1 package/extension adapter、ANN index build job UI、platform packaging gate、删除书清理和 provider/model 失效；候选 ANN backend 必须继续通过固定 fixture 的 ANN/exact topK overlap gate。 |
| 复杂无限画布式图谱 | 当前 ConceptGraph 是局部探索、dossier、本地摘要、轻量节点-连线图；Settings 入口可选择已有全局层的已索引书查看只读全书自动图谱，阅读页入口可直接看当前书全局层派生图谱；仍不做无限画布、缩放手势或跨书外部知识扩展。 | 若要做画布，先定义移动端资源 gate、证据可见性和 graph asset ownership。 |
| 发布版可用 | 本表描述 `codex/future-agentic-upgrade` 分支，不代表 `main`、TestFlight 或用户已安装版本。 | 走 release promotion gate：合并、构建、回归、发布说明和用户迁移说明。 |

入口计划以 `04_user_facing_activation_plan_zh.md` 为准；长期取舍以 `user_decision_summary_zh.md` 为准；`implementation_status_zh.md` 只记录代码和验证证据。

## 7. 历史锚点

旧文档保留为历史事实，不在本目录内重写：

- `docs/ai/ai_status_roadmap_zh.md`
- `docs/ai/agent_system_architecture_zh.md`
- `docs/ai/rag_memory_plan_zh.md`
- `docs/superpowers/specs/2026-05-28-library-rag-optimization-design.md`
- `docs/superpowers/plans/2026-05-28-library-rag-optimization.md`

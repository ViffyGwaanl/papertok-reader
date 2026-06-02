# User-Facing Activation Plan

> 状态：In Review  
> 用途：把 agentic upgrade 的底层能力转成用户能找到、能触发、能验证的产品入口。

本文件只回答三个问题：

- 用户现在从哪里用。
- 哪些能力已有底层 artifact，但还没有产品入口。
- 剩余 Agent Task 怎样把能力接成可用闭环。

入口前置条件和命名：

- 阅读页入口来自选中文本后的横向菜单；窄屏上 `知识卡 / 研讨 / 图谱 / AI` 可能需要横向滑动才能看到。
- `Review Inbox` 有两个可达路径：Settings 顶层 AI 区的直达入口，以及 `Settings -> AI -> Review inbox`。
- AI Chat 的 Memory 入口是回答旁书签图标；tooltip 是 `Memory actions / 记忆操作`，菜单项是 `Add to Review inbox / 加入待审核队列`。
- 图片知识卡必须先在 ImageViewer 点工具栏魔法棒 `AI Image Analysis / AI图片解析`，解析结果弹层出现后才会显示 `Card / 知识卡`。
- AI Chat 回答旁 `知识卡` 只在回答完成后可用；streaming 中禁用，不会写 store。
- AI Chat 左下角 `+` 打开 Add-to-Chat sheet；其中 `AI 研讨会` 会在当前 AI Chat 页面内展开 Seminar runtime 面板，并在当前会话里写入一张轻量 `AI 研讨会` 历史入口卡片；它不等同于 `Choose style / 选择风格`；`Choose style / 选择风格` 内的 `研讨会设置` 只打开 Seminar 配置页，不会切换当前 active skill。当前内嵌面板复用现有 runtime；轻量卡片随 `conversationV2` 保存，历史重载后可点击重新打开 inline runtime；`AiSeminarDirectorState` 第一片已可随 runtime state 保存，并能把 completed run 中的 open question 标为 `askUser`、disagreement 标为 `refreshEvidence` 且在状态区显示主持人下一步；`askUser` 状态下用户可以输入回复并选择让角色回应、重新找证据或整理总结，回复只保存为 human intervention，不进入 formal evidence；其中“让角色回应”已会调用所选角色生成 follow-up turn 并更新 synthesis，“重新找证据”已会重新检索 evidence、重跑角色并更新 synthesis，“整理总结”已会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；completed run 完成后会在 synthesis 后显示 `Continue discussion / 继续讨论`，即使没有 open question，用户也能继续追问某个角色、要求重找证据或重新整理总结，输入仍只保存为读者回合；当 completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会自动重新检索 evidence、重跑角色，并在预算耗尽仍有分歧时转为 `askUser`；App 重启时如果 active Seminar 可从 traceable checkpoint 续跑，带完整 session 的 queued Seminar 会继续排队并在 active 完成后自动启动；但还不是包含证据、角色发言、分歧、白板、总结和送审子视图的完整 Chat message part，也没有完整分歧反驳 loop。
- `Custom skills` 已完成中文适配；中文界面中对应 `自定义技能`，英文界面仍显示 `Custom skills`；AI Chat `+ -> Choose style / 选择风格` 里，自定义 skill 行也可直接点 `Custom skills / 自定义技能` 进入同一个导入/启用/删除页面，且不会改变当前 active skill；普通内置 skill 行可点 `Skill settings / 技能设置` 保存该 skill 的个人提示词补充，不会改变当前 active skill。
- Review Inbox 只有 producer 写入 pending item 后才会显示内容；空 inbox 不代表入口不存在。
- Review Inbox 批量处理同步冲突的入口是 `Approved` 状态 + `Sync conflict` 类型筛选；只对 `canApply=true` 且有可追踪 SourceRef 的安全冲突显示 `Apply Sync conflict`，部分失败后失败项留在 approved 可用 `Retry Sync conflict` 重试。

## 1. 当前用户可用性

| 能力 | 用户入口 | 当前状态 | 真实边界 |
| --- | --- | --- | --- |
| Review Inbox | `Settings -> AI -> Review inbox`，以及 Settings 顶层知识审核入口。 | 已接入 UI，可展示、批准、忽略、应用 KnowledgeCard、ConceptGraph relation 和 flashcard candidate 类型审批项；每个有证据的待审项会显示证据摘录、来源标题/位置、不可用来源原因和打开来源动作；Settings 顶层 AI 区和 `Settings -> AI` 子页两条路径都有点击级导航证据。 | 只有 producer 写入 `ReviewItemStore` 后，用户才会看到内容；空 inbox 显示空态，不代表入口失败。 |
| 选中文本 -> KnowledgeCard | 阅读页选中文本 -> `知识卡`。 | 本分支已接入 `SelectionKnowledgeCardProducer` 和选中菜单入口，选中文本会进入 KnowledgeCard store 与 Review Inbox。 | 默认只进入 Review，不写长期记忆、不写笔记、不写 spaced review。 |
| 图片解析 -> KnowledgeCard | 阅读页点开图片 -> `AI Image Analysis / AI图片解析` -> `Card / 知识卡`。 | 本分支已接入 `ImageAnalysisKnowledgeCardProducer`、图片解析结果弹层入口和 ImageViewer 工具栏点击级路径，解析结果会进入 KnowledgeCard store 与 Review Inbox。 | 默认只进入 Review，不写长期记忆、不写笔记、不写 spaced review；SourceRef 使用当前阅读位置的 book/cfi/href 回跳；图片本体不写入 card payload。 |
| 选中文本 / AI Chat -> AI Seminar | 阅读页选中文本 -> `研讨`，`Settings -> AI -> Seminar Mode / 研讨会模式`，AI Chat 左下角 `+` -> `AI 研讨会`，或 AI Chat `+` -> `选择风格` -> `研讨会设置`。 | 本分支已接入结构化 runtime：用户可启动 role-by-role Seminar，查看 evidence、角色输出、Shared Whiteboard、synthesis，并把 traceable synthesis、候选卡和候选 flashcard 送入 Review Inbox；阅读页选中文本 `研讨` 会打开阅读页 AI Chat，并在当前 AI Chat 页面内展开 `AiSeminarRuntimePanel`，带入选中文段和真实 reader `SourceRef`，不会把 `activeAiSkillId` 改成 `seminar_mode`，也不会覆盖用户当前 `Choose style`；AI Chat 的 Add-to-Chat sheet 显示独立 `AI 研讨会` 卡片，点击后在当前 AI Chat 页面内展开同一类 runtime panel，带入当前输入框问题，并向当前 `conversationV2` 写入轻量 `AI 研讨会` 历史入口卡片；历史重载后该卡片可点击重新打开 inline runtime；内嵌面板可关闭，也可跳到完整 Seminar runtime page；`Choose style / 选择风格` 内的 `研讨会设置` 只打开配置页，不改变当前 active skill；阅读页选中文本入口会把真实 reader `SourceRef`、CFI、jump link、snippet 带入 Seminar session，并在 evidence broker 中优先生成 `Reader selection` evidence；Seminar 页面会在启动前显示 `Provider readiness`，列出当前 provider、model、context/max output、Tools/Vision/Thinking 能力、Streaming 状态未知提示和成本状态；角色完成后优先显示 provider 返回的 `Provider reported usage`，没有 provider usage metadata 时显示 `Local token estimate`、input/output 估算和 `Provider billing may differ` 提示；页面提供本地 `Role output token budget`、`Run token budget`，当 provider capability cache 带 pricing metadata 时还启用估算 `Run cost cap USD`；页面保存当前本机 `Background job` snapshot 和最近 job 账本并显示当前 job id/status，可在同一书籍/同一入口问题恢复本机保存的 completed/cancelled/failed/interrupted Seminar state，并显示 `Recovered local Seminar state`；如果重启时 running state 已有可追踪 evidence 且 provider/model/pricing 仍匹配当前配置，会复用已保存 evidence，从第一个缺失角色继续；已有 completed role 会跳过不重跑，缺 tokenUsage 的 checkpoint turn 会补本地估算；运行中再次点击会显示 `Queue Seminar`，把新问题加入本机串行队列，页面展示 `Seminar job queue`；当同一恢复快照存在可续跑 active job 和带完整 session 的 queued job 时，queued job 会保持 queued 并在 active 续跑完成后自动启动；`AiSeminarDirectorState` 第一片会随 runtime state 记录轮次、已完成角色、证据账本、白板账本、分歧 id、最后一次用户插话和下一步 intent；completed run 留下 open question 时会标记 `askUser`，留下 disagreement 且仍有轮次预算时会标记 `refreshEvidence`，状态区显示主持人下一步；用户在 `askUser` 中选择“让所选角色回应”会追加目标角色 follow-up turn 并更新 synthesis，选择“重新找证据”会重新调用 evidence broker、重跑角色并更新 synthesis，选择“整理总结”会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；completed run 完成后会在 synthesis 后显示 `Continue discussion / 继续讨论`，即使没有 open question，也可让用户继续追问某角色、重找证据或再次整理总结，输入仍只写 `lastUserIntervention`；completed run 只留下 disagreement 且仍有 maxRounds 刷新预算时，会自动刷新 evidence、重跑角色；刷新后仍有分歧且预算耗尽时转为 askUser。 | 阅读页优先 current book evidence，且选中文段本身会先作为可跳回原文的 evidence；AI Chat 入口没有 reader anchor 时只带入问题文本和当前阅读书籍上下文，不伪造选区 SourceRef；Settings 独立入口没有 current book 时会走 library fallback。AI Chat 内嵌面板仍复用当前全局 Seminar runtime state；轻量历史卡片只是可恢复入口，不是完整结构化 chat message part，不支持每条消息多实例并行；DirectorState 已能驱动 askRole follow-up、用户触发的 refreshEvidence、completed continuation composer、disagreement 预算内自动 refresh 和 synthesize，但还没有驱动完整多轮分歧检测、结构化 rebuttal turn 或澄清调度；Seminar synthesis 本身只进入 Review，不自动应用；候选卡和候选 flashcard 仍需用户在 Review Inbox 中批准/应用后才成为长期资产或复习项；provider readiness 只读本地 Provider Center 配置和 capability cache，不记录 API key；provider token usage 只表示 provider/SDK 回传的 token metadata；估算美元成本来自 pricing metadata 与 token usage，不等于真实 provider 发票；缺少 pricing metadata 时继续显示成本未知原因且禁用美元 cap；取消当前 job 只命中当前活跃 job id，取消 queued job 不会误取消当前运行；当前 job 终态后才串行启动下一条 queued job；恢复续跑只信任 traceable evidence checkpoint 和合法 completed role prefix；只有 half-stream partial 时丢弃 partial 并重新生成缺失角色；同一恢复快照里带完整 session 的 queued job 可在 active 完成后启动；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时会标记为 interrupted/retryable；它不会继续旧 LLM stream，也不是 OS 后台执行；换书或换选区打开 Seminar 会丢弃旧 runtime/cache，不显示不属于当前入口的旧研讨。 |
| AI Chat 普通解释 -> KnowledgeCard | 阅读页选中文本 -> `AI` -> 等回答完成 -> 回答旁 `知识卡`。 | 本分支已接入 `AiChatKnowledgeCardProducer` 和回答旁显性 `知识卡` action；streaming 中 `知识卡` 按钮禁用且不会调用 producer；AI 回答流式文本更新会合并到 160ms UI flush 窗口，阅读页底部 AI 面板隐藏或多 tab 非活动 chat 时降到约 1000ms，重新可见时立即补刷 pending 文本，减少生成中阅读页滚动/翻页重建压力；回答旁显示 `可跳转来源` 或 `已标记不可用` 来源状态，tooltip 解释是否能跳回原文；选中文本 `AI` 入口点击级测试覆盖打开 chat draft 并传入 reader SourceRef；选中文本进入 AI 草稿时会带上精确 reader SourceRef，并随 `conversationV2` 历史持久化，点击后写入 KnowledgeCard store 与 Review Inbox；reader-grounded card 会带保守 `conceptRefs`。 | 必须用户显式点击；不会在回答生成时直接写 KnowledgeCard 或 ConceptGraph；如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不保存旧 reader SourceRef；短公共片段只靠碰巧包含不会保留精确 reader grounding；无有效 anchor 的选中文本只打开 AI draft，不伪造 reader grounding；用户在 Review Inbox 中 Apply 后，带 `conceptRefs` 的 reader-grounded AI Chat card 才会生成 draft ConceptGraph relation 和 pending relation ReviewItem；纯聊天 card 不生成 `conceptRefs`；没有持久化 reader SourceRef 的旧历史只保留 conversation provenance，不用当前阅读位置伪造 reader grounding；这不是完整真机性能证明，仍需 release/profile gate。 |
| Responses 兼容模型提问 | `Settings -> AI -> Provider Center` 选择 OpenAI Responses 兼容 provider，按 provider 配置打开或保留 `Use previous_response_id continuation`。 | 本分支已接入 `previous_response_id` 兼容 fallback：当 Responses provider 返回 HTTP 400 且错误体明确指向 `Unsupported parameter: previous_response_id` 时，当前请求会标记该运行时实例不再发送 `previous_response_id`，并用同一消息/工具输出重建 replay body 重试一次；正常 provider 仍使用 server-side continuation。 | 只对明确的 `previous_response_id` unsupported 生效；非该参数的 HTTP 400 保留原始错误并不重试；fallback 是当前运行时实例内的兼容保护，不是 provider capability schema 的永久迁移；仍需用户在 Provider Center 正确配置 base URL、model、streaming 和 reasoning 选项。 |
| 书库 Hybrid RAG 召回 | AI Chat、Seminar library fallback、agent tool、ConceptGraph 空态或其它调用 `semantic_search_library` 的入口。 | 本分支已把书库 RAG 从“文本没有候选才走向量 fallback”改为“FTS/BM25 精确文本召回 + `AiVectorSearchBackend` 语义召回共同进入候选池”：只要允许 query embedding，向量后端都会参与召回，结果 JSON 会显示 `usedVectorRecall`；FTS 命中时 `usedVectorFallback=false`，但纯语义命中的 chunk 仍可进入 hybrid/MMR/rerank 排序；默认 backend 是 ANN -> native -> exact：Vec1/sqlite-vec function 和 per-provider/model/dim ANN 表存在且完整时优先走 `AiVec1VectorSearchBackend`，只 hydrate ANN winner 正文；Vec1 不可用、ANN 表缺失或 shadow layer 不完整时合并/降级 native SQL seam 和 compact exact backend。 | 当前代码已经有 extension-ready ANN 路径，但还不是已打包的 sqlite-vec/Vec1 发布能力；ConceptGraph 空态和 RAG KnowledgeCard 本地文本入口显式关闭 query embedding、vector fallback 和 rerank，因此不外发正文；正式 evidence 仍必须有 SourceRef 和 chunk snippet；老索引缺 `embedding_blob` 时 exact backend 仍会按命中页批量回查 `embedding_json`。 |
| 当前书语义检索资源保护 | 阅读页搜索、AI Seminar current-book evidence、`semantic_search_current_book` 工具。 | 本分支已把当前书语义搜索改成分页向量扫描：扫描页只取 id、章节、hash、context 和 vector blob/norm，不取 `text/raw_text/embedding_json`；只为 topK 命中回查正文；老索引缺少 blob 时按页批量回查 `embedding_json`；搜索服务全局串行，页内/页末让出 UI isolate，向量扫描 progress 会合并快速页通知并强制保留取消/最终状态，工具 registry 也默认串行该工具；搜索会优先用 `ai_chunks_fts` 做 bounded FTS/BM25 候选预筛，只扫描候选 vector row；FTS5 不可用、MATCH 失败、无候选或候选过期时，阅读页 fallback 扫描上限为 1024 行，Seminar evidence 和 agent tool fallback 扫描上限为 2048 行；阅读页 stale query 会取消旧 token，目录搜索进度条显示 semantic progress，工具 timeout 会取消底层搜索。 | 这是 OOM/发热/掉帧的保护层，不是完整高性能向量引擎；有 FTS 候选时不会完整扫描全书向量；无 FTS 候选、FTS 不可用或候选过期时，用户入口只做预算内分页 fallback，达到上限会返回带 message 的降级结果；没有实现 sqlite-vec/ANN 或自动索引重建提示。 |
| 旧索引全局层补建 | 批量路径：`Settings -> AI Index / Library Index` -> `全局层索引` -> `补建`；当前书路径：`Settings -> AI -> Concept graph / 概念图谱` 或阅读页选中文本 -> `图谱/Graph` -> 当前书全书图谱为空态 -> `立即生成全局层索引`。 | 本分支已接入旧 chunk-only 索引的全局层补建入口：批量页检查已索引书籍是否缺少 RAPTOR 全局层，显示缺失数量、补建进度、取消按钮和完成/取消/失败提示；服务层用已有 chunk rebuild book-level summary、RAPTOR links 和当前 deterministic GraphRAG 派生层，不重新生成 embedding；ConceptGraph 当前书为空态会检查该书 chunk/global-layer 状态，有旧 chunk 索引时可直接补建该书全局层，完成后刷新当前书只读全书派生图谱；取消后未处理的书会继续显示为缺失，用户可再次补建；中文书籍即使当前 deterministic graph node 很少，只要 RAPTOR 全局层存在，就不会被反复标记为缺失。 | 这是旧索引升级为可被 RAPTOR/GraphRAG 派生层使用的补建入口，不是 sqlite-vec/ANN；当前 deterministic graph term extractor 对纯中文概念节点仍弱，完整中文全书关系图需要后续中文短语/实体抽取或 LLM-backed concept extraction gate。 |
| 旧索引向量层升级 | `Settings -> AI Index / Library Index` -> `向量索引升级` -> `升级`，再点 `ANN 向量索引` -> `构建`。 | 本分支已接入 native vector shadow layer 升级入口：页面检查已索引书籍是否缺少 `ai_vector_index_rows`，显示可升级书籍数、完整准备书籍数、升级进度、取消按钮和完成/取消提示；服务层用已有 `embedding_blob` 或旧 `embedding_json` 生成紧凑 float32 shadow rows，不重新生成 embedding；`AiVec1VectorIndexBuilder` 已能从 shadow rows 按 provider/model/dim 建立独立 Vec1 virtual table，并写入 `vec1-ann` meta；`ANN 向量索引` tile 会检查 Vec1/sqlite-vec 加载状态、shadow rows、ANN group/row 缺口，并在可用时触发可取消构建；默认向量后端会先尝试 Vec1 ANN，再降级 native SQL seam 与 exact backend；删除书籍时会显式清理该书的 RAPTOR/GraphRAG、native vector shadow、ANN 行和对应 meta。 | 当前不自动打包或加载 Vec1/sqlite-vec 扩展；未加载扩展时页面显示 ANN 暂不可用并保持 fallback；真实 package/extension adapter、平台打包和 provider/model 失效仍需后续任务；候选 ANN 后端必须继续通过现有 `AiVectorRecallOverlapGate`。 |
| AI Chat -> Memory 候选审核 | AI Chat 回答旁书签图标 `Memory actions / 记忆操作` -> `Add to Review inbox / 加入待审核队列` -> `Settings -> AI -> Review inbox`。 | 本分支已接入 MemoryCandidate 到统一 ReviewItem 的 handoff、Memory source-specific apply/dismiss adapter 和 Review Inbox Apply UI；回答旁书签 popup 已有点击级测试覆盖 `Add to review inbox` handoff。 | Memory 候选必须经用户批准和应用；Apply 先追加到目标 daily/long-term Markdown，再推进 ReviewItem；Dismiss 不写 memory；streaming 中或空回答不会写 memory candidate；无书内跳转的 conversation memory 会显示证据摘录和不可跳原因；不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| Memory 独立浏览 SourceRef 审计 | 首页底部 `Memory / 记忆` tab 打开 daily/long-term memory 列表，再进入条目详情；该 tab 默认隐藏，可先到 `Settings -> Home navigation / 首页导航` 打开。 | 本分支已接入 `MemoryEntrySourceRefAdapter`、Memory home row source audit chips、Memory detail `SourceRefEvidenceList` 和 `Open source` action；只从已应用 MemoryCandidate 只读投影 SourceRef，按目标文档与条目 body 匹配，long-term `MEMORY.md` 按 H1 分段 body 匹配。 | 匹配只认实际写入 memory 的 `text/displayText`，不能只靠 summary 命中；不往 Markdown memory 写隐藏来源字段；没有 book anchor 的 conversation memory 只显示 unavailable/unresolved；可跳来源只使用合法 `paperreader://reader/open?...`；long-term H1 分段不能被批量删除/打标签，避免误操作整份 `MEMORY.md`；浏览页不创建 KnowledgeCard、ReviewItem、ConceptGraph、SpacedReview、Sync 或 Note。 |
| 旧划线/笔记 SourceRef 审计 | 书籍笔记列表或搜索结果里的笔记条目。 | 本分支已接入 `BookNoteSourceRefAdapter`、`BookNoteTile` source audit、`SourceRefEvidenceList` 和 `PaperReaderSourceJumpAudit`；条目显示 Evidence、可跳转/不可跳状态、来源书名/章节和不可跳原因。 | 有有效 `bookId + cfi` 的条目保持原文跳转；无有效 book anchor 的旧条目点击时显示不可跳原因，不调用阅读页空 CFI 或无效 book anchor 跳转；不写 KnowledgeCard、ReviewItem、Memory、ConceptGraph、SpacedReview 或 Sync。 |
| Custom Skill 导入 | `Settings -> AI -> 自定义技能 / Custom skills` 粘贴 governed JSON -> `导入技能 / Import skill`，再到 `当前技能 / Active Skill` 或 AI Chat `+ -> Choose style / 选择风格` 选择启用后的自定义 skill；在 AI Chat `Choose style` 里可从自定义 skill 行点 `Custom skills / 自定义技能` 回到配置页。 | 本分支已接入导入页面、`CustomSkillStore`、Settings 入口、AI Chat Choose style 自定义 skill 配置入口、中文界面适配、`AiSkillRegistry` 合并、Active Skill picker 点击级选择测试和 LangChain runtime 工具收窄；AI Chat Choose style 列表已改为可滚动，skill 较多时不溢出；普通内置 skill 行也可点 `Skill settings / 技能设置` 保存个人提示词补充。 | 只接受 `CustomSkillContract(schemaVersion=1)`；unsafe JSON 不落库、不激活；禁用 skill 不进入 Active Skill 列表；点击配置入口不改变当前 active skill；普通内置 skill 的个人提示词补充不能覆盖隐私、证据、工具权限和写入确认规则；运行时只保留自定义 skill 声明过、当前 scene 可用、permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具。 |
| ConceptGraph / WikiLinks Explorer | `Settings -> AI -> Concept graph / 概念图谱`，或阅读页选中文本 -> `图谱/Graph`。 | 本分支已接入 Explorer、Settings 点击入口、选中文本入口、KnowledgeCard -> draft ConceptGraph producer、Seminar candidate card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路、reader-grounded AI Chat card -> conceptRefs -> KnowledgeCard -> ConceptGraph 候选链路，以及空态 `Create draft candidate` 显性 action：可列出现有概念、按选中文本筛选相关概念、打开 dossier、查看局部节点-连线图、局部图谱摘要、局部路径、draft/formal 状态、evidence 状态和 orphan/broken link，并可把 derived RAG/GraphRAG result 写成待审图谱候选；Settings 入口会列出已完成全局层索引的书，用户可直接选择一本书查看只读 `全书自动图谱 / Full-book auto graph`；从阅读页进入时会带入当前 bookId 并直接显示当前书全局层只读 `全书派生图谱 / Full-book derived graph`；如果当前书已有旧 AI chunk 索引但缺少全局层，空态会显示 `立即生成全局层索引`，补建成功后刷新当前书全书派生图谱；空态动作会显示已进入 Review 或跳过原因。 | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或带 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，会生成 draft node/edge 和 pending relation ReviewItem；全书派生图谱只读取 `ai_graph_nodes / ai_graph_edges / ai_graph_node_chunks / ai_chunks`，只展示带 chunk SourceRef 的 derived-cache 节点和关系，不写正式 `ConceptGraphStore`、不进入 Review、不外发正文；Settings 书籍选择只列出已有全局层的已索引书，不自动外发正文；当前书空态补建只复用已有 chunk，不重新生成 embedding；空态草稿入口使用本地文本检索，关闭 query embedding、vector fallback 和 rerank；AI Chat 不直接调用 RAG/GraphRAG producer，不自动创建正式节点；当前图形视图是移动端轻量局部 canvas 和全书只读预览，不是无限画布。 |
| RAG/GraphRAG -> KnowledgeCard | 阅读页选中文本 -> `图谱/Graph` -> 无相关概念空态 -> `Card / 知识卡`。 | 本分支已接入 `RagEvidenceKnowledgeCardProducer` 和 ConceptGraph 空态 Card action；本地 RAG/GraphRAG 结果可进入 KnowledgeCard store 与 Review Inbox；写入后页面会提示已加入 Review inbox。 | 只接受带 traceable chunk SourceRef 和可保存 chunk snippet 的 RAG evidence；derived summary 只作为 explanation，正式 quote/evidence 使用书内 chunk snippet；不自动写图谱、长期记忆、笔记或 spaced review。 |
| Spaced Review | `Settings -> AI -> Spaced review / 间隔复习`；KnowledgeCard 或 Seminar 候选 flashcard 在 Review Inbox 中 `Apply` 后入队。 | 本分支已接入 Settings 点击入口、`.knowledge/spaced_review_items_v1.json`、复习页、证据摘录预览、Again/Hard/Good/Easy 评分、来源跳转状态；Seminar 的 `reviewSuggestion` 会作为 flashcard candidate 进入 Review，并可由 Review Inbox Apply UI 应用到 Spaced Review。 | KnowledgeCard apply 和 flashcard candidate apply 已接入；跨设备同步还没接。 |
| Sync / Export / Remote Preview 知识资产 | `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。 | 本分支已接入安全 manifest 预览、Markdown 学习导出、HTML study report、Anki TSV 导出、机器可读 sync bundle、创建入口、远端同步状态面板、`Send conflicts to Review` 冲突 handoff、`Preview remote sync` 远端 bundle 预览、`Check remote changes` 前台只读远端检查、`Run safe remote sync` 前台一键安全编排、`Send remote incoming to Review` 安全远端 KnowledgeCard 导入、`Send remote review history to Review` 安全远端复习记录导入、`Stage safe remote card conflicts to Review` 安全远端 KnowledgeCard 冲突暂存导入、`Send remote conflicts to Review` 远端冲突 triage handoff、只读 remote merge planner、带 rollback snapshot 和 ETag/CAS 条件写保护的 remote writeback executor、受保护 `Upload sync bundle` 写出，以及 Review inbox 直达入口；只纳入已应用 KnowledgeCard 和复习历史，显性显示排除项、待审冲突、远端 incoming/outgoing/conflict 计数、只读远端检查摘要和 `Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed` 状态；provider 级闭环覆盖安全的本地 KnowledgeCard 冲突进入 Review Inbox 后 approve/apply，并解除 pending conflict 回到 export included 集合。 | 目前是本地导出 + 远端 bundle 预览 + 前台只读远端检查 + 远端状态提示 + canonical per-envelope merge plan + 安全远端 KnowledgeCard Review 导入 + 安全远端 review history Review 导入 + 安全远端 KnowledgeCard 冲突 staged Review 恢复 + 前台一键安全编排 + 带 rollback 和条件写 guard 的安全 bundle 写回 + 冲突 Review handoff；`Check remote changes` 只读取远端 bundle 并展示 incoming/conflict 摘要，不上传、不发送 Review、不应用资产；`Run safe remote sync` 会先 preview，存在远端 blocker 时只批量送入 Review/暂存 Review 并停止上传，无 blocker 时才执行受保护 upload；本地 staged 或远端 staged 且满足 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的冲突可 apply，远端 staged ReviewItem 写入失败会回滚暂存 entry，远端 incoming KnowledgeCard 和 review history 都会降级为 pending Review；旧的远端 preview conflict triage 入口只支持 dismiss/triage；写回前如果发现远端 incoming/conflict 会阻止覆盖；WebDAV 写回使用 `If-Match` 或 `If-None-Match`，preview 后远端变化或远端被其他设备创建时会停止上传并要求重新 preview；provider 不暴露 ETag/CAS 时拒绝覆盖并显示 concurrency guard unavailable；普通写回失败仍会恢复旧远端 bundle 或删除半写入的新 bundle 并显示状态。 |

## 2. 已接入的用户路径

### 2.1 选中文本生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `知识卡`。
4. 系统创建 `KnowledgeCard(origin=selection)`，写入 `.knowledge/knowledge_cards_v1.json`。
5. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
6. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
7. 用户可以先查看证据摘录、来源标题/位置和不可用来源原因，再批准、忽略、应用，并通过 SourceRef 跳回原文。

Gate：

- 卡片必须带 `bookId/cfi/jumpLink/sourceHash/createdAt`。
- 相同书籍、相同 CFI、相同选中文本重复点击，不制造重复卡。
- 空选中文本不写 store。
- 生成内容只进入 Review，不直接进入长期资产。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/selection_knowledge_card_producer_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  -r compact
```

### 2.2 一键开启研讨

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `研讨`。
4. 系统打开阅读页 AI Chat，并在当前 AI Chat 页面内展开 `AiSeminarRuntimePanel`，把选中文段预填为 Seminar question，并携带 reader `SourceRef`、CFI、jump link 和 snippet；完整 `AiSeminarRuntimePage` 只作为详情、恢复和兼容入口。
5. 用户点击 `Start Seminar`。
6. 系统先取 evidence：阅读页入口先把选中文段作为 `Reader selection` evidence，再优先 current book；Settings 独立入口没有 current book 时使用 library fallback。
7. 系统按 `critical -> supportive -> synthesizer` 串行执行角色，页面展示 role turn、evidence、Shared Whiteboard 和 synthesis。
8. 用户可以取消运行；失败或证据不足时可以重试。
9. 运行中用户可修改问题并点击 `Queue Seminar`，新任务进入本机串行队列；当前 job 终态后系统启动下一条 queued job。
10. synthesis 满足 `readyForReview + traceable handoff` 后，用户点击 `Send to Review`。
11. 运行完成后，用户仍可在 synthesis 后的 `Continue discussion / 继续讨论` 输入读者回合，并选择继续问某个角色、重新找证据或重新整理总结。
12. 系统把 Seminar synthesis 写成 pending ReviewItem，把候选卡写成 pending KnowledgeCard + ReviewItem，把 `reviewSuggestion` 写成 pending flashcard ReviewItem。

Gate：

- 默认使用 current book 语境。
- 阅读页选中文本入口必须把可追踪 reader SourceRef 写入 Seminar session；SourceRef 不可追踪时不能伪造 evidence。
- 默认不开 web。
- 页面启动前必须显示当前 provider/model/capability 诊断；缺少 pricing metadata 时必须显示 `Cost: unknown` 和原因，不伪造美元成本估算。
- 角色完成后如果 provider/SDK 返回 usage metadata，必须显示 `Provider reported usage` 并持久化到 turn/run；如果没有返回 usage metadata，必须显示本地 token 估算和 `Provider billing may differ` 提示；本地估算只能来自本地 prompt/evidence/response 字符计数，不得伪装成 provider billing。
- 用户填写的本地 role output token budget 和 run token budget 只能使用 `local-char-estimate-v1` 执行；超限时停止后续 Seminar 步骤、保留已完成 traceable turn、显示失败原因并允许重试。
- 当 provider capability cache 带 pricing metadata 时，页面必须启用估算 `Run cost cap USD`；runtime 使用 provider-reported usage 或本地 fallback usage 聚合估算美元成本，超出 cap 时停止后续 Seminar 步骤并保留失败原因。
- 页面必须说明估算 cost cap 不是真实 provider 发票或扣费上限；缺少 pricing metadata 时必须禁用美元 cap 并显示原因；不得把 provider token usage 或本地 token budget 单独当作真实账单上限。
- completed/cancelled/failed Seminar state 可作为本机恢复缓存保存；该缓存不得进入普通 prefs backup，不得同步，不得包含 API key；恢复出的页面必须显示 recovered 提示。
- 从阅读页进入 Seminar 时，现有 runtime/cache 必须匹配当前 `bookId` 和入口问题；不匹配时必须清除本机 runtime/cache 并显示新的空白 runtime，不得把旧书/旧选区的结果展示到当前入口。
- persisted `running` state 如果有可追踪 evidence、completed turns 是合法连续前缀且 provider/model/pricing 仍匹配当前配置，必须复用已保存 evidence 并从第一个缺失角色继续；不得重跑已完成角色；缺 tokenUsage 的 checkpoint turn 必须补本地估算后再进入终态 usage/cost。
- persisted `running` state 如果没有 completed role 但已有可追踪 evidence，必须丢弃 active partial text 并从首个角色重新生成；如果 checkpoint 无效、证据不可追踪或 provider/model/pricing 已变化，必须恢复为 interrupted/retryable，清空 active role 和 partial text，不得伪装后台 stream 仍在继续。
- 运行中再次启动 Seminar 必须排入本机串行 queued job，不得取消当前 active stream；用户取消 queued job 时不得取消 active stream；重启时如果 active job 可从 traceable checkpoint 续跑，且 queued job 带完整 session payload，queued job 必须保持 queued 并在 active 续跑完成后自动启动；如果没有可续跑 active job、queued job 缺少 session、checkpoint 无效、证据不可追踪或 provider 已切换，queued job 必须标记 interrupted/retryable，不得伪装旧 stream 仍在继续。
- 研讨结果不自动写 KnowledgeCard、Memory、Note 或 Sync asset。
- completed continuation composer 的读者输入必须保存为 `lastUserIntervention`，不得写入 formal evidence ledger，不得生成没有 SourceRef 的正式证据。
- synthesis、候选卡和候选 flashcard 只进入 Review；用户必须在 Review Inbox 中批准或应用，才会进入长期知识资产或复习队列。
- 当前入口必须保留降级路径：用户仍可用普通 `AI` 按钮解释选中文本。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/langchain_runner_usage_test.dart \
  test/service/ai/ai_seminar_runtime_service_test.dart \
  test/providers/ai_seminar_runtime_test.dart \
  test/page/settings_page/ai_seminar_runtime_page_test.dart \
  test/ai_chat_stream_seminar_entry_test.dart \
  test/ai_multi_tab_chat_visibility_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  -r compact
```

### 2.3 AI Chat 回答生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `AI`。
4. AI 面板打开，并把选中文本放入草稿；如果用户发送的草稿仍包含原选中文本或 SourceRef snippet，系统把本轮草稿的 reader SourceRef 写入会话树用户节点，随 `conversationV2` 历史保存。
5. 用户发送问题并等待回答完成。
6. 用户查看回答气泡旁边的来源状态：`可跳转来源` 表示卡片会带 reader source；`已标记不可用` 表示只保留 conversation provenance，不能跳回原文。
7. 用户点击回答气泡旁边的 `知识卡`。
8. 系统创建 `KnowledgeCard(origin=ai-chat)`，写入 `.knowledge/knowledge_cards_v1.json`。
9. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
10. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
11. 用户可以批准、忽略、应用；有 reader SourceRef 时可跳回原文，没有 reader SourceRef 时仍保留 conversation provenance 和不可跳原因。
12. 如果这张卡有 reader grounding 和保守 `conceptRefs`，用户 `Apply` 后系统会创建 draft ConceptGraph node/edge 和 pending relation ReviewItem；relation 仍需再次 Review。

Gate：

- 入口必须是回答完成后的用户显式 `知识卡` 点击；streaming 中按钮不可用。
- 回答旁必须显示来源状态：有 reader grounding 或有效当前阅读位置 fallback（`bookId + cfi`）时显示可跳转；旧历史、没有 reader source 或当前阅读位置缺少可保存锚点时显示已标记不可用，并通过 tooltip 说明不能跳回原文。
- 从选中文本打开 AI 时，KnowledgeCard 必须优先使用该选中文本的 reader SourceRef。
- 如果用户把预填草稿改成不包含原选中文本或 SourceRef snippet 的无关问题，本轮 user node 不得保存旧 reader SourceRef，回答旁 `知识卡` 只能使用 conversation provenance 或显式持久化的新 reader SourceRef。
- 短公共片段不能只因为被改写后的问题碰巧包含就保留精确 reader SourceRef；短片段只有发送内容等于该片段本身时才保留。
- 选中文本 reader SourceRef 必须随 `conversationV2` 保存；历史重载后回答旁 `知识卡` 仍优先使用原始 reader SourceRef。
- 没有 reader SourceRef 的普通聊天也必须保留 conversation SourceRef 和不可跳原因；从历史加载且没有持久化 reader SourceRef 的会话不能使用当前阅读位置 fallback。
- 只有 reader-grounded AI Chat card 能生成保守 `conceptRefs`；纯聊天 card 的 `conceptRefs` 必须为空。
- 空回答不写 store。
- 长回答在写入 KnowledgeCard、SourceRef 和 ReviewItem payload 前必须裁剪。
- 重复点击同一 conversation/message/prompt/answer 不制造重复卡。
- 本入口不调用额外 LLM、embedding、rerank 或 web provider；只保存当前已有回答。
- Producer 只写 pending KnowledgeCard 和 pending ReviewItem，不直接写 ConceptGraph、长期记忆、笔记或 spaced review；ConceptGraph 候选只能由 Review apply 后的 `ReviewInboxController -> ConceptGraphProducer` 生成。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/ai_chat_knowledge_card_producer_test.dart \
  test/ai_chat_stream_knowledge_card_test.dart \
  -r compact
```

### 2.4 AI Chat Memory 候选审核

用户路径：

1. 在 AI Chat 中找到一条回答。
2. 点击回答旁的 `Memory actions`。
3. 选择 `Add to Review inbox`。
4. 系统创建 `MemoryCandidate(status=pending)`，写入 `.workflow/review_inbox_v2.json`。
5. 系统创建对应 `ReviewItem(sourceType=memory-candidate)`，写入 `.workflow/review_items_v1.json`。
6. 用户进入 `Settings -> AI -> Review inbox`，审核这条 memory 候选。
7. 用户可以查看证据摘录、来源标题/位置、不可跳原因或打开来源动作。
8. 用户点击 `Approve` 后，再点击 `Apply`。
9. 系统先通过 `MemoryWorkflowService.applyCandidate` 追加到目标 daily 或 long-term Markdown memory，再推进 ReviewItem 到 `applied`。

Gate：

- Memory 候选必须经用户显式 `Approve -> Apply`，不能自动写长期 memory。
- `Dismiss` 必须同步 MemoryCandidate 状态，且不写 memory Markdown。
- Apply 必须走 Memory source-specific adapter；不能通过泛型 ReviewItem 状态推进绕过 source 写入。
- 无书内跳转的 conversation memory 必须保留 evidence snippet、source hash 和不可跳原因，使用户能解释来源不可跳。
- Apply/dismiss 不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。
- MemoryCandidate 缺失、targetDoc 缺失或 SourceRef 不满足 gate 时，不得推进 ReviewItem 到 applied。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/knowledge_review_adapter_test.dart \
  test/service/memory_workflow_service_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/page/settings_page/review_inbox_page_test.dart \
  -r compact
```

### 2.5 Memory 独立浏览 SourceRef 审计

用户路径：

1. 用户在 `Settings -> Home navigation / 首页导航` 打开默认隐藏的 `Memory / 记忆` tab。
2. 用户从首页底部导航进入 `Memory / 记忆` tab。
3. 页面加载 daily memory 和 long-term memory 条目。
4. 系统用已应用的 `MemoryCandidate` 按目标文档和条目 body 只读投影 SourceRef。
5. 条目行显示 `traceable/unavailable/unresolved` 来源状态。
6. 用户点击一条 memory 进入详情页。
7. 详情页显示 `Evidence`、证据摘录、来源标题/位置和不可跳原因。
8. 如果 SourceRef 可解析为 `paperreader://reader/open?...`，用户点击 `Open source` 回到原文。
9. 如果来源没有 book anchor，用户点击 `Open source` 时看到不可跳原因，不触发空跳转。

Gate：

- Memory 独立浏览页只能读取已应用 MemoryCandidate 生成 SourceRef，不写新的 ReviewItem 或知识资产。
- SourceRef 投影必须匹配 `daily/longTerm` 目标文档和条目正文；只能用实际写入 memory 的 `text/displayText` 证明归属，不能只靠 summary 命中；long-term `MEMORY.md` 使用 H1 分段 body，不能把整文件来源全部挂到每个分段。
- 不往 Markdown memory 文件写隐藏 metadata；旧 Markdown 仍可正常打开。
- long-term H1 分段不可批量删除/打标签，避免把一个分段的操作变成整份 `MEMORY.md` 的资产修改。
- 有效来源必须通过 `PaperReaderReaderIntent.fromSourceRef` 生成 reader intent；非法 jump link 不能算 traceable。
- conversation-only memory 保留 evidence snippet、source hash 和 `memory-source-not-jumpable` 不可跳原因。
- 详情页只展示已裁剪 evidence，不读取整章正文、图片原文、OCR 长文本或派生索引。

验证命令：

```bash
flutter test --no-pub \
  test/page/memory/memory_home_page_test.dart \
  test/service/memory/markdown_memory_store_test.dart \
  test/service/memory/memory_source_ref_adapter_test.dart \
  test/page/memory/memory_row_test.dart \
  test/page/memory/memory_detail_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.6 旧划线/笔记 SourceRef 审计

用户路径：

1. 用户打开某本书的笔记列表，或在全局搜索里看到命中的笔记/划线。
2. 系统用 `BookNoteSourceRefAdapter.fromBookNote` 把旧 `BookNote` 投影成 `SourceRef`。
3. 笔记条目显示 `Evidence`、证据摘录、来源书名、章节位置和 `traceable/unavailable` 状态。
4. 有 `bookId + cfi` 的条目沿用原有阅读页跳转。
5. 缺失 CFI 或无有效 book anchor 的旧条目点击时显示 `book-note-source-not-jumpable` 原因，不调用空 CFI 跳转。

Gate：

- 旧 BookNote/highlight 不制造 KnowledgeCard、ReviewItem、Memory、ConceptGraph、SpacedReview 或 Sync side effect。
- `BookNoteSourceRefAdapter` 必须区分 highlight 与 note。
- 有 `bookId + cfi` 的 SourceRef 必须生成 `paperreader://reader/open?...` jumpLink。
- 缺失 CFI 或无有效 bookId 的旧条目必须写 `unavailableReason`，并仍可在 UI 中看到来源证据。
- `SourceRefEvidenceList` 只展示裁剪后的 snippet、title、location 和 unavailable reason，不读取章节正文或 `ai_index.db`。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/knowledge_review_adapter_test.dart \
  test/widgets/book_notes/book_note_tile_test.dart \
  -r compact
```

### 2.7 图片解析生成知识卡

用户路径：

1. 打开一本书。
2. 点开正文中的图片。
3. 点击图片工具栏里的 `AI Image Analysis / AI图片解析`。
4. 等待图片解析结果出现在弹层中。
5. 点击弹层里的 `Card / 知识卡`。
6. 系统创建 `KnowledgeCard(origin=image-analysis)`，写入 `.knowledge/knowledge_cards_v1.json`。
7. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`，写入 `.workflow/review_items_v1.json`。
8. 用户进入 `Settings -> AI -> Review inbox`，审核这张卡。
9. 用户可以批准、忽略、应用，并通过 SourceRef 跳回图片所在阅读位置。

Gate：

- 图片解析结果必须由用户显式点击 `Card / 知识卡` 后才写入。
- 卡片必须带当前阅读位置的 `bookId/cfi/href/jumpLink/sourceHash/createdAt`。
- 相同书籍、相同阅读锚点、相同图片上下文和相同解析结果重复点击，不制造重复卡。
- 图片解析结果只进入 Review，不直接进入长期资产、笔记或 spaced review。
- 图片本身不写入 knowledge card payload；SourceRef 只保存裁剪后的图片上下文、alt/title 和当前阅读锚点。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/image_analysis_knowledge_card_producer_test.dart \
  test/page/book_player/image_viewer_test.dart \
  -r compact
```

### 2.8 概念图谱探索

用户路径：

1. 用户先在 Review Inbox 中 `Apply` 一个带 `conceptRefs` 和可追踪 SourceRef 的 KnowledgeCard。
2. 系统创建 card node、concept node 和 `appears_in` edge，全部保持 draft ownership。
3. 系统为每条 relation 创建 `ReviewItem(sourceType=concept-graph-relation, status=pending)`。
4. 用户在 Review Inbox 中审核这些 relation；只有 relation 被 `Apply` 后，edge 才升级为正式图谱关系。
5. 用户进入 `Settings -> AI -> Concept graph / 概念图谱`，或在阅读页选中文本后点击 `图谱/Graph`。
6. 从阅读页进入时，系统带入当前 bookId，并读取 `ai_graph_nodes / ai_graph_edges` 全局层，只展示有 chunk SourceRef 的只读 `全书派生图谱 / Full-book derived graph`。
7. 系统列出 `ConceptGraphStore` 中已有概念节点；从阅读页进入时，会先按选中文本筛选相关概念。
8. 用户点一个概念。
9. 页面显示该概念的定义、来源证据、局部图谱摘要、局部路径和可回溯关联；局部图谱摘要会标出中心概念、直接关系、二跳节点、evidence link 数量和 draft/formal 状态。
10. 页面显示 orphan node / broken edge 计数，用于发现悬空图谱关系。
11. 有可跳转 SourceRef 时，用户可以点 `Open source / 打开来源` 回到原文。
12. 如果选中文本没有匹配到已有概念，页面展示空态和 `Create draft candidate / 创建草稿候选` 入口。
13. 当 Seminar candidate card 或 reader-grounded AI Chat card 带有 `conceptRefs` 时，用户在 Review Inbox 中应用该 KnowledgeCard 后，系统复用同一 producer 创建 draft 概念节点、draft card 关系和 pending relation ReviewItem。
14. 用户点击 `Create draft candidate` 后，系统执行本地文本 library RAG search，并关闭 query embedding、vector fallback、rerank；只有 search result 带 `derivedLayer/derivedSummary` 且有 traceable chunk SourceRef 时，才通过 producer 创建 draft 概念节点、draft RAG claim 节点和 pending relation ReviewItem。

Gate：

- 只有 `applied + user asset + traceable + conceptRefs` 的 KnowledgeCard 会触发 producer。
- 只有带 `derivedLayer/derivedSummary` 且 SourceRef 可追踪到书内 chunk 的 library RAG result 会触发 RAG/GraphRAG producer。
- Producer 只写 draft node/edge 和 pending relation ReviewItem；正式 relation 必须经过 Review apply。
- 没有 `conceptRefs` 的 KnowledgeCard 不制造图谱噪声。
- 普通 RAG 命中不制造 ConceptGraph 节点；GraphRAG/RAPTOR summary 只作为 derived summary，正式 evidence snippet 必须来自书内 chunk SourceRef。
- Seminar candidate card 和 reader-grounded AI Chat card 的 `conceptRefs` 必须先随 KnowledgeCard 进入 Review；只有用户 Apply 后才会生成图谱候选关系。
- Producer 失败不回滚 KnowledgeCard apply 或 spaced review 入队。
- 只展示已有图谱数据，不把 AI 推断直接变成用户确认关系。
- 全书派生图谱只读取当前书全局层和 chunk evidence，节点/关系保持 `derived-cache`，不写正式 `ConceptGraphStore`，不进入 Review，不外发正文。
- 局部路径只使用有 evidence 的边。
- broken link / orphan node 必须显性可见。
- 没有图谱数据时展示空态，而不是制造无证据节点。
- 阅读页 `图谱/Graph` 入口不自动调用 LLM、embedding、rerank 或 web provider，不外发正文，不写正式 `ConceptGraphStore` 资产；用户点击 `Create draft candidate` 时只执行关闭 query embedding、vector fallback、rerank 的本地文本 library RAG search 和 draft/pending 写入。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/concept_graph_producer_test.dart \
  test/service/knowledge/derived_book_concept_graph_loader_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  test/widgets/context_menu/excerpt_menu_actions_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.9 RAG / GraphRAG 结果生成知识卡

用户路径：

1. 打开一本书。
2. 选中一段文本。
3. 点击选中菜单里的 `图谱/Graph`。
4. 如果没有匹配到已有概念，页面展示空态。
5. 用户点击空态里的 `Card / 知识卡`。
6. 系统执行本地文本 library RAG search，并关闭 query embedding、vector fallback、rerank。
7. 系统只从带 traceable chunk SourceRef 的 RAG evidence 创建 `KnowledgeCard(origin=rag-evidence)`。
8. 系统创建对应 `ReviewItem(sourceType=knowledge-card)`。
9. 用户进入 `Settings -> AI -> Review inbox` 审核这张卡。
10. 用户可以批准、忽略、应用，并通过 SourceRef 跳回原文 chunk。

Gate：

- 入口必须是用户显式点击 `Card / 知识卡`。
- 本入口不调用 LLM、embedding、rerank 或 web provider，不外发正文。
- 只有 `SourceRef.hasDerivedChunkHint`、可追踪回书内 chunk、且带可保存 chunk snippet 的 evidence 能进入卡片。
- `derivedSummary` 只作为 explanation，不作为 formal evidence snippet；quote 使用书内 chunk snippet。
- Producer 只写 pending KnowledgeCard 和 pending ReviewItem，不写 ConceptGraph node/edge、Memory、Note 或 Spaced Review。
- 重复点击同一 query 和同一 evidence 不制造重复卡。

验证命令：

```bash
flutter test --no-pub \
  test/service/knowledge/rag_evidence_knowledge_card_producer_test.dart \
  test/providers/concept_graph_explorer_test.dart \
  test/page/settings_page/concept_graph_explorer_page_test.dart \
  -r compact
```

### 2.10 间隔复习

用户路径：

1. 阅读页选中文本生成 `KnowledgeCard`，Seminar 生成 `reviewSuggestion`，或其他 producer 写入待审知识卡/复习卡。
2. 用户进入 `Settings -> AI -> Review inbox`。
3. 用户先批准，再点击 `Apply`。
4. 系统把已应用且有 SourceRef 的 KnowledgeCard 或 flashcard candidate 写入 `.knowledge/spaced_review_items_v1.json`。
5. 用户进入 `Settings -> AI -> Spaced review / 间隔复习`。
6. 页面刷新时会对账已应用 KnowledgeCard，补齐缺失的复习队列项。
7. 页面显示到期复习项、答案、证据摘录、来源标题/位置、可跳转来源、不可用来源和未解析来源计数。
8. 用户点击 `Again / Hard / Good / Easy` 后，系统记录复习历史并更新下一次到期时间。

Gate：

- 只有 `applied + traceable + user asset` 的 KnowledgeCard，或 `applied + traceable + flashcard candidate`，能进入复习队列。
- 同一 KnowledgeCard 或同一 flashcard candidate 重复入队不会制造重复复习项。
- 如果 KnowledgeCard Review apply 已成功但队列写入曾失败，复习页刷新会按已应用 KnowledgeCard 对账恢复；flashcard candidate 需要重新 Apply 或由后续对账任务补齐。
- 复习项必须保留 SourceRef；证据摘录、来源位置、可跳转、不可用、未解析来源都要显性展示。
- 复习记录只更新 spaced review 队列，不写长期记忆、不写笔记、不写同步资产。
- 删除书或恢复备份导致来源不可跳时，页面显示不可用或未解析状态，而不是静默丢失。

验证命令：

```bash
flutter test --no-pub \
  test/service/review/spaced_review_store_test.dart \
  test/service/review/review_inbox_controller_test.dart \
  test/providers/spaced_review_test.dart \
  test/page/settings_page/spaced_review_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.11 知识同步 / 导出

用户路径：

1. 用户先在 Review Inbox 中 `Apply` KnowledgeCard，或完成间隔复习记录。
2. 用户进入 `Settings -> AI -> Knowledge sync/export / 知识同步 / 导出`。
3. 页面展示本次默认纳入的知识资产数量、默认排除项数量和待审冲突数量。
4. 用户可以刷新计划，确认哪些 envelope 会进入导出，哪些因草稿、派生缓存、密钥或冲突被排除。
5. 如果页面显示待审冲突，用户点击 `Send conflicts to Review / 发送冲突到 Review`。
6. 系统为每个尚未进入 Review 的待审冲突创建 `ReviewItem(sourceType=sync-conflict, status=pending)`，只保存安全 metadata、payload key 列表和 SourceRef；如果冲突没有 SourceRef，则写入 `sync-conflict-no-source` 不可跳原因，不把 raw payload 值或 secret 值写入 ReviewItem payload。
7. 页面显示 `Review inbox` 直达入口；用户点击后进入 Review Inbox，也可以从 `Settings -> AI -> Review inbox` 进入。
8. 用户查看 `Sync conflict / 同步冲突` 类型的待审项、冲突原因、来源证据和可跳转状态。
9. 如果该冲突是 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef`，页面显示 `Approve` 和 `Apply`；用户 `Apply` 后系统把该 KnowledgeCard 写回为用户确认资产，并解除 pending conflict metadata。
10. 如果冲突含 secret payload、未知 schema、无可追踪 SourceRef、非 KnowledgeCard 或 payload 不可解析，页面只显示 `Dismiss`，不提供 approve/apply。
11. 用户点击 `Create export / 创建导出`。
12. 系统写入 `.knowledge/knowledge_export_manifest_v1.json`，其中只包含安全的实体 ID、格式、时间戳和裁剪后的 SourceRef 引用。
13. 系统同时写入 `.knowledge/knowledge_export_v1.md`，作为可阅读的 Markdown 学习导出，只包含已纳入资产、裁剪后的证据片段和可跳转来源。
14. 系统同时写入 `.knowledge/knowledge_export_study_report.html`，作为可打开的本地 HTML 学习报告；页面不加载外部资源、不执行同步，只展示已纳入资产、裁剪后的证据片段和可跳转来源。
15. 系统同时写入 `.knowledge/knowledge_export_anki.tsv`，作为 Anki 兼容 TSV；Front/Back/Source 只来自默认纳入资产、裁剪后的证据片段和可跳转来源。
16. 系统同时写入 `.knowledge/knowledge_sync_bundle_v1.json`，作为机器可读 per-entity envelope bundle；它只包含默认纳入的安全 envelope，不包含 draft、pending conflict、secret payload 或派生缓存。
17. 如果用户已配置 WebDAV/SyncClient，用户可以先点击 `Check remote changes / 检查远端变更` 执行前台只读检查；这个入口只读取远端 bundle 并显示 incoming/conflict 摘要，不上传、不发送 Review、不应用资产。
18. 用户也可以点击 `Preview remote sync / 预览远端同步` 查看完整远端 preview，或点击 `Run safe remote sync / 运行安全远端同步` 执行前台安全编排。
19. 系统读取远端 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json`，按 entity id 比对本地 included envelope，展示 `remote / incoming / outgoing / remote conflict` 计数。
20. 页面显示远端同步状态：`Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed`，并显示对应下一步动作说明；如果来自 `Check remote changes`，页面额外显示只读检查提示。
21. 如果用户点击 `Run safe remote sync` 且 preview 发现 incoming 或 conflict，系统只批量执行安全 Review handoff：安全远端 incoming KnowledgeCard 进入 Review、安全远端 review history 进入 Review、安全远端 KnowledgeCard conflict 写入 staged conflict store 并进入 Review、远端 preview conflict 进入 triage Review；本次不会上传。
22. 如果用户点击 `Run safe remote sync` 且 preview 没有 incoming/conflict，系统走受保护 `Upload sync bundle`，成功后显示上传路径、上传 envelope 数量，并清理旧的 Review handoff 计数。
23. 用户也可以单独点击 `Send remote incoming to Review / 发送远端待引入到 Review`。
24. 系统只把安全远端 incoming KnowledgeCard 降级为 `KnowledgeCard(reviewState=pending, ownership=AI-generated-draft)` 和 `ReviewItem(sourceType=knowledge-card, status=pending)`；重复导入、非 KnowledgeCard、无 evidence 或 unsafe payload 被跳过。
25. 用户点击 `Send remote review history to Review / 发送远端复习记录到 Review`。
26. 系统只把安全远端 review history 降级为 `ReviewItem(sourceType=review-history-import, status=pending)`；用户 Apply 后才写入本机 SpacedReviewStore；重复导入、无 evidence 或 unsafe payload 被跳过。
27. 用户点击 `Stage safe remote card conflicts to Review / 暂存安全远端知识卡冲突到 Review`。
28. 系统只把安全远端 KnowledgeCard conflict 写入本机 staged conflict store，并创建可 apply 的 `ReviewItem(sourceType=sync-conflict, status=pending, canApply=true, remoteStaged=true)`；ReviewItem 不保存 remote raw payload value。
29. 用户在 Review Inbox 中批准并应用后，系统才把 staged remote KnowledgeCard 写回为本机已确认资产，并清掉 staged conflict；未 Apply 前原本机 KnowledgeCard 不被覆盖。
30. 用户点击 `Send remote conflicts to Review / 发送远端冲突到 Review`。
31. 系统把远端冲突创建为 preview-only `ReviewItem(sourceType=sync-conflict, status=pending, canApply=false)`；ReviewItem 只保存安全 metadata、payload key 列表、SourceRef count 和 SourceRef safe JSON，不保存 remote raw payload value。
32. preview-only 远端 `sync-conflict` 只用于 triage/dismiss，不显示 approve/apply；可恢复 apply 必须来自 staged conflict 入口。
33. 用户点击 `Upload sync bundle / 上传 sync bundle`。
34. 系统重新生成本机安全 sync bundle；如果远端 bundle 不存在，创建远端目录并上传；如果远端 bundle 已存在，先执行 preview gate，只有 `incoming=0` 且 `conflict=0` 时才允许覆盖写出。
35. 如果远端存在 incoming 或 conflict，上传中止并显示错误，不删除远端内容、不覆盖本地资产、不把远端冲突自动应用到本地。

Gate：

- 默认只纳入 `applied + user asset` 的 KnowledgeCard 和 review history。
- `ai-draft`、`derived-index`、包含 API key/token/secret/auth/authorization/bearer/private-key/credential/password 的 payload 默认排除。
- 待审冲突显示为排除项，不进入 manifest。
- `Send conflicts to Review` 只为待审冲突创建 `sync-conflict` ReviewItem；重复点击不制造重复 ReviewItem，不覆盖已经存在的 pending/approved/dismissed/applied 审核决策；无 SourceRef 冲突必须带不可跳原因。
- sync conflict ReviewItem 只保存 entity id/type/schema/update/conflict reason/payload keys/sourceRef count；不得保存 raw payload value、API key、token、secret 或派生缓存内容。
- sync conflict ReviewItem 只有在 payload 标记 `canApply=true` 且底层 store 再次验证为 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 时，才可 approve/apply；其他 sync conflict 只能 dismiss/triage。
- safe sync conflict apply 只允许解除该 KnowledgeCard 的 pending conflict metadata 并写回为用户确认资产；不得创建 SpacedReview、ConceptGraph、Memory、Note 或远端同步 side effect。
- manifest 不写 `ai_index.db`，不把派生索引当作 source-of-truth。
- SourceRef 文本片段必须使用现有裁剪规则，不导出无限正文。
- Markdown 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 Markdown 正文。
- HTML study report 只能读取默认纳入资产；正文和链接属性必须转义，不加载远端脚本、图片、样式或 provider 内容；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 HTML 正文。
- Anki TSV 导出只能读取默认纳入资产；草稿、派生缓存、密钥 payload 和待审冲突不得出现在 TSV 正文；TSV 字段必须清理制表符和换行，避免破坏导入结构。
- sync bundle 只能包含默认纳入 envelope；不得包含 draft、pending conflict、secret payload、`ai_index.db` 或 derived cache。
- remote preview 只读取配置的 SyncClient/WebDAV bundle；读取失败进入页面错误状态，用户可刷新重试；不会自动导入 incoming envelope，不会自动覆盖本地资产。
- `Check remote changes` 是前台只读 remote preview：只更新远端检查摘要和远端状态，不调用 upload，不调用任何 `submitRemote*ToReview` handoff，不调用 apply，不修改本地 confirmed asset。
- remote incoming 导入必须由用户点击触发；只接受安全 KnowledgeCard，且导入后仍是 pending Review，不直接成为本机用户资产。
- remote review history 导入必须由用户点击触发；只接受安全 review history，且导入后仍是 pending Review，不直接写入 SpacedReviewStore。
- remote conflict 有两条显式入口：preview-only triage 入口必须 `canApply=false`；staged restore 入口只接受安全 KnowledgeCard conflict，必须先写 staged conflict store，再由 Review Inbox approve/apply 恢复；若 ReviewItem 写入失败，必须回滚 staged entry。
- `Run safe remote sync` 必须先 preview；存在 incoming/conflict blocker 时只执行安全 Review handoff 和 staged conflict handoff，不调用 upload；无 blocker 时才调用受保护 upload，并清理旧 Review handoff 计数。
- remote upload 只上传本机重新生成的安全 sync bundle；远端存在 incoming 或 conflict 时必须阻止上传，不能用本机 bundle whole-file 覆盖远端用户资产。
- 当前入口创建本地 manifest、Markdown 学习导出、HTML study report、Anki TSV、sync bundle，能把安全远端 incoming KnowledgeCard、远端 review history、本地冲突、安全远端 KnowledgeCard staged conflict 和远端 preview-only conflict 送入 Review Inbox，能通过 `Run safe remote sync` 串联 preview、Review handoff 和无 blocker 写回，并能在无远端 incoming/conflict 时通过带 rollback snapshot 和条件写 guard 的 executor 写回安全 sync bundle；支持安全 KnowledgeCard 本地冲突和安全远端 KnowledgeCard staged conflict 的用户确认恢复，且 staged ReviewItem 写入失败会清理暂存项；WebDAV 写回使用 ETag/CAS 条件写，preview 后远端变化会停止上传并要求重新 preview，provider 缺少条件写能力会拒绝覆盖；写回失败会恢复旧远端 bundle 或删除半写入的新 bundle；不执行双向自动合并或自动同步备份。

验证命令：

```bash
flutter test --no-pub \
  test/models/knowledge_sync_test.dart \
  test/service/sync/knowledge_asset_export_service_test.dart \
  test/providers/knowledge_asset_export_test.dart \
  test/page/settings_page/knowledge_asset_export_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.12 Custom Skill 导入

用户路径：

1. 用户进入 `Settings -> AI -> 自定义技能 / Custom skills`。
2. 用户粘贴 `CustomSkillContract(schemaVersion=1)` JSON，或点击 `粘贴安全示例 / Paste safe example` 填入安全示例。
3. 用户点击 `导入技能 / Import skill`。
4. 系统解析 JSON、校验 schema、scene、工具权限和 runtime 注入边界。
5. 如果校验失败，页面显示错误，skill 不写入本地 store，也不出现在 `Active Skill`。
6. 如果校验通过，系统写入 SharedPreferences 中的 `customAiSkillContractsV1`，并在页面的 Installed skills 列表显示 runtime 状态、scene 和允许工具。
7. 用户可以开关或删除该 custom skill。
8. 用户回到 `Settings -> AI -> Active Skill`，选择启用后的 custom skill。
9. AI Chat runtime 构建 system prompt 时合并 custom skill prompt；工具列表只保留 custom skill 声明过、当前 scene 可用、permission matrix 允许的只读工具。

Gate：

- 只接受 JSON object，不接受空输入或数组根节点。
- `schemaVersion` 必须是整数 `1`。
- unknown field、unknown scene、system scene、字段类型错误、未知工具、写工具、`spawn_sub_agent` 均阻止导入。
- disabled custom skill 可以保存在 Installed skills，但不进入 `Active Skill`，也不会注入 runtime。
- active custom skill scene 不匹配时不注入 prompt，工具列表为空。
- active custom skill 运行时不加载 MCP 工具，避免绕过 contract 的 tool whitelist。
- 导入、开关、删除不写 KnowledgeCard、ReviewItem、Memory、Note、ConceptGraph 或 Sync asset。

验证命令：

```bash
flutter test --no-pub \
  test/service/ai/skills/custom_skill_store_test.dart \
  test/service/ai/langchain_registry_custom_skill_test.dart \
  test/page/settings_page/custom_skills_page_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

### 2.13 Responses 兼容模型提问

用户路径：

1. 用户进入 `Settings -> AI -> Provider Center`。
2. 用户选择或创建 OpenAI Responses 兼容 provider。
3. 用户按 provider 需要配置 model、base URL、streaming/reasoning 选项。
4. 用户可以保持 `Use previous_response_id continuation` 开启。
5. 用户在阅读页 AI Chat、Seminar 或工具调用场景中发起请求。
6. 如果 provider 支持 `previous_response_id`，系统继续使用 server-side continuation。
7. 如果 provider 明确以 HTTP 400 拒绝 `previous_response_id`，系统自动重建为不带该字段的 tool-output replay body，并重试一次。
8. 如果错误不是 `previous_response_id` unsupported，系统保留原错误并显示给用户，不把 provider 配置错误误判为兼容 fallback。

Gate：

- 只有请求体确实包含 `previous_response_id`，且 HTTP status 是 `400`，且错误正文同时包含 `previous_response_id` 和 `unsupported`，才允许 fallback。
- fallback 后同一个 `ChatOpenAIResponses` runtime instance 不再发送 `previous_response_id`。
- 正常支持 `previous_response_id` 的 provider 不受影响。
- 非 `previous_response_id` 的 HTTP 400 不允许 retry。
- fallback 不记录 API key，不改 provider 设置，不把第三方 provider 的兼容行为写成永久 capability。

验证命令：

```bash
flutter test --no-pub \
  test/service/openai_responses_chat_model_test.dart \
  -r compact
```

### 2.14 当前书语义检索资源保护

用户路径：

1. 用户先为当前书构建本地 AI semantic index。
2. 用户在阅读页触发普通搜索、AI Seminar current-book evidence，或 agent tool 调用 `semantic_search_current_book`。
3. 系统嵌入 query 后先尝试用 `ai_chunks_fts` 取得 bounded FTS/BM25 候选 id。
4. 若 FTS5 不可用、MATCH 失败或候选为空，阅读页、AI Seminar evidence 和 agent tool 路径按 `ai_chunks.id` 做预算内 fallback 分页扫描。
5. 无论候选预筛还是完整分页扫描，扫描页只读取 vector 和 provenance 所需列，不读取 `text/raw_text/embedding_json`。
6. 系统维护 bounded topK 候选，只为最终命中的 chunk 回查正文。
7. 如果旧索引 chunk 还没有 `embedding_blob`，系统按页批量回查 `embedding_json`，不做逐行 SQL 回查。
8. 同进程 current-book semantic search 通过全局 lock 串行化；agent tool registry 也把 `semantic_search_current_book` 标为非并发。
9. 每页向量解码和 cosine scoring 通过 `AiCurrentBookVectorPageScorer` seam 执行，默认使用 background isolate，避免长循环独占 UI isolate。
10. 阅读页新搜索、清空搜索或离开页面会 cancel stale semantic search；stale query 不写入 partial results。
11. 阅读页目录搜索进度条显示 semantic progress；progress 总量使用候选数或 fallback 扫描预算。
12. `semantic_search_current_book` 工具超时时会 cancel 底层 token 并返回 `cancelled=true` degrade；fallback 达到预算时返回带 message 的降级结果。

Gate：

- hot scan query 不允许选择 `text/raw_text/embedding_json`。
- FTS/BM25 预筛只允许取候选 id，不能把正文列带入向量扫描热路径。
- FTS5 缺失、MATCH 抛错或无候选时，阅读页、AI Seminar evidence 和 agent tool 路径必须提供 fallback vector scan budget。
- topK 候选必须 bounded，不能把全书 scored rows 常驻内存。
- text/raw_text 只能为 winners 回查。
- JSON fallback 只能按页批量回查 blob 缺失行。
- 直接调用路径和 tool orchestrator 路径都不能并发扫描当前书。
- 阅读页 fallback 扫描上限为 1024 行；AI Seminar evidence 和 agent tool fallback 扫描上限为 2048 行；达到上限时不得继续扫描下一页。
- fallback progress 的 `totalRows` 必须使用预算后的行数，不能让 UI 误以为要扫完整本书。
- 向量 scoring 默认不得在 UI isolate 长循环执行；可替换 backend 必须保留 SourceRef provenance 所需字段。
- 取消后不得回查 winners 正文或写入 semantic results。
- 本切片不是发布级 ANN/sqlite-vec/Vec1 后端；无 FTS 候选时仍是预算内分页扫描；任何后续替换后端都必须继续保留 SourceRef 和 evidence gate。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/semantic_search_current_book_search_test.dart \
  test/providers/toc_search_test.dart \
  test/service/ai/tools/semantic_search_current_book_tool_test.dart \
  test/service/ai/tools/ai_tool_registry_governance_test.dart \
  -r compact
```

### 2.15 书库 Hybrid RAG 向量召回

用户路径：

1. 用户在 AI Chat、Seminar library fallback、agent tool 或其它书库 RAG 入口提出问题。
2. `semantic_search_library` 先执行 FTS/BM25 或 LIKE 文本召回，保留精确关键词候选。
3. 只要该入口允许 query embedding，系统同时调用 `AiVectorSearchBackend` 做语义召回。
4. 文本候选、RAPTOR/GraphRAG 全局层候选和向量召回候选进入同一个 RRF/hybrid/MMR/rerank 排序池。
5. 最终 evidence 仍只返回带 `SourceRef`、chunkId、jumpLink 和可保存 snippet 的 chunk。
6. 结果 JSON 中 `usedVectorRecall=true` 表示向量后端参与候选召回；`usedVectorFallback=true` 只表示文本召回没有候选时的向量兜底。

Gate：

- FTS/BM25 是精确文本召回层；向量后端是语义召回层；二者不能互相替代。
- 只要 `allowQueryEmbedding=true` 且入口允许向量召回，书库搜索必须调用 `AiVectorSearchBackend`，即使 FTS 已命中候选。
- ConceptGraph 空态、RAG KnowledgeCard 本地文本入口继续设置 `allowQueryEmbedding=false`、`allowVectorFallback=false`、`allowRerank=false`，不得外发正文。
- `usedVectorFallback=false` 不能被解释为没有语义召回；必须用 `usedVectorRecall` 判断向量后端是否参与。
- 默认 backend 是 ANN -> native -> exact；Vec1 不可用、ANN 表缺失、native shadow layer 不完整、native 不可用或 native 无结果时，exact backend 必须补足 recall，不得漏掉未升级书籍。
- exact backend 主扫描不得读取 `text/raw_text/context_text/embedding_json`，只能为缺 blob 行批量回查 JSON fallback，并只为 top winner hydrate 正文。
- 替换成 sqlite-vec/ANN backend 时必须保持 SourceRef、chunk evidence、RRF/hybrid/MMR/rerank contract。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/semantic_search_library_search_test.dart \
  test/service/rag/ai_vector_index_test.dart \
  test/service/ai/tools/semantic_search_library_tool_test.dart \
  -r compact
```

### 2.16 书库 exact 向量后端资源保护

用户路径：

1. 用户通过 AI Chat、Seminar library fallback 或 agent tool 触发书库 RAG。
2. `semantic_search_library` 调用默认 `AiExactVectorSearchBackend` 做语义召回。
3. exact backend 先扫描 compact vector/provenance row，按 cosine 选出 top winner。
4. 只有 winner chunk 再回查 `text/raw_text/context_text/embedding_json`，用于 evidence snippet、MMR/rerank 和 SourceRef 输出。

Gate：

- 主扫描 SQL 不得选择 `c.text`、`c.raw_text`、`c.context_text` 或 `c.embedding_json`。
- 旧索引缺 `embedding_blob` 时，只允许对缺 blob 的扫描行批量回查 `embedding_json`，不得全表正文热扫。
- 返回给上层的 winner 仍必须带 `chapter_href`、`text/raw_text/context_text`、embedding metadata、provider/model 和 `local_vector_score`。
- 本切片只声明 extension-ready ANN search/build seam 和设置页前台 build action；sqlite-vec/ANN 发布能力仍需平台 package/extension、provider/model 失效和 overlap gate。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/ai_vector_index_test.dart \
  test/service/rag/ai_local_vector_index_test.dart \
  test/service/rag/semantic_search_library_search_test.dart \
  test/service/ai/tools/semantic_search_library_tool_test.dart \
  -r compact
```

### 2.17 旧索引向量层升级

用户路径：

1. 用户进入 `Settings -> AI Index / Library Index`。
2. 页面显示 `向量索引升级`。
3. 系统检查已完成书库索引中哪些书缺少 `ai_vector_index_rows` shadow rows。
4. 用户点击 `升级`。
5. 系统用已有 `embedding_blob` 或旧 `embedding_json` 写入紧凑 float32 shadow rows，不重新生成 embedding。
6. 页面显示升级进度和取消按钮；取消后未处理书籍仍保留为可升级。
7. 后续检索先尝试 native SQL backend seam，native 不可用或无结果时自动降级 exact backend。

Gate：

- 不外发正文，不调用 embedding provider，不重嵌入。
- 只处理 `ai_book_index.chunk_count > 0` 且 `index_status=succeeded` 的旧索引书籍。
- 缺失、损坏或空向量不得写入 shadow rows。
- 书籍删除和 chunk 删除必须显式清理 stale rows，不能只依赖后续 backfill 掩盖残留。
- 页面必须显示进度、取消和完成/取消结果。
- 本切片不得宣称 sqlite-vec/ANN 发布完成；真实 native package/extension adapter、平台打包和 provider/model 失效仍需独立验收；候选 backend 必须复用现有 recall overlap gate。

验证命令：

```bash
flutter test --no-pub \
  test/service/rag/ai_native_vector_index_test.dart \
  test/service/rag/ai_index_schema_global_layers_test.dart \
  test/page/settings_page/settings_navigation_compile_test.dart \
  -r compact
```

## 3. 当前还不能用

这些能力没有产品入口或没有完成端到端验收，不应在用户沟通中描述为已经可用：

| 能力 | 当前边界 | 下一步 Agent Task | Gate |
| --- | --- | --- | --- |
| 完整云同步引擎 | 当前已有本地导出、机器可读 sync bundle、远端 bundle preview、`Check remote changes` 前台只读检查、远端同步状态面板、`Run safe remote sync` 前台安全编排、安全远端 incoming KnowledgeCard Review 导入、安全远端 review history Review 导入、安全远端 KnowledgeCard 冲突 staged Review 恢复、安全冲突 Review handoff、安全 KnowledgeCard 冲突本地恢复、Review Inbox 已审核安全冲突批量 apply/retry、只读 remote merge planner、本机 remotePath baseline 持久化、带 rollback snapshot 的 remote writeback executor 和 WebDAV ETag/CAS 条件写 guard；还没有跨设备后台同步任务和发布版迁移。 | 继续拆跨设备后台同步和 release promotion。 | API key 永不同步；冲突进入 Review；不得使用 whole-file newer-wins 覆盖用户资产；不能宣称后台跨设备自动同步已完成。 |
| AI Chat 内嵌多轮 Seminar | 当前 AI Chat 已有 `AI 研讨会` 入口、当前页内嵌 `AiSeminarRuntimePanel`、完整 runtime page 跳转和 `研讨会设置` 入口；Choose style 仍主要负责选择 active skill，不承载多角色讨论的证据刷新、用户插话和分歧回合。Seminar settings 已能保存角色显示名和 custom prompt，并注入新 Seminar session；`AiSeminarDirectorState` 已能保存 Director 账本，并在 completed run 后根据 whiteboard 自动标记下一步：open question -> `askUser`，disagreement + 轮次预算 -> `refreshEvidence`，页面状态区显示主持人下一步；`askUser` 状态下页面提供用户回复输入框、目标角色选择和“让所选角色回应 / 重新找证据 / 整理总结”动作，用户输入只写 `lastUserIntervention`，其中“让所选角色回应”会执行目标角色 follow-up turn 并更新 synthesis，“重新找证据”会重新检索 evidence、重跑角色并更新 synthesis，“整理总结”会用现有 evidence 和 turns 执行本地 synthesis 并收束 Director；completed run 即使没有 open question，也会在 synthesis 后提供 `Continue discussion / 继续讨论`，让用户继续追问角色、刷新证据或重新整理总结，输入仍只写 `lastUserIntervention`；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会自动刷新 evidence、重跑角色，并在刷新后仍有分歧且预算耗尽时转为 `askUser`；角色启用状态、证据策略、工具范围和完整 Director 每轮调度仍未接入。 | 继续拆持久化 Chat run 卡片、role profile 剩余策略、真正 contradiction/rebuttal loop 和独立页面兼容迁移。 | 同一讨论只能有一个 runtime state；AI Chat 内嵌面板、后续 Chat run 卡片、独立详情页和恢复缓存必须共享 SourceRef、turn ledger、budget、Review handoff；用户插话不得被当作 AI evidence；重新检索必须保留 current book first 和默认不开 web。 |
| Seminar OS 后台执行、queued job 重启确认和 provider 发票导入 | Seminar runtime 已能流式、取消、重试、Review handoff，并显示 provider readiness、capability cache、成本未知原因、provider token usage、本地 token 估算 fallback、本地 role/run token budget、pricing metadata 驱动的估算 `Run cost cap USD`、billing snapshot / reconciliation UI、本机 state 恢复、当前 `Background job` snapshot、最近本机 job 账本、本机串行 queued job scheduler 和 traceable evidence checkpoint resume；running state 重启后如果已有可追踪 evidence 且 provider/model/pricing 仍匹配当前配置，会保留 job id、复用已保存 evidence，并从第一个缺失角色继续；已有 completed role prefix 会跳过不重跑，只有 active partial stream 时丢弃 partial 并重新生成缺失角色；同一恢复快照里带完整 session 的 queued job 会继续排队并在 active 续跑完成后启动；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时会标记为 interrupted/retryable。当前没有并发并行 Seminar、OS/background execution gate、旧 LLM stream 原地续传，也没有连接 provider invoice import API；UI 会把估算成本、provider usage metadata、pricing source 和 invoice reconciliation 状态分开展示。 | 拆分 OS/background execution gate、provider request idempotency 和 queued job 跨设备确认；真实 provider invoice import 另拆 provider-specific adapter、鉴权、只读账单导入和失败恢复 gate。 | 移动资源 gate；长任务可取消、失败可恢复或重试；无 pricing metadata 时继续显示成本未知原因并禁用美元 cap；估算美元成本不等于 provider 发票；本地 token budget 不得声明为 provider billing cap；不能把本机 recovery cache 当作同步资产；不得把 job 账本、queued job 或 interrupted snapshot 描述成 OS 后台继续生成；恢复续跑必须说明会重新调用 provider 生成缺失角色。 |
| sqlite-vec/ANN 实验后端 | 当前书语义搜索已做分页、topK、串行、background isolate scoring、取消 token、progress callback、阅读页 stale query cancel、工具超时 cancel、bounded FTS/BM25 候选预筛、fallback scan budget 和 synthetic large-book scan acceptance；书库 RAG 已进入 hybrid recall：向量后端和 FTS/BM25 一起召回，不再只在文本 miss 后兜底；exact fallback backend 主扫描不再加载正文大字段；当前 `kAiIndexDbVersion = 12`，已有 `ai_vector_index_rows/meta` shadow schema、旧索引向量层升级入口、Vec1 table builder、`vec1-ann` meta、ANN -> native -> exact backend、设置页 ANN 构建入口、删除书籍派生索引清理和固定 fixture ANN/exact overlap gate。仍不是已打包的 ANN/Vec1/sqlite-vec 发布后端：没有加载 Vec1 extension 时自动降级；无 FTS 候选时当前书仍是预算内分页扫描。 | 拆真实 sqlite-vec/Vec1 package/extension adapter、平台打包、provider/model 失效，并把候选 ANN backend 接入 `AiVectorRecallOverlapGate`。 | 不得牺牲 SourceRef；无 evidence 不返回正式结果；旧 DB、无 embedding、FTS5 缺失、书籍删除和 provider 切换都有 degrade path；移动端大书搜索必须有取消或可恢复状态；ANN topK 与 exact backend 必须通过固定 fixture 重合率验收。 |
| 复杂无限画布式 ConceptGraph | 当前是局部图谱、dossier、路径、摘要、轻量节点-连线 canvas 和当前书全局层的只读派生图谱预览，不做无限画布、缩放手势或跨书外部知识扩展。 | 如需画布，先定义移动端资源、证据可见性和 graph ownership gate。 | 关系必须有 evidence；正式关系必须 Review apply。 |
| 发布版可用 | 本文件描述 `codex/future-agentic-upgrade` 分支；不代表 `main`、TestFlight 或已安装版本。 | 走 release promotion gate，完成合并、构建、回归、发布说明和用户迁移说明。 | 发布前必须重跑权威验证命令并记录 commit。 |

## 4. 用户入口任务验收状态

这张表是分支内的 agent task 台账，不是发布排期。`Accepted` 表示在当前分支已有代码和测试证据；`In Review` 表示已有切片但仍有上表列出的用户证据或发布 gate 未完成。

| TaskID | 状态 | Parent Capability | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| UFA-C01-T01 | Accepted | Selection KnowledgeCard | 选中文本生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore | `SelectionKnowledgeCardProducer` | 已通过 producer 测试，重复点击不重复写入。 |
| UFA-C01-T02 | Accepted | Selection KnowledgeCard | 阅读页选中菜单显示 `知识卡`。 | UFA-C01-T01, E07 menu | `ExcerptMenu` action, l10n keys, reader context fallback resolver | widget 覆盖 `Card/Seminar/Graph` 入口可见；点击 `Card` 调用 selection KnowledgeCard producer，传入 book/cfi/选中文本/标题上下文，显示 Review feedback 并关闭菜单；无注入 context/creator 的点击级测试覆盖 reader context fallback resolver 和默认 `SelectionKnowledgeCardProducer()` 文件 store 写入，验证 pending KnowledgeCard、pending ReviewItem、SourceRef、重复点击不重复写。生产默认 resolver 仍读取 `epubPlayerKey.currentState`。 |
| UFA-C01-T03 | Accepted | Image Analysis KnowledgeCard | 图片解析结果生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 image analysis sheet | `ImageAnalysisKnowledgeCardProducer`, `AiImageAnalysisSheet` Card action, `ImageViewer` analysis/card seams | 图片解析结果弹层显示 `Card` 入口；producer 覆盖 pending KnowledgeCard 和 pending ReviewItem、重复点击和不自动写长期资产；ImageViewer 工具栏点击 `AI Image Analysis` 后使用可注入分析流打开弹层，点击 `Card` 写入 pending image-analysis KnowledgeCard 和 pending ReviewItem，保留 book/cfi/href SourceRef 且不保存图片本体。 |
| UFA-C01-T04 | Accepted | RAG Evidence KnowledgeCard | 本地 RAG/GraphRAG evidence 生成待审 KnowledgeCard。 | E00 SourceRef, E02 RAG evidence, E03 store, E05 ReviewItemStore, E07 ConceptGraph empty state | `RagEvidenceKnowledgeCardProducer`, `ConceptGraphExplorerNotifier.createKnowledgeCardFromLibrarySearch`, 空态 `Card` action | 只有 traceable chunk SourceRef 且带可保存 chunk snippet 的 RAG evidence 能写 pending KnowledgeCard 和 pending ReviewItem；derived summary 不替代书内 chunk evidence；不写正式图谱或长期资产；写入后页面显示 Review inbox 反馈。 |
| UFA-C01-T05 | Accepted | AI Chat KnowledgeCard | AI Chat 回答显式生成待审 KnowledgeCard。 | E00 SourceRef, E03 store, E05 ReviewItemStore, E07 AI Chat message action | `AiChatKnowledgeCardProducer`, `AiChatStream` 回答旁 `知识卡` action, answer-side source status chip, `ExcerptMenu` AI sourceRef handoff, `conversationV2` user-node SourceRef persistence | 回答完成后才可点击 `知识卡`，streaming 中按钮禁用且 producer 调用数为零；回答旁显示可跳转或不可用来源状态；选中文本进入 AI 草稿且发送内容仍包含原选中文本或 SourceRef snippet 时，才保留并持久化精确 reader SourceRef；历史重载后 `知识卡` 仍优先使用原始 reader SourceRef；无关改写不保存旧 reader SourceRef；短公共片段碰巧命中不保存旧 reader SourceRef；reader-grounded card 带保守 `conceptRefs`，纯聊天 card 不带；重复点击不制造重复卡；不直接写 ConceptGraph、长期记忆、笔记或 spaced review。 |
| UFA-C01-T06 | Accepted | Selected-text AI launcher widget evidence | 阅读页选中文本 `AI` 按钮点击级 widget 测试，证明会打开 AI chat draft 并传 reader SourceRef。 | UFA-C01-T05, E07 menu | `ExcerptMenu.aiChatDraftOpener` seam, `ExcerptMenu` AI action widget tests | 点击 `AI` 后草稿包含选中文本；有效 `bookId + cfi` SourceRef 被传入 chat；无有效 anchor 时不伪造 reader grounding。 |
| UFA-C02-T01 | Accepted | Seminar launcher | 阅读页选中菜单显示 `研讨`，打开结构化 Seminar runtime page。 | AI Seminar runtime, E07 menu | `ExcerptMenu` action | 入口可见；选中文本预填；不自动写用户资产。 |
| UFA-C02-T02 | Accepted | Structured Seminar runtime UI | 把 `AiSeminarOrchestrationService` 接入真实模型流式事件。 | E01 services, E06 governance, E07 progress UI | `AiSeminarRuntimeService`、`aiSeminarRuntimeProvider`、`AiSeminarRuntimePage` | 角色 turn、evidence、whiteboard、synthesis 进入可序列化 runtime state；失败可重试，运行可取消。 |
| UFA-C02-T03 | Accepted | Seminar Review handoff | Seminar synthesis 和候选卡进入 Review Inbox。 | UFA-C02-T02, E05 controller | `AiSeminarRuntimeNotifier.sendToReview` + `SeminarSynthesisReviewAdapter` | 只有 `readyForReview + traceable handoff` 的 synthesis 进入 pending Review；候选卡保持 AI draft/pending，不直接应用；页面级 widget 覆盖用户点击 `Start Seminar` 后再点击 `Send to Review`，并断言 synthesis、KnowledgeCard ReviewItem 和 seminar KnowledgeCard 均为 pending/draft 边界。 |
| UFA-C02-T04 | Accepted | Seminar Flashcard handoff | Seminar reviewSuggestion 进入 flashcard Review。 | UFA-C02-T03, UFA-C04-T01 | `SeminarSynthesisReviewAdapter.flashcardsFromSynthesis`, `FlashcardReviewAdapter`, `ReviewInboxController` | 只有 traceable synthesis 的 candidate review question 会生成 pending flashcard；页面级 widget 覆盖 `Send to Review` 后 flashcard candidate 进入 pending ReviewItem；用户 Apply 后进入 Spaced Review；不绕过 Review。 |
| UFA-C02-T05 | Accepted | Seminar provider readiness | Seminar 页面启动前显示当前 provider/model/capability 和成本透明度。 | Provider Center capability cache, UFA-C02-T02 | `AiSeminarProviderContextService`, `AiSeminarRuntimeState.providerDiagnostics`, `AiSeminarRuntimePage` Provider readiness section | 从 `Prefs.selectedAiService`、provider metadata、AI config 和 `AiModelCapability` cache 解析 provider/model/context/max output/Tools/Vision/Thinking/pricing metadata；当前 schema 没有 streaming 字段时显示 `Streaming unknown`，不伪造支持；runtime `start` 前捕获 diagnostics 并随 state JSON restore；页面显示 `Provider readiness`、capability chips、缺少 pricing metadata 时的 `Cost: unknown` 和原因，有 pricing metadata 时显示可用于 estimated USD cap；不读取或展示 API key，不把估算成本声明为真实账单。 |
| UFA-C02-T06 | Accepted | Seminar local token usage | Seminar 角色输出显示本地 token 估算并随 runtime state 恢复。 | UFA-C02-T02, UFA-C02-T05 | `AiSeminarTokenUsage`, `AiSeminarRuntimeService` local estimator, `AiSeminarRuntimePage` usage UI | 每个通过 evidence gate 的 completed role turn 都写入 `tokenUsage(inputTokens/outputTokens/isEstimated/estimationMethod=local-char-estimate-v1)`；`AiSeminarRun` 聚合 usage，state JSON restore 保留 turn/run usage；页面显示 `Local token estimate`、input/output 和 `Provider billing may differ`，继续显示 `Cost: unknown`，不读取 API key，不调用 provider，不把本地估算当作美元成本。 |
| UFA-C02-T07 | Accepted | Seminar local recovery | Seminar runtime state 保存为本机恢复缓存，重新打开页面可恢复同一入口的已完成或已中断状态。 | UFA-C02-T02, UFA-C02-T06, E07 recovery gate | `aiSeminarRuntimeStateV1PrefsKey`, `AiSeminarRuntimeNotifier` persistence/restore, `AiSeminarRuntimePage` recovered banner, prefs backup skip | completed/cancelled/failed state 会写入 `aiSeminarRuntimeStateV1` 本机缓存；同一书籍/同一入口问题的新页面会恢复 state 并显示 `Recovered local Seminar state`；换书或换选区会清掉旧 runtime/cache，不展示旧研讨；traceable evidence checkpoint 的 running 恢复由 `UFA-C02-T16` 接管；checkpoint 无效、evidence 不可追踪或 provider 已切换时降级为 cancelled/interrupted 且 `canRetry=true`，并回写清理 active role / partial text；该缓存被普通 prefs backup 排除，不同步，不导出 API key 或正文到 backup；恢复态保留生成时保存的 provider/model diagnostics，retry 时再使用当前 provider 设置。 |
| UFA-C02-T08 | Accepted | Seminar local token budgets | 用户在 Seminar 页面设置本地 role/run token budget，并在超限时停止后续步骤。 | UFA-C02-T06, mobile resource gate | `AiSeminarBudgetPolicy`, `AiSeminarRuntimeService` budget gate, `AiSeminarRuntimePage` Local budget guardrails | Session contract round-trip 保存 `maxRoleOutputTokens/maxRunTokens`；页面显示 `Local budget guardrails`、`Role output token budget` 和 `Run token budget`；runtime 用 `local-char-estimate-v1` 判断 token 超限，流式 partial 超出 role output budget 时取消 active stream，completed turn 超出 role/run budget 时停止后续步骤；超限进入 failed/retryable，不生成 synthesis，不发送 Review；restore/retry 保留 session budget policy；不把本地 token 预算冒充 provider billing 或美元成本上限。 |
| UFA-C02-T09 | Accepted | Seminar provider token usage | provider/SDK 返回 token usage metadata 时，Seminar turn/run 保存并显示 provider-reported token usage。 | UFA-C02-T06, UFA-C02-T08 | `CancelableLangchainRunner.stream`, `AiUsageTracker`, `AiSeminarModelRoleExecutor`, `AiSeminarTokenUsage.source`, `AiSeminarRuntimePage` usage UI | 非 agent stream 完成后把 provider usage 记录到会话 tracker；role executor 按 session usage tracker 前后差值写入 `provider-reported` tokenUsage；run 聚合 provider/local mixed usage；页面显示 `Provider reported usage` 或 mixed/local fallback；local role/run token budget 仍只使用 `local-char-estimate-v1`；provider token usage 只作为估算成本输入之一，不等于真实账单。 |
| UFA-C02-T10 | Accepted | Seminar estimated USD cost cap | 用户在 Seminar 页面设置估算 `Run cost cap USD`，超出时停止后续步骤。 | UFA-C02-T05, UFA-C02-T09 | `AiModelCapability` pricing metadata, `AiSeminarBudgetPolicy.maxRunCostUsd`, `AiSeminarRuntimeService` cost gate, `AiSeminarRuntimePage` cost cap UI | Provider capability cache 带 input/output/cache pricing metadata 时，页面启用 `Run cost cap USD` 并显示 pricing source；session/run JSON round-trip 保存 pricing policy 和 estimated cost；runtime 聚合 provider-reported usage 或本地 fallback usage 估算美元成本，超出 cap 时进入 failed/retryable、保留已完成 turn、不生成 synthesis、不发送 Review；无 pricing metadata 时禁用 cost cap 并显示原因；估算成本不声明为 provider invoice。 |
| UFA-C02-T11 | Accepted | Seminar background job snapshot | 把 Seminar running state 接入可取消的本机 job snapshot，并为恢复语义保留 job id。 | UFA-C02-T07, mobile resource gate | `AiSeminarBackgroundJobSnapshot`, `AiSeminarRuntimeState.backgroundJob`, `AiSeminarRuntimeNotifier` job lifecycle, `AiSeminarRuntimePage` job status line | 启动会持久化 running job id；completed/needsEvidence/failed/cancelled 会写终态；cancel 会标记 cancelled；retry 会生成新 job id；有 traceable evidence checkpoint 的 persisted running 由 `UFA-C02-T16` 复用同一 job id 继续缺失角色；同一恢复快照里带完整 session 的 queued job 可继续排队；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时标记 interrupted/retryable，且不生成 synthesis、不开放 Review；页面显示 `Background job: <status> · <id>`；不含 API key，不同步；不是并发队列，也不是旧 LLM stream 原地续传。 |
| UFA-C02-T12 | Accepted | Provider billing reconciliation | 记录 provider pricing source/optional version/usage snapshot，并在 UI 中区分 estimate、provider metadata 和 invoice reconciliation。 | UFA-C02-T10 | `AiSeminarBillingContext`、`AiSeminarBillingSnapshot`、`AiSeminarRuntimeService` billing snapshot、`AiSeminarRuntimePage` billing reconciliation UI | 每个有 token usage 的终态 Seminar run 保存 usage snapshot、provider/model、pricing source/optional version、pricing captured time、估算 USD 和 invoice status；页面显示 `Estimated cost, not invoice`、`Usage snapshot`、`Pricing snapshot` 和 `Invoice reconciliation`；默认 invoice import 未连接时显示 `Not connected` 和原因；已覆盖 snapshot round-trip、runtime not-connected 状态和页面展示；不把 local budget 或 estimated USD cap 声明为真实扣费上限。 |
| UFA-C02-T13 | Accepted | Selected-text Seminar SourceRef seed | 阅读页选中文本 `研讨` 入口把真实 reader SourceRef 写入 Seminar session，并作为优先 evidence seed。 | UFA-C02-T01, E00 SourceRef, E01 evidence broker, E07 menu | `AiSeminarSessionContract.sourceRefs`, `AiSeminarEvidenceBroker`, `AiSeminarRuntimePage.initialSourceRef`, `ExcerptMenu` seminar launcher | session JSON round-trip 保留 reader SourceRef；点击 `研讨` 后 runtime page 持有 bookId/CFI/snippet/sourceKind；`Start Seminar` 把 SourceRef 传入 session，evidence broker 先生成 `Reader selection` evidence，再执行 current-book search；runtime provider 重建 session 时保留 sourceRefs；同书同问题但 CFI/SourceRef 不同时会丢弃旧本机恢复缓存；hash-only、不可追踪或无 snippet 的 SourceRef 不进入 formal evidence。 |
| UFA-C02-T14 | Accepted | Seminar background job ledger | 本机保存最近 Seminar job 账本，并让取消操作只命中对应 job。 | UFA-C02-T11, mobile resource gate | `AiSeminarRuntimeState.backgroundJobs`, `AiSeminarRuntimeNotifier.cancelBackgroundJob`, `aiSeminarRuntimeStateV1` JSON | 多次 Seminar run 会在本机 runtime cache 中保留去重后的最近 job 记录；`backgroundJob` 仍代表当前页面显示的当前 job；terminal event 会同步更新账本中的对应 job；旧 terminal job id 调用 `cancelBackgroundJob` 不影响当前运行；当前 job id 会走同一 cancel lifecycle；账本不含 API key，不同步，不表示进程死亡后继续 stream。 |
| UFA-C02-T15 | Accepted | Seminar local serial queue | 运行中再次启动 Seminar 时进入本机串行 queued job，并在页面可见和可取消。 | UFA-C02-T14, mobile resource gate | `AiSeminarBackgroundJobStatus.queued`, queued `AiSeminarBackgroundJobSnapshot.session`, `AiSeminarRuntimeNotifier` serial scheduler, `AiSeminarRuntimePage` `Queue Seminar` / `Seminar job queue` | active Seminar 运行中再次点击会创建 queued job，不取消 active token；当前 job 进入 completed/failed/cancelled/needs-evidence 后才启动下一条 queued job；queued 真正启动前会按当前 provider diagnostics 重新绑定 billing context 和 budget policy；取消 queued job 不取消 active stream；本机恢复时如果没有可续跑 active checkpoint，queued job 标记为 interrupted，不自动继续生成；同一恢复快照存在可续跑 active 且 queued 带完整 session 时，queued 保持 queued 并在 active 续跑完成后启动；页面显示 running/queued job 和问题文本；测试覆盖 provider scheduler、provider switch rebind、queued cancel、restore interrupted 和页面点击路径；不是并行执行、不是 OS/background execution，也不是 provider invoice import。 |
| UFA-C02-T16 | Accepted | Seminar checkpoint resume | App 重启后从 traceable evidence checkpoint 继续 Seminar。 | UFA-C02-T07, UFA-C02-T11, UFA-C02-T15, mobile resource gate | `AiSeminarRuntimeCheckpoint`, `AiSeminarRuntimeService.run(checkpoint:)`, `AiSeminarRuntimeNotifier` restored running auto-resume | 恢复只信任可追踪 evidence、合法连续 completed role prefix 和当前匹配的 provider/model/pricing；复用持久化 evidence bundle，不重新 fetch evidence；已有 completed role 不重跑，缺 tokenUsage 的 checkpoint turn 会补 `local-char-estimate-v1`，避免终态 usage/cost 漏算；没有 completed turn 但已有 evidence 时从首个角色重新生成；只有 active partial stream 时丢弃半截文本并重新生成缺失角色；继续时保留原 background job id；同一恢复快照里带完整 session 的 queued job 会保持 queued，并在 active 续跑完成后自动启动；checkpoint 无效、evidence 不可追踪、provider 已切换、没有可恢复 active job 或 queued job 缺少 session 时标记 interrupted/retryable；dispose 后不得写已销毁 notifier；不是 OS/background execution，也不是旧 LLM stream 原地续传。 |
| UFA-C02-T17 | In Review slice | Chat Seminar DirectorState | 把 Seminar 从固定角色顺序推进为 AI Chat 可恢复 Director loop。 | UFA-C02-T16, E01-C05-T01 | `AiSeminarDirectorState`、`AiSeminarRuntimeState.directorState`、runtime JSON、tests | 第一片已接入：DirectorState 可记录轮次、已完成角色、已完成 turn id、证据账本、白板账本、分歧 id、证据刷新次数、用户插话状态和下一步 intent；runtime state JSON 可恢复该账本；用户插话明确不是 formal evidence；恢复时已有 `remainingRolesFor` 可跳过已完成角色；completed run 留下 open question 时会标记 `askUser`，留下 disagreement 且有轮次预算时会标记 `refreshEvidence`，状态区显示主持人下一步；用户提交回复后写入 `lastUserIntervention` 并把下一步 intent 转成 `runRole / refreshEvidence / synthesize`；`runRole` 已能通过 `executeDirectorNextStep` 调用目标角色生成 follow-up turn，用户触发的 `refreshEvidence` 已能重新检索 evidence、重跑角色并更新 synthesis，用户触发的 `synthesize` 已能用现有 evidence/turns 执行本地 synthesis 并收束为 `end`；completed run 即使没有 open question，也会在 synthesis 后显示 `Continue discussion / 继续讨论` 并保存读者回合；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，会自动刷新 evidence 并重跑角色，刷新后仍有分歧且预算耗尽时转为 `askUser`。AI Chat 轻量历史入口卡片已接入；仍需完整 rebuttal loop 和结构化 Chat run card 子视图；不得生成第二套 Seminar runtime state。 |
| UFA-C02-T18 | In Review slice | Seminar role prompt settings | 用户可编辑多角色提示词和角色策略。 | UFA-C02-T17, E06 governance | `AiSeminarRoleProfile`、`Prefs.aiSeminarRoleProfiles`、`AiSeminarConfigPage` role profile fields、runtime prompt injection | 已完成角色显示名和 custom prompt：默认角色保留 `critical/supportive/synthesizer/verifier`；设置页保存 profile；新 session 会把 profile 写入 `AiSeminarSessionContract` 并注入 role prompt；session JSON 与 provider budget rewrite 不丢 profile。仍需拆角色启用状态、证据策略、工具范围、空 prompt validator 和 AI Chat 内嵌配置入口。 |
| UFA-C02-T19 | In Review slice | Multi-round evidence refresh | 讨论出现分歧或证据不足时，Director 可以重新检索并进入反驳轮。 | UFA-C02-T17, UFA-C07-T05 | Director loop service、contradiction scan、evidence refresh tests | 已完成用户触发和自动触发的 evidence refresh 执行路径：用户在 `askUser` 状态点击“重新找证据”后，runtime 会重新调用 evidence broker、保留 current book first、重跑角色并更新 synthesis；completed run 只留下 disagreement 且仍有 `maxRounds` 刷新预算时，runtime 会在启动 queued job 前自动刷新 evidence 并重跑角色；每次刷新后的 evidence 仍需 SourceRef，刷新后仍有分歧且预算耗尽时转为 `askUser`。AI Chat 轻量历史入口卡片已接入；仍需覆盖结构化 contradiction gap scan、角色针锋相对的 rebuttal turn 和结构化 Chat run card 子视图；默认不开 web。 |
| UFA-C02-T20 | In Review slice | User-in-the-loop Seminar | 用户能在 AI Chat 中插话、指定追问角色或回答澄清问题。 | UFA-C02-T17, E07 Chat UI | `AiSeminarUserIntervention`、`AiSeminarRuntimeNotifier.recordUserIntervention`、`AiSeminarRuntimeNotifier.executeDirectorNextStep`、`AiSeminarRuntimeService.runUserDirectedRole`、`AiSeminarRuntimePanel` reader turn UI、tests | 第一片已接入：Director 可进入 `needsUserInput`；页面显示用户回复输入框、目标角色选择、让角色回应、重新找证据和整理总结动作；用户输入保留为 `lastUserIntervention` human turn，不写 `evidenceBundle`、不当作 AI evidence；点击“让所选角色回应”会把用户输入注入目标角色 prompt，调用所选角色生成 follow-up turn，并用现有 evidence 与 prior turns 更新 synthesis；点击“重新找证据”会保存 human intervention、重新检索 evidence、重跑角色并更新 synthesis；点击“整理总结”会保存 human intervention，用现有 evidence 与 turns 执行本地 synthesis，并把 Director 收束为 `end`；completed run 没有 Director 提问时也显示 `Continue discussion / 继续讨论`，允许用户继续推动角色或证据刷新。AI Chat 轻量历史入口卡片已接入；仍需完整 Chat run card 子视图。 |
| UFA-C02-T21 | In Review slice | AI Chat Seminar run card | 在 AI Chat 内展示多角色讨论，而不是强制跳到独立 Seminar 页面。 | UFA-C02-T17, UFA-C02-T20 | `AiSeminarRuntimePanel`、AI Chat inline panel entry、`AiSeminarRunCardMeta`、Seminar runtime page compatibility、l10n | 已完成第二片：AI Chat `+` -> `AI 研讨会` 在当前 AI Chat 页面内展开 Seminar runtime panel，带入输入框问题，不改变 active skill；同时向当前 `conversationV2` 追加用户问题和带 `seminarRunCard` meta 的 assistant fallback message，历史重载后可渲染轻量 `AI 研讨会` 卡片并点击重新打开 inline runtime；阅读页选中文本 `研讨` 也已进入阅读页 AI Chat 的内嵌 runtime panel，带入 reader SourceRef；面板可关闭，也可跳到完整 runtime page；旧 `Choose style -> 研讨会设置` 路径仍只打开配置页；用户 askRole follow-up、用户触发的 refreshEvidence、用户触发的 synthesize、completed continuation composer 和 disagreement 预算内自动 refresh 会在同一面板中更新角色回应、证据或 synthesis。仍需完整 AI Chat message part 的证据/角色/分歧/白板/总结/送审子视图、分歧 tab 和 per-run 多实例隔离。 |
| UFA-C02-T22 | In Review slice | Seminar entry migration | 阅读页和 AI Chat 的 Seminar 入口默认进入 Chat 内嵌 run，独立页只作为详情/恢复入口。 | UFA-C02-T21 | entry router、compatibility tests | 已完成第二片：阅读页选中文本 `研讨` 不再 push 独立 `AiSeminarRuntimePage`，而是打开阅读页 AI Chat 并调用内嵌 Seminar panel；该路径保留 SourceRef/bookId/snippet，不改 `activeAiSkillId`。AI Chat `+` 入口现在会写轻量历史入口卡片，历史重载后仍能重新打开 inline runtime。仍需把轻量卡片升级为完整结构化 Chat run card，并让独立页面读取同一 run-scoped state；历史恢复、queued job、budget、Review handoff 不得分叉。 |
| UFA-C03-T01 | Accepted | Concept producer | 从 KnowledgeCard、Seminar candidate concept refs、reader-grounded AI Chat concept refs 和 derived RAG/GraphRAG search result 提取有证据的 ConceptNode/Edge 候选。 | E03, E04 store, E05 controller, UFA-C01-T05, UFA-C02-T03, E02 SourceRef evidence | `ConceptGraphProducer`, ReviewInboxController apply hook, Seminar candidate `conceptRefs` handoff, AI Chat card `conceptRefs` handoff, `createFromLibrarySearchResult`, `ConceptGraphExplorerNotifier.createDraftCandidateFromLibrarySearch` | 只有 `applied + traceable + conceptRefs` 的 KnowledgeCard，或 `derivedLayer/derivedSummary + traceable chunk SourceRef` 的 library RAG result，生成 draft node/edge；Seminar candidate card 和 reader-grounded AI Chat card 可携带 conceptRefs 并在用户 Apply 后进入同一链路；relation 进入 pending Review；ConceptGraph 空态显性 action 已接，并展示 Review/skip feedback。 |
| UFA-C03-T02 | Accepted | Concept Explorer page | 提供局部图谱探索入口。 | E04 dossier/explore | `ConceptGraphExplorerPage`, provider, Settings AI entry, local graph map canvas, local graph map summary, injectable source opener | 用户能打开概念页、看中心概念、直接关系、二跳节点、evidence link 数量、draft/formal 状态、局部节点-连线图、局部路径、原文跳转和 orphan/broken link；`Open source` 点击会把 jumpable SourceRef 交给 opener，不可跳来源显示原因且不触发 opener；Settings AI 点击级测试覆盖 `Settings -> AI -> Concept graph` 导航到 Explorer。 |
| UFA-C03-T03 | Accepted | Reader concept entry | 阅读页选中文本可进入概念探索。 | UFA-C03-T02 | `ExcerptMenu` graph action, `ConceptGraphExplorerPage.initialQuery` | 选中文本可打开图谱页并筛选相关概念；没有相关概念时展示空态和草稿候选入口，不生成无证据正式节点。 |
| UFA-C03-T04 | Accepted | Full-book derived graph preview | Settings 和阅读页图谱入口展示书籍级全局层只读派生关系图。 | E02 global layer, E04 Explorer, E07 reader entry | `AiGlobalDerivedBookConceptGraphLoader`, `AiGlobalDerivedBookConceptGraphCatalog`, `conceptGraphDerivedBookLoaderProvider`, `conceptGraphDerivedBookCatalogProvider`, `ConceptGraphExplorerPage.bookId`, `ExcerptMenu` graph action | Settings `Concept graph` 入口会列出已有全局层的已索引书，可选择书籍并显示 `全书自动图谱 / Full-book auto graph`；阅读页 `图谱/Graph` 入口把当前 bookId 传入 Explorer 并直接显示 `全书派生图谱 / Full-book derived graph`、节点数、关系数和只读 canvas；loader 只读取 `ai_graph_nodes / ai_graph_edges / ai_graph_node_chunks / ai_chunks`，只展示带 chunk SourceRef 的 derived-cache 节点/关系；缺表、无 evidence 或无全局层时显示空态/提示；不写正式 ConceptGraph、ReviewItem、KnowledgeCard、Memory、Note、Sync 或 spaced review。 |
| UFA-C04-T01 | Accepted | Spaced Review | Review apply 后生成复习队列。 | E03, E05 | `SpacedReviewStore`, `spacedReviewProvider`, `SpacedReviewPage`, `SourceRefEvidenceList`, injectable source opener, Settings AI entry | 复习项可回溯到卡片和原文；页面显示证据摘录和不可用来源原因；删除书后显示可解释状态；评分记录下一次到期时间；`Open source` 点击会把 jumpable SourceRef 交给 opener，不可跳来源显示原因且不触发 opener；Settings AI 点击级测试覆盖 `Settings -> AI -> Spaced review` 导航到复习页。 |
| UFA-C04-T02 | Accepted | Flashcard Review apply | 待审 flashcard 应用后进入 Spaced Review。 | E05 controller, UFA-C02-T04 | `SpacedReviewStore.reviewIdForFlashcard`, `upsertFromFlashcardReviewItem`, `ReviewInboxPage` Apply gate | pending/approved flashcard 不直接入队；只有用户在 Review Inbox 点击 enabled `Apply` 后，applied 且 traceable 的 flashcard 才能入队；重复入队不制造重复复习项。 |
| UFA-C04-T03 | Accepted | Memory Review apply | 待审 MemoryCandidate 通过统一 Review Inbox 应用到本地 Markdown memory。 | E05 controller, MemoryWorkflowService, MemoryCandidateReviewAdapter | `MemoryWorkflowService.addToReviewInbox` -> `ReviewItemStore` handoff, `ReviewInboxController` memory source-specific apply/dismiss adapter, `ReviewInboxPage` Apply gate | AI Chat memory action 创建 pending MemoryCandidate 时同步创建 pending ReviewItem；conversation-only memory SourceRef 带 evidence snippet、source hash 和不可跳原因；Review Inbox `Approve -> Apply` 先调用 MemoryWorkflowService 追加到目标 daily/long-term Markdown，再推进 ReviewItem；`Dismiss` 同步 MemoryCandidate 且不写 memory；source candidate 缺失不推进 ReviewItem；不写 KnowledgeCard、ConceptGraph、SpacedReview、Sync 或 Note。 |
| UFA-C04-T04 | Accepted | BookNote SourceRef audit | 旧划线/笔记条目显示来源证据和可跳/不可跳状态。 | E00 SourceRef, E07 deep link, BookNote UI | `BookNoteSourceRefAdapter`, `BookNoteTile`, `BookNotesList`, search note result, `SourceRefEvidenceList` | Notes 列表和搜索结果传入 source title；BookNoteTile 显示 evidence、traceable/unavailable chip、来源位置和不可跳原因；有有效 `bookId + cfi` 的条目保持原文跳转；无有效 book anchor 条目点击只显示不可跳 snackbar，不触发空 CFI 或无效 book anchor 跳转；测试覆盖 adapter 和 widget。 |
| UFA-C04-T05 | Accepted | Memory browse SourceRef audit | Memory home、daily memory、long-term memory 浏览 UI 显示来源证据和可跳/不可跳状态。 | E00 SourceRef, E05 MemoryCandidate, E07 deep link, Memory browse UI | `MemoryEntrySourceRefAdapter`, `MemoryEntryRef.body/supportsBulkActions`, `MemoryRow` source audit chips, `MemoryDetailPage` source evidence/open source, Home navigation Memory label/icon | 只读投影已应用 MemoryCandidate；按目标文档和条目 body 匹配，summary-only 不归因，long-term H1 分段不共享整文件来源；列表显示 traceable/unavailable/unresolved chip；详情页显示 Evidence 和 `Open source`；可跳来源交给 reader opener，不可跳来源显示原因且不调用 opener；long-term H1 分段不允许批量删除/打标签，详情页也不显示会写整份 `MEMORY.md` 的 tag editor；不写 Markdown metadata、不写任何新知识资产。 |
| UFA-C04-T06 | Accepted | AI Chat Memory popup widget evidence | 回答旁书签图标打开 popup 并点击 `Add to Review inbox` 的 widget 测试。 | UFA-C04-T03, AI Chat message actions | `AiChatStream.memoryWorkflowService` seam, `test/ai_chat_stream_memory_actions_test.dart` | 点击 Memory icon 展示 `Memory actions / 记忆操作` 菜单；点击 `Add to Review inbox / 加入待审核队列` 调用 memory handoff；streaming 或空回答不写 memory candidate。 |
| UFA-C04-T07 | Accepted | Settings Review Inbox navigation evidence | Settings 顶层 AI 区和 `Settings -> AI` 子页进入 Review Inbox 的点击级 widget 测试。 | E05 Review Inbox UI, E07 navigation | `test/page/settings_page/settings_navigation_compile_test.dart` | 两条路径都能打开 `ReviewInboxPage`；空 inbox 显示空态而不是导航失败；不创建 ReviewItem。 |
| UFA-C05-T01 | Accepted | Sync / Export | 用户确认资产进入同步和导出入口。 | E08 policy | `KnowledgeAssetExportService`、`knowledgeAssetExportProvider`、`KnowledgeAssetExportPage`、Settings AI entry、export manifest、Markdown export、HTML study report、Anki TSV export、sync-conflict ReviewItem handoff | API key 不同步；派生索引不当作 source-of-truth；冲突被排除并显性显示；当前创建本地 manifest、Markdown 学习导出、HTML study report 和 Anki TSV，并能把待审冲突送入 Review Inbox；导出页在发送成功后显示 `Review inbox` 直达入口；provider 级测试覆盖 `KnowledgeAssetExportNotifier -> ReviewInboxNotifier -> ReviewInboxController -> KnowledgeCardStore/ReviewItemStore` 的安全 KnowledgeCard 冲突 approve/apply 闭环，解除 pending conflict 并重新进入导出集合；不执行远端写回或自动跨设备合并。 |
| UFA-C05-T02 | Accepted | Remote sync preview | 用户从 Knowledge sync/export 读取远端 sync bundle，预览 per-entity incoming/outgoing/conflict，并把远端冲突送入 Review。 | UFA-C05-T01, E08 sync bundle, SyncClient/WebDAV config, E05 ReviewItemStore | `.knowledge/knowledge_sync_bundle_v1.json`, `KnowledgeRemoteSyncPreview`, `KnowledgeAssetExportService.previewRemoteSync`, `submitRemoteConflictsToReview`, `KnowledgeAssetExportNotifier.previewRemoteSync`, `KnowledgeAssetExportPage` `Preview remote sync` / `Send remote conflicts to Review` actions | sync bundle 只包含默认纳入的安全 envelope；remote preview 读取 `paper_reader/.knowledge/knowledge_sync_bundle_v1.json` 并展示 remote/incoming/outgoing/conflict 计数；preview 不导入 incoming、不覆盖本地资产；远端冲突 ReviewItem 只保存安全 metadata、payload keys、SourceRef count 和 safe SourceRef；远端 preview 冲突一律 `canApply=false`，只支持 dismiss/triage；安全 KnowledgeCard 本地 staged 冲突继续走 approve/apply，本地解除 pending conflict；不执行远端写回、自动合并或备份同步。 |
| UFA-C05-T03 | Accepted | Protected remote sync upload | 用户从 Knowledge sync/export 把本机安全 sync bundle 写到 WebDAV/SyncClient。 | UFA-C05-T02, SyncClient/WebDAV config | `KnowledgeAssetExportService.uploadRemoteSyncBundle`, `KnowledgeRemoteSyncUploadResult`, `KnowledgeAssetExportNotifier.uploadRemoteSyncBundle`, `KnowledgeAssetExportPage` `Upload sync bundle` action | 上传前重新生成本机安全 sync bundle；远端不存在时创建 `paper_reader/.knowledge` 并上传；远端存在时先 preview，只有 `incoming=0` 且 `conflict=0` 时允许 replace；存在 incoming 或 conflict 时抛错并保持 remote 未改；页面显示上传路径和上传数量；不导入 incoming、不应用远端冲突、不执行双向自动合并或备份同步。 |
| UFA-C05-T04 | Accepted | Remote incoming KnowledgeCard Review import | 用户从 Knowledge sync/export 把远端 incoming KnowledgeCard 发送到 Review Inbox。 | UFA-C05-T02, E03 KnowledgeCardStore, E05 ReviewItemStore | `KnowledgeAssetExportService.submitRemoteIncomingToReview`, `KnowledgeRemoteIncomingReviewResult`, `KnowledgeAssetExportNotifier.submitRemoteIncomingToReview`, `KnowledgeAssetExportPage` `Send remote incoming to Review` action | 只接受 `knowledge-card + schemaVersion=1 + 无 secret payload + 有 evidence` 的远端 incoming envelope；导入时降级为 pending KnowledgeCard 和 pending ReviewItem；重复导入不制造重复卡；非 KnowledgeCard、无 evidence 或 unsafe payload 跳过；不导入 reviewHistory、不应用远端冲突、不自动写用户资产、不写 memory/note/graph/spaced review。 |
| UFA-C05-T05 | Accepted | Remote review history Review import | 用户从 Knowledge sync/export 把远端 review history 发送到 Review Inbox。 | UFA-C05-T02, E05 ReviewInboxController, SpacedReviewStore | `KnowledgeAssetExportService.submitRemoteReviewHistoryToReview`, `KnowledgeRemoteReviewHistoryReviewResult`, `ReviewItemSourceType.reviewHistoryImport`, `ReviewInboxController` review history apply adapter, `SpacedReviewStore.upsertImportedReviewHistory`, `KnowledgeAssetExportPage` `Send remote review history to Review` action | 只接受 `review-history + schemaVersion=1 + 无 secret payload + 有 evidence` 的远端 incoming envelope；导入时只创建 pending ReviewItem；generic ReviewItemStore apply 被拒绝；用户在 Review Inbox approve/apply 后才写入 SpacedReviewStore；重复导入不制造重复复习记录；不应用远端冲突、不写 KnowledgeCard/Memory/Note/ConceptGraph。 |
| UFA-C05-T06 | Accepted | Remote KnowledgeCard conflict staged restore | 用户从 Knowledge sync/export 把安全远端 KnowledgeCard conflict 暂存到 Review Inbox，并在 Review Inbox 中确认恢复。 | UFA-C05-T02, E03 KnowledgeCardStore, E05 ReviewInboxController | `KnowledgeAssetExportService.stageRemoteKnowledgeCardConflictsToReview`, `KnowledgeRemoteConflictStageResult`, `KnowledgeCardStore.stageRemoteSyncConflict`, `KnowledgeCardStore.removeStagedRemoteSyncConflict`, `remote_sync_conflicts_v1.json`, `KnowledgeAssetExportPage` `Stage safe remote card conflicts to Review` action | 只接受 `knowledge-card + schemaVersion=1 + 无 secret payload + 有可追踪 SourceRef` 的远端 conflict；staging 只写 staged conflict store 和 pending sync-conflict ReviewItem，未 Apply 前不覆盖本机 KnowledgeCard；ReviewItem 写入失败会删除 staged entry；用户 Apply 后才写为本机 approved asset 并清掉 staged conflict；preview-only `Send remote conflicts to Review` 仍 `canApply=false`；重复、unsafe、untraceable 或无 staged envelope 的 apply 失败关闭；不远端写回、不双向自动合并、不写 Memory/Note/ConceptGraph/SpacedReview。 |
| UFA-C05-T07 | Accepted | Remote sync status panel | 用户从 Knowledge sync/export 看到远端同步当前状态和下一步动作。 | UFA-C05-T02, UFA-C05-T03, E07 observability | `KnowledgeRemoteSyncStatus`, `KnowledgeAssetExportState.remoteSyncStatus`, `KnowledgeAssetExportPage` remote status panel, l10n keys | 页面显示 `Not previewed / Review required / Ready to upload / Uploaded / Re-preview required / Concurrency guard unavailable / Failed`；远端 preview 出现 incoming/conflict 时显示 Review required；无 blocker 时显示 Ready to upload；上传成功显示 Uploaded；远端在 preview 后变化显示 Re-preview required；provider 缺少条件写保护显示 Concurrency guard unavailable；远端操作失败显示 Failed；刷新或重新创建 manifest 会清理旧上传状态；状态面板只解释下一步，不自动合并、不绕过 Review。 |
| UFA-C05-T08 | Accepted | Remote merge planner | 对 local/remote/base envelope 做三路 diff，输出 incoming/outgoing/conflict plan，不写本地或远端资产。 | UFA-C05-T07, E08 policy | `KnowledgeRemoteMergePlanner`、`KnowledgeRemoteMergePlan`、`KnowledgeAssetExportService._previewRemoteSync`、`test/models/knowledge_remote_merge_planner_test.dart` | Planner 支持 optional `base` 三路判断；远端 preview 会把同 remotePath 的本机 baseline 传入 planner，无 baseline 或 baseline 不合格时降级为保守 preview。已覆盖 same id same content、local changed vs base、remote changed vs base、delete/modify、unknown schema、secret payload、base unsafe envelope、no base divergent content、duplicate id、missing required id、whitespace padded id；canonical fingerprint 排除 `updatedAt`，不使用 whole-file newer-wins；preview conflicts 保持 pending Review handoff。 |
| UFA-C05-T09 | Accepted | Remote writeback executor | 只在 merge plan 无 incoming/conflict blocker 时写回远端 bundle，并保留 rollback snapshot。 | UFA-C05-T08 | `KnowledgeRemoteWritebackExecutor`、`KnowledgeRemoteWritebackException`、`KnowledgeRemoteSyncUploadResult.rollbackSnapshotFile`、provider rollback state、page rollback status | 远端写失败不改本地 confirmed asset；旧远端 bundle 写回失败后用 rollback snapshot 恢复；新远端 bundle 半写入失败后删除 partial remote；API key 和派生索引不得写出；状态面板显示 rollback snapshot、恢复或删除 partial 的结果。 |
| UFA-C05-T10 | Accepted | Remote writeback CAS guard | 在 SyncClient 层支持条件写或 ETag guard，降低 preview 与 replace/create 之间的并发覆盖风险。 | UFA-C05-T09, SyncClientBase/WebDAV | `SyncRemoteWritePrecondition`、`SyncClientBase.uploadFileConditionally`、`WebdavClient.uploadFileConditionally`、`SyncPreconditionFailedException`、`SyncConditionalWriteNotSupportedException`、provider/page `repreviewRequired` 与 `concurrencyGuardUnavailable` 状态、race tests、WebDAV adapter header tests | WebDAV 写回使用 `If-Match` 或 `If-None-Match`；远端在 preview 后被其他设备修改时不得覆盖；远端在 create 前被其他设备创建时不得覆盖；无法提供 ETag/CAS 的 provider 会拒绝覆盖并显示 guard unavailable；precondition 失败会显示重新 preview；测试覆盖 replace race、create race、unsupported CAS、页面状态、真实 WebDAV adapter 请求头和 HTTP 412 映射。 |
| UFA-C05-T11 | Accepted | Remote sync baseline source-of-truth | 成功远端写回后保存本机 remotePath baseline，下一次 preview 用它做三方 diff。 | UFA-C05-T08, UFA-C05-T10 | `KnowledgeAssetExportService.remoteSyncBaselineFile`、`_readRemoteSyncBaseline`、`_writeRemoteSyncBaseline`、`test/service/sync/knowledge_asset_export_service_test.dart` baseline tests | 只有 `uploadRemoteSyncBundle` 写回成功后才更新 `.knowledge/knowledge_sync_remote_baseline_v1.json`；baseline keyed by remotePath，只保存默认同步策略纳入的安全 envelopes，不保存 draft、secret payload、派生索引或待审冲突；写入新 baseline 时会丢弃旧文件中已污染或不合格的 remote entries；preview 读取同 remotePath baseline 后 local 单边变化成为 outgoing，remote 单边变化成为 incoming；baseline 缺失、损坏、路径不匹配、重复 ID、future schema、unsafe payload 或 malformed envelope 会降级为保守 preview；不自动导入 incoming、不自动覆盖本地或远端资产、不替代 ETag/CAS guard，也不声明完整跨设备后台同步。 |
| UFA-C05-T12 | Accepted | Safe remote sync run | 用户点击 `Run safe remote sync`，把远端 preview、Review blocker handoff 和无 blocker 上传串成前台安全运行。 | UFA-C05-T02, UFA-C05-T06, UFA-C05-T10, UFA-C05-T11 | `KnowledgeAssetExportNotifier.runSafeRemoteSync`、`KnowledgeAssetExportPage` `Run safe remote sync` action、l10n keys、provider/page tests | 点击后先执行 remote preview；存在 incoming/conflict blocker 时调用安全远端 KnowledgeCard incoming Review、review history Review、safe remote KnowledgeCard conflict staged Review 和 preview-only conflict triage Review，且不调用 upload；无 blocker 时调用受保护 `uploadRemoteSyncBundle`；上传成功清理旧 Review handoff 计数；不自动 apply 任何 ReviewItem，不同步 API key，不声明后台跨设备自动同步。 |
| UFA-C05-T13 | Accepted | Review Inbox safe sync conflict batch apply/retry | 用户在 Review Inbox 的 `Approved + Sync conflict` 视图批量应用已审核安全冲突，失败项保持 approved 可重试。 | UFA-C05-T06, UFA-C05-T12, E05 controller | `ReviewInboxController.applyApprovedSyncConflicts`、`ReviewInboxState.canApplyApprovedSyncConflicts`、`ReviewInboxNotifier.applyApprovedSyncConflicts`、`ReviewInboxPage` `Apply Sync conflict` / `Retry Sync conflict` action | 只批量处理 `approved + sync-conflict + canApply=true + traceable SourceRef` 的项目；preview-only、memory-candidate、pending 和无 evidence 项不进入批量 apply；批量执行按项调用 source-specific apply adapter，成功项推进 applied，失败项留在 approved 且保留重试入口；UI 显示部分失败错误，不把失败项伪装为已应用；测试覆盖 controller、provider 和页面入口。 |
| UFA-C05-T14 | Accepted | Foreground remote change check | 用户从 Knowledge sync/export 点 `Check remote changes`，只读检查远端 bundle 并看到 incoming/conflict 摘要。 | UFA-C05-T02, UFA-C05-T07 | `KnowledgeAssetExportState.lastRemoteCheckAt`、`KnowledgeAssetExportNotifier.checkRemoteChanges`、`KnowledgeAssetExportPage` `Check remote changes` action、l10n keys、provider/page tests | 点击后只调用 remote preview，记录本次前台检查，显示 `Remote changes found` 或 clean 摘要和 read-only 提示；不得调用 upload、不得调用任何 remote Review handoff、不得 apply；失败时清理 stale preview 和检查状态并进入 Failed；刷新或创建导出会清理旧检查状态；测试覆盖 provider read-only flags 和页面可见提示。 |
| UFA-C06-T01 | Accepted | Custom Skill 导入 | 用户从 Settings 导入 governed JSON skill，并在 Active Skill 或 AI Chat Choose style 中启用。 | E06 CustomSkillContract, AiSkillRegistry, LangChain runtime | `CustomSkillStore`、`CustomSkillsPage`、Settings AI entry、AI Chat `Choose style` configurable custom skill row、中文 ARB/l10n、`AiSkill.allowedToolIds/sceneIds`、`LangchainAiRegistry.enabledToolIdsForActiveSkill` | 有效 `CustomSkillContract(schemaVersion=1)` 可导入、upsert、禁用和删除；危险工具、递归 sub-agent、unknown scene/field 和类型错误不落库不激活；禁用 skill 不进入 Active Skill 或 AI Chat Choose style；运行时只保留 custom skill 声明过且当前 scene/permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具；widget 覆盖 `Settings -> AI -> Custom skills` 导航、粘贴 JSON 导入、AI Chat `Choose style` 自定义 skill 配置入口和配置点击不改变 active skill；中文界面显示 `自定义技能`、`导入技能`、`已安装技能` 和导入结果。 |
| UFA-C06-T02 | Accepted | Responses previous_response_id fallback | 第三方 Responses provider 拒绝 `previous_response_id` 时自动降级重试。 | Provider Center Responses config, LangChain runtime | `ChatOpenAIResponses` compatibility latch, fallback request builder, endpoint normalization, failure diagnostics | 只有明确 `previous_response_id` unsupported 的 HTTP 400 会 fallback；正常 provider 继续用 server-side continuation；unrelated 400 不 retry；用户把完整 `/responses` endpoint 粘进 baseUrl 时不会生成 `/responses/responses`；非 fallback 错误会附带 endpoint、model、是否发送 `previous_response_id`、是否发送 `conversation`、是否已经 fallback retry 的诊断；测试覆盖正向 fallback、负向错误保留和 endpoint normalization。 |
| UFA-C06-T03 | Accepted | Active Skill picker widget evidence | 从 `Settings -> AI -> Active Skill` 选择已启用 custom skill 的点击级 widget 测试。 | UFA-C06-T01 | `test/page/settings_page/settings_navigation_compile_test.dart` | 已启用 custom skill 出现在 picker；disabled custom skill 不出现；选择后 runtime registry 能读取 active custom skill 并收窄工具。 |
| UFA-C06-T04 | In Review slice | Built-in Skill prompt settings | AI Chat `Choose style` 的普通内置 skill 不再只有选择动作，可打开该 skill 的提示词附加设置。 | UFA-C06-T01, E06 governance, E07 Chat UI | `Prefs.aiSkillCustomPrompts`、`Prefs.setAiSkillCustomPrompt`、AI Chat `Choose style` built-in configurable row、`LangchainAiRegistry._activeSkillPrompt`、`test/ai_chat_stream_choose_style_config_test.dart`、`test/service/ai/langchain_registry_custom_skill_test.dart` | 普通内置 skill 行显示 `Skill settings / 技能设置`；点击设置不会改变当前 active skill；保存的 custom prompt 写入 `aiSkillPromptProfilesV1`，空内容清除 profile；prompt add-on 上限 2000 字符，保存时保留 profile 未来扩展字段；新 agent 请求会在该 skill 原始 system prompt 后追加 `## User Skill Settings`，并声明该段低于 PaperTok 隐私、证据、工具权限和写入确认规则；profile 只作用于普通内置 skill，不作用于 custom skill 或 `seminar_mode`；Seminar 行仍只打开 `AiSeminarConfigPage`，custom skill 行仍进入 `CustomSkillsPage`；当前只支持 prompt add-on，不支持内置 skill 的工具范围、证据策略、输出模板 schema 或单次 Chat run 临时覆盖。 |
| UFA-C07-T01 | Accepted | Current-book semantic search resource guard | 当前书语义搜索避免一次性全书向量/正文加载并串行化扫描。 | E02 current-book index, E06 tool governance, mobile resource gate | `SemanticSearchCurrentBook` paged scan/topK/text winner load/global lock, `AiToolRegistry` non-concurrent flag | scan columns 不含 `text/raw_text/embedding_json`；JSON fallback 按页批量；只为 winners 取正文；直接调用与 tool 调用都不并发扫描；测试覆盖分页列、winner text load、直接调用串行和 tool non-concurrent。 |
| UFA-C07-T02 | Accepted | Current-book semantic search background backend | 为当前书语义搜索增加候选预筛/ANN 或后台 isolate，并暴露取消或进度状态。 | UFA-C07-T01, E02 schema gate | `AiCurrentBookVectorPageScorer` backend seam, default background isolate scoring, FTS/BM25 candidate prefilter, cancellation/progress tests, synthetic large-book scan acceptance, `TocSearch.semanticProgress`, reading-page stale search cancel, tool timeout cancel | 已覆盖 background isolate scoring seam、FTS/BM25 只取候选 id、synthetic large-book 只扫描 candidate limit 而非全书 chunk、候选 vector row 不含 `text/raw_text/embedding_json`、FTS 无候选、MATCH 失败、候选过期或表缺失时进入 fallback 分页扫描路径、JSON fallback 仅覆盖候选页 blob 缺失行、取消后不回查 winners/不写 partial result、阅读页 semantic progress state 和工具 timeout cancel；SourceRef evidence 不降级；不是 sqlite-vec/Vec1/ANN 实验后端。 |
| UFA-C07-T03 | Accepted | AI Chat hidden streaming UI throttle | 阅读页 AI 面板隐藏或多 tab 非活动 chat 继续生成时降低 UI 重建频率。 | UFA-C01-T05, E07 mobile resource gate | `aiChatUiVisibleProvider`、`AiChat.setStreamingUiVisible`、`AiChat.flushPendingStreamingUi`、provider `onDispose` cleanup、`AiChatStream.uiVisible`、`AiMultiTabChat.uiVisible`、ReadingPage bottom-sheet `uiVisible` handoff、`test/providers/ai_chat_new_conversation_test.dart`、`test/ai_multi_tab_chat_visibility_test.dart` | 可见 chat 仍按 160ms 合并流式文本；隐藏阅读页 AI 面板或非活动 tab 的 chat 会把 pending streaming UI flush 降到约 1000ms；从可见切到隐藏时会取消已排队的短 flush 并按隐藏窗口重排；用户重新打开面板或切回 tab 时立即补刷 pending 文本；每个 tab 的 visibility provider scope 独立，切换 tab 不把活动/非活动状态串到其它 tab；关闭 streaming tab 会 dispose scope 并取消该 tab 的 generation subscription/timer；stream 完成时仍强制 flush；隐藏/切 tab 不取消后台生成、不丢 conversation history、不把该测试等同于真机 profile 通过。 |
| UFA-C07-T04 | Accepted | Current-book fallback scan budget | 无 FTS 候选或 FTS 不可用时限制前台 fallback 向量扫描规模。 | UFA-C07-T01, UFA-C07-T02, mobile resource gate | `SemanticSearchCurrentBook.maxFallbackVectorRows`, `foregroundFallbackVectorRowBudget`, `toolFallbackVectorRowBudget`, 阅读页/Seminar/tool 显式预算接入 | 阅读页 fallback 扫描最多 1024 行；AI Seminar evidence 和 `semantic_search_current_book` tool fallback 扫描最多 2048 行；FTS 命中候选路径不受 fallback 预算误伤；fallback progress 总量使用预算后行数；扫描列仍不含 `text/raw_text/embedding_json`；预算耗尽时返回带 message 的降级结果；测试覆盖无候选 fallback 只扫描预算行数。 |
| UFA-C07-T05 | Accepted | Library hybrid vector recall | 书库 RAG 让向量后端与 FTS/BM25 同时召回候选，而不是只在文本 miss 后 fallback。 | E02 library RAG, E06 tool contract | `SemanticSearchLibrary.usedVectorRecall`, `AiVectorSearchBackend`, `semantic_search_library_search_test.dart` | FTS 命中候选时仍调用 `AiVectorSearchBackend`；纯语义命中的 chunk 可进入最终 hybrid/MMR/rerank 排序；结果 JSON 区分 `usedVectorRecall` 与 `usedVectorFallback`；本地文本入口仍可关闭 query embedding/vector/rerank，避免外发正文；默认 backend 是 ANN -> native -> exact，但没有 Vec1 extension/table 时会降级，不误标发布级 ANN 完成。 |
| UFA-C07-T06 | Accepted | Library exact vector compact scan | 降低默认 exact backend 在书库 hybrid recall 中的内存峰值，并给 sqlite-vec/ANN backend 固化 winner hydrate contract。 | UFA-C07-T05, E02 library RAG | `AiExactVectorSearchBackend`, `ai_vector_index_test.dart`, `ai_local_vector_index_test.dart` | 主扫描不读取 `text/raw_text/context_text/embedding_json`；旧索引缺 blob 时只批量回查缺失行 JSON；只 hydrate top winner 正文；返回 winner 仍带 `local_vector_score` 和完整 evidence 所需字段；不是 ANN/Vec1/sqlite-vec 完成。 |
| UFA-C07-T07 | Accepted | Native vector shadow index prep | 为旧书库索引补建 native vector shadow rows，并把默认向量 backend 接成 ANN -> native -> exact fallback。 | UFA-C07-T05, UFA-C07-T06, E02 schema gate | `kAiIndexDbVersion = 12`, `ai_vector_index_rows`, `ai_vector_index_meta`, `AiNativeVectorIndexBuilder`, `AiVec1VectorIndexBuilder`, `AiAnnThenNativeThenExactVectorSearchBackend`, `AiLibraryIndexPage` `向量索引升级` tile | v12 schema 创建 shadow rows/meta 表和索引；backfill 可把已有 blob 或旧 JSON vector 写成 compact float32 rows，跳过损坏向量并清理 stale rows；inspect/status 能报告已索引书籍、完整准备书籍、已写入 vector row 数和缺失书籍；页面显示升级入口、进度、取消和结果；Vec1 可用且 ANN 表完整时优先返回 ANN winner；Vec1 不可用、ANN 表缺失、native SQL seam 不可用或无结果时 exact backend 接管；shadow layer 不完整时 fallback rows 与 ANN/native rows 合并，避免漏掉未升级书籍；不是已打包的 ANN/Vec1/sqlite-vec 发布完成。 |
| UFA-C07-T09 | In Review slice | Vec1 ANN backend seam | 在不牺牲 fallback 的前提下，把真实 sqlite-vec/Vec1 查询形态接入默认书库向量后端。 | UFA-C07-T05, UFA-C07-T06, UFA-C07-T07, UFA-C07-T08 | `AiVec1VectorIndexBuilder`, `AiVec1VectorSearchBackend`, `AiAnnThenNativeThenExactVectorSearchBackend`, `AiVectorIndexPurger`, `AiIndexDatabase.clearBook`, `AiLibraryIndexPage` `ANN 向量索引`, `ai_native_vector_index_test.dart`, `ai_index_schema_global_layers_test.dart` | Vec1 表名按 provider/model/dim 固定隔离；builder 可从 shadow rows rebuild per-model ANN table 并写 `vec1-ann` meta；status API 报告 extension 可用性、group/row 缺口和是否可构建；设置页可触发前台 ANN 构建并取消；ANN search 只 hydrate winner；Vec1 不存在、ANN 表缺失或 ANN rows 不完整时降级 native/exact；删除书籍会清理该书 native vector rows、Vec1 ANN 行并更新/移除 meta，且不误删同 group 的其它书；仍需平台打包和 provider/model 失效。 |
| UFA-C07-T08 | Accepted | ANN/exact recall overlap gate | 给真实 sqlite-vec/ANN 后端接入前建立可执行召回质量验收。 | UFA-C07-T05, UFA-C07-T06, UFA-C07-T07 | `AiVectorRecallOverlapGate`, `ai_vector_recall_overlap_test.dart` | Gate 会分别调用候选 ANN/native backend 和 exact backend，比对 topK `chunk_id`，输出 candidate/exact/overlap/missing/unexpected chunk id、overlap ratio 和 threshold 结果；固定 fixture 覆盖 4/5 overlap 通过、2/4 overlap 失败，并确认 limit/maxScanRows 转发到 backend；该 gate 不替代真实 ANN adapter、index build job 或平台打包。 |

## 5. Agent 执行约束

每个剩余任务必须使用 `02_agent_execution_model_zh.md` 的 Agent Task 模板，并附加这些约束：

- 阅读场景优先 current book；只有用户显式跨书或 evidence 不足时才查 library。
- 外发正文给 provider 必须经过现有 AI 功能开关或显式用户动作。
- 写入用户资产必须经过 Review 或用户确认。
- ConceptGraph 是派生层；用户确认过的关系才是用户资产。
- UI 入口要能在移动端触达，不把核心阅读内容遮住。
- 长任务必须有取消、失败提示、重启恢复或可重试路径。

## 6. Rescue Review 要点

执行完成前，reviewer/rescue agent 必须逐项检查：

- 入口是否真实可触发，而不是只写了文档。
- 生成的 KnowledgeCard、Seminar synthesis、ConceptNode、ConceptEdge 是否都有 SourceRef。
- Review Inbox 是否能解释每个待审项的来源和状态。
- 任何自动化输出是否越过 Review 写入了长期资产。
- 文档是否把未接入口的能力标成已可用。
- 测试是否覆盖重复点击、空输入、source 不可跳、provider 失败和取消路径。

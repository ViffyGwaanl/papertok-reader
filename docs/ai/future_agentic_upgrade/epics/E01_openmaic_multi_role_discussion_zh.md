# E01 OpenMAIC-Style Multi-Role Discussion

> 状态：In Review
> 目标：把现有 prompt-only `seminar_mode` 升级为 PaperTok Reader 原生 AI Seminar。

## 1. 融合方式

借鉴 OpenMAIC 的多角色课堂、Director-Agent 分离、Shared Whiteboard 和 action protocol，但实现必须贴合 PaperTok Reader：

- 主场是阅读页和 AI 面板。
- 证据来自 current book、library RAG、notes、memory 和 ConceptGraph。
- 默认不开 web。
- 写入知识资产前必须进入 Review 或用户显式确认。
- 不复制 OpenMAIC 代码。

OpenMAIC 当前实现可借鉴的工程结构：

- `lib/chat/agent-loop.ts`：客户端/前端循环维护 `DirectorState`，每次请求只让 Director 选择一个下一位 agent，收到 `END`、`USER` cue 或异常空轮后停止。
- `lib/orchestration/director-graph.ts`：服务端 LangGraph 图是 `START -> director -> agent_generate -> END` 的单轮拓扑；多轮讨论由客户端串行多次请求驱动，而不是服务端长循环。
- `app/api/chat/route.ts`：Chat endpoint 以 SSE 输出 `agent_start / text_delta / action / cue_user / done / error`，并用 request abort 和 heartbeat 管理流式生命周期；PaperTok 应采用 run-scoped stream event，而不是把整场 Seminar 包成一次不可中断调用。
- `lib/orchestration/stateless-generate.ts`：角色输出采用结构化 JSON array，把 `text` 与 `action` 交错流式解析；PaperTok 不需要复制白板动作系统，但应借鉴“结构化 message part + 增量解析 + fallback text finalize”的 robustness。
- `lib/prompts/templates/director/system.md`：Director prompt 显式要求不要重复已发言 agent、优先回答真人学生问题、允许输出 `USER` 让用户参与。
- `components/chat/use-chat-sessions.ts` 与 `lib/buffer/stream-buffer.ts`：Chat 侧把 SSE 事件写入 UI buffer，等本轮显示和 action 执行完成后再让 agent loop 进入下一轮；buffer 支持 pause/resume、逐字显示、action 延迟执行和 `cue_user`。这比一次性跑完整场更适合移动端暂停、取消和恢复。
- `lib/orchestration/registry/store.ts`：agent 由 `name / role / persona / allowedActions / priority / voice` 等字段配置；PaperTok 只能借鉴这个“可治理 profile”结构，不能复制 AGPL 代码或默认人格内容。
- `lib/orchestration/tool-schemas.ts`、`summarizers/whiteboard-ledger.ts` 与 `summarizers/whiteboard-conflicts.ts`：agent 输出 text/action 交错事件，whiteboard/action 由客户端执行并写 ledger，下一轮 prompt 能看到白板摘要和布局冲突；PaperTok 应把它降级为移动端轻量 evidence/disagreement/whiteboard ledger，不引入完整课堂白板。

OpenMAIC 的关键启发已经整理到 `../05_openmaic_discussion_reference_zh.md`。后续实现必须按该文档的许可边界执行：只借鉴 single-round director graph、client-driven loop、USER cue、action whitelist 和 ledger 思路，不复制 AGPL 代码、prompt 模板或 UI。

## 2. 默认角色

| 角色 | 责任 | 默认工具范围 |
| --- | --- | --- |
| `critical` | 找逻辑漏洞、反例、概念混淆。 | current book search、notes search、verify 类只读工具。 |
| `supportive` | 解释文本、补例子、建立直觉。 | current chapter、current book RAG、TOC。 |
| `synthesizer` | 汇总共识、分歧、下一步阅读和候选卡片。 | evidence bundle、Shared Whiteboard。 |
| `verifier` | 可选角色，用于跨书或高风险答案核证。 | library RAG，默认仍不开 web。 |

实现 agent 不得自由新增角色。新增角色必须先修改本 Epic 的角色表并通过 rescue gate。

## 3. Capability

### E01-C01 Reading Director

负责解析用户意图、选择资料范围、规划讨论轮次、分配角色。默认规则：

- 阅读页内优先 current book。
- 只有用户选择跨书或当前书证据不足时才用 library。
- 默认不调用 web。
- 每场讨论先有本地 token budget guardrail；provider token usage 只在 provider/SDK 回传 metadata 时记录和展示；provider capability cache 带 pricing metadata 时可启用估算美元成本预算，但不得声明为真实 provider 发票。

### E01-C02 Evidence Broker

负责把 current chapter、current book RAG、library RAG、notes、memory、ConceptGraph 统一成 evidence bundle。

每个 evidence 必须含 SourceRef。

### E01-C03 Shared Whiteboard

记录：

- `claim`
- `evidenceRefs`
- `disagreement`
- `openQuestion`
- `candidateCard`
- `reviewSuggestion`

Shared Whiteboard 是本场 Seminar 的工作台，不直接写用户资产。

### E01-C04 Synthesis And Review Handoff

Seminar 结束时输出：

- 简短总结。
- 支持观点。
- 质疑观点。
- 分歧和未解问题。
- 候选 KnowledgeCard。
- 候选复习题。
- 回跳原文链接。

### E01-C05 AI Chat 内嵌 Seminar Director Loop

把 Seminar 从独立页面能力推进为 AI Chat 内的原生讨论模式。借鉴 OpenMAIC 的做法，但只吸收结构思想：

- Director 每轮只决定一个下一位角色，runtime 持久化 `turnCount`、已发言摘要、证据 ledger、白板 ledger 和用户插话状态。
- AI Chat composer 是同一输入入口；用户可以在角色之间插话、要求重新找证据、追问某个角色、回答澄清问题，completed run 也必须允许继续讨论。当前首片已把 completed AI Chat Seminar 历史卡接入 run-scoped `读者参与` composer，可在同一张卡里点名角色回应、重新找证据或整理总结。
- 角色配置不再只藏在固定 prompt：当前基础切片已支持 Settings 全局默认和 AI Chat `本次研讨设置`，可配置每个角色的显示名、custom prompt、是否启用、会话证据提示和只读工具范围；剩余部分是发言目标、角色级证据过滤和角色级 token/cost guardrail。
- 讨论不是固定一轮：`evidence -> 角色观点 -> contradiction scan -> evidence refresh -> rebuttal -> synthesis -> inline save or exception handoff`，由 Director 根据 evidence gap、分歧和用户插话决定继续或暂停。
- AI Chat 中渲染为一条可展开的 Seminar run 卡片，包含 `证据 / 分歧 / 白板 / 总结 / 异常` 子视图和 completed 卡片内联保存动作；不强迫用户离开当前对话上下文。
- 普通 synthesis、candidate card 和 flashcard 先在当前 AI Chat 卡片内由用户显式保存、编辑、加入复习、加入我的图谱、忽略或撤销；只有异常、低置信、冲突、来源断裂或旧兼容路径进入 Review。

本 Capability 的产品决策：

- `Choose style / 选择风格` 只保留为普通 AI Chat 的 prompt/skill 风格选择；`AI 研讨会` 是独立的 Chat run action，不通过修改 `activeAiSkillId` 来启动。
- 独立 `AiSeminarRuntimePage` 只作为详情、恢复和兼容入口；主路径应在 AI Chat 页面内完成提问、角色发言、证据刷新、用户插话、总结、内联保存和异常送审。
- Director 不是一次固定模板调用，而是显式状态机：`collectEvidence -> roleTurn -> contradictionScan -> refreshEvidence -> userCheck -> rebuttal -> synthesize -> inlineSaveOrExceptionHandoff`。每次进入 `refreshEvidence` 都必须追加可追踪 SourceRef。
- 用户是讨论参与者，不是 evidence producer。用户可以要求某个角色反驳、要求重新找证据、回答 Director 澄清问题；这些输入只进入 user-turn ledger，不能冒充书内证据。
- 角色提示词设置必须在 Settings 和 Chat run 内都可达；Chat run 内改动只影响当前 run，Settings 改动影响新 run 默认值。
- `seminar_mode` 只是普通 AI Chat 多视角 prompt 风格，不等同于 `AiSeminarRuntime`；产品文案、入口和历史卡必须持续区分两者，避免用户误以为切换风格就启动多角色 runtime。
- AI Chat 是 durable transcript owner；Seminar runtime panel 是某个 run 的操作视图。当前第一片已让 AI Chat inline runtime、历史任务卡 snapshot、卡内异常送审和卡内 `读者参与` composer 按 `seminarSessionId` 使用 scoped runtime；阅读页/外部入口也会写入同 session 任务卡，避免进程死亡后只剩临时 panel 状态而用户找不到恢复入口。继续推进时，独立详情页也必须读取同一 run store，避免不同 tab、不同历史卡或 Settings 详情页串场。
- AI Chat 的 thinking、tool call、skill/plugin UI 已经是用户熟悉的 AI 工作台；Seminar 应复用同一个 composer、stream、tool/cost/status surface，并以结构化 run card 呈现多角色讨论，不再把“研讨会模式”做成另一套主要交互。
- 角色当前是固定 role contract + role prompt + evidence gate 的顺序执行，不是任意递归 sub-agent 群聊；后续如接入 `spawn_sub_agent` 或 agent tool 平台，也必须保持禁止递归、只读检索默认串行、写入用户资产前需要当前卡片内显式确认，异常写入走 Review 审批。

## 4. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E01-C01-T01 | 定义 Seminar session contract | E00-C01-T02 | session/role/round schema | 能表达 3 个默认角色和 verifier。 |
| E01-C01-T02 | 接入 Seminar session runtime model | E01-C01-T01 | `lib/models/ai_seminar.dart` | 默认角色固定，verifier 受 contract 控制，unknown role 不进入执行。 |
| E01-C02-T01 | 定义 evidence bundle contract | E00-C01-T02, E02 Ready | evidence schema | 每条 evidence 有 SourceRef。 |
| E01-C02-T02 | 接入 current-book-first evidence broker | E01-C02-T01 | `AiSeminarEvidenceBroker` | 阅读场景优先 current book，证据不足或显式跨书才 fallback library。 |
| E01-C03-T01 | 设计 Shared Whiteboard | E01-C02-T01 | whiteboard schema | claim/disagreement/candidateCard 可追溯 evidence。 |
| E01-C03-T02 | 接入 role turn 和 whiteboard validation | E01-C03-T01 | `AiSeminarOrchestrationService` | role 输出必须匹配 roleId 且引用可追踪 evidence，不合格 turn 不污染后续上下文。 |
| E01-C04-T01 | 定义 synthesis 输出 | E01-C03-T01 | synthesis schema | 可转 Review，不直接落盘。 |
| E01-C04-T02 | 接入结构化 UI 入口 | E01-C04-T01, E07 Ready | `AiSeminarRuntimePage`、Settings AI entry、reader selection entry | 阅读页 2 步内可开 Seminar，并可看到 evidence、role turns、Shared Whiteboard、synthesis。 |
| E01-C04-T03 | 接入 synthesis Review handoff | E01-C04-T01, E05-C01-T01 | `SeminarSynthesisReviewAdapter`、`AiSeminarRuntimeNotifier.sendToReview` | readyForReview 且 traceable handoff 才能进入 pending Review；候选卡保持 draft/pending。 |
| E01-C04-T04 | 接入 Seminar provider readiness | E06-C04-T01, E07 Ready | `AiSeminarProviderContextService`、`AiSeminarRuntimeState.providerDiagnostics`、`AiSeminarRuntimePage` readiness UI | 启动前显示当前 provider/model/capability cache 和成本未知原因；缺少 pricing/usage metadata 时不伪造成本估算。 |
| E01-C04-T05 | 接入 Seminar local token usage | E01-C04-T02, E01-C04-T04 | `AiSeminarTokenUsage`、`AiSeminarRuntimeService` local estimator、`AiSeminarRuntimePage` usage UI | 每个完成角色 turn 记录 input/output 本地估算，run 聚合 usage，页面显示 `Provider billing may differ`；不得当作 provider 账单或美元成本。 |
| E01-C04-T06 | 接入 Seminar local recovery | E01-C04-T02, E07 Ready | `aiSeminarRuntimeStateV1`, `aiSeminarRuntimeStateV1:<seminarSessionId>`, `AiSeminarRuntimeNotifier` restore, `AiSeminarRuntimePage` recovered banner | completed/cancelled/failed state 可在同一书籍/同一入口问题本机恢复；AI Chat embedded run 使用 scoped cache，legacy Settings 入口使用 global cache；阅读页/外部入口会用同一 `seminarSessionId` 写入 AI Chat 任务卡，作为进程死亡后的 transcript 恢复锚点；历史任务卡在同 session scoped cache 可续跑时显示 `可从中断处继续`、`继续研讨` 和 `打开恢复`，`继续研讨` 直接调用 scoped runtime 续跑缺失角色，`打开恢复` 只打开内嵌面板查看详情；换书、换选区或换 `seminarSessionId` 清除旧 runtime/cache；有可追踪 evidence 且 provider/model/pricing 匹配当前配置的 running state 重启后可复用已保存 evidence，从第一个缺失角色继续；已有连续 completed role prefix 会跳过不重跑；只有 active partial stream 时丢弃半截文本并重发缺失角色；checkpoint 无效、evidence 不可追踪、provider 已切换或 queued job 仍降级为 interrupted/retryable；global 与 scoped 恢复缓存都不进普通 prefs backup。 |
| E01-C04-T07 | 接入 Seminar local token budget | E01-C04-T05, E07 Ready | `AiSeminarBudgetPolicy`, `AiSeminarRuntimeService` budget gate, `AiSeminarRuntimePage` budget UI | 用户可设置 role output/run token budget；超出本地估算时停止后续步骤、保留失败原因并可重试；不得当作 provider 账单或美元成本上限。 |
| E01-C04-T08 | 接入 Seminar provider token usage | E01-C04-T05, E01-C04-T07 | `CancelableLangchainRunner.stream` usage tracker、`AiSeminarModelRoleExecutor` usage delta、`AiSeminarRuntimePage` provider usage UI | provider/SDK 返回 usage metadata 时，role turn 和 run 保存 `provider-reported` token usage；无 usage metadata 时降级本地估算；local budget gate 仍只使用本地估算，不把 provider usage 当作实时账单或美元成本。 |
| E01-C04-T09 | 接入 Seminar estimated USD cost cap | E01-C04-T04, E01-C04-T08 | `AiModelCapability` pricing metadata、`AiSeminarBudgetPolicy.maxRunCostUsd`、`AiSeminarRuntimeService` cost gate、`AiSeminarRuntimePage` cost cap UI | provider capability cache 带 pricing metadata 时，用户可设置估算 `Run cost cap USD`；runtime 聚合 provider/local usage 估算美元成本，超出 cap 时停止后续步骤并可重试；无 pricing metadata 时禁用美元 cap；不得声明为真实 provider invoice。 |
| E01-C05-T01 | 定义 Chat Seminar DirectorState | E01-C03-T02, UFA-C02-T15 | `AiSeminarDirectorState` / migration | 第一片已接入模型和 runtime state JSON：可记录轮次、已完成角色、已完成 turn id、证据账本、白板账本、分歧 id、证据刷新次数、用户插话和下一步 intent；用户插话不算 formal evidence；恢复时不得重放已完成角色。后续必须让 Director loop 真正消费该状态。 |
| E01-C05-T02 | 增加角色 prompt 设置 | E01-C01-T02, E06 skill governance | Seminar role profile store + Settings/AI Chat 配置入口 | Settings 全局默认基础切片已支持默认角色显示名、custom prompt、启用状态、会话证据提示和只读工具范围；AI Chat Add-to-Chat sheet 的 `AI 研讨会` 调参按钮已接入 `本次研讨设置`，可为下一张任务卡临时设置角色 prompt、启用状态、核验者和 `maxRounds`，不写回全局 Settings；设置会写入 session contract 并注入 role prompt；disabled role 会从新 session 和 AI Chat Seminar 任务卡 role ids 中移除，全部关闭时降级为 synthesizer；secret-like prompt 会被丢弃，写工具、联网工具、递归 sub-agent 和 unknown tool 会被过滤。当前可见证据提示只开放 current book/library，并合并到整场 Seminar evidence bundle，不是每个角色独立过滤证据。剩余是空 prompt 显式提示、角色级证据过滤和角色级预算；当前工具范围是 contract/prompt 治理第一片，不等于角色已拥有自由工具调用 loop。 |
| E01-C05-T03 | 接入多轮分歧与证据刷新 | E01-C02-T02, E01-C05-T01 | Director loop service | 已完成第一片：用户触发和 disagreement 预算内自动触发都会重新检索 evidence、重跑角色并保留 SourceRef；刷新后仍有分歧且预算耗尽时转为 `askUser`。后续继续补结构化 contradiction gap scan、角色 rebuttal turn 和完整结构化 Chat run card。 |
| E01-C05-T04 | 接入用户插话/澄清回合 | E01-C05-T01, E07 Chat UI | Chat Seminar user-turn model | 第一片已支持 Director 暂停为 `needsUserInput`，以及 completed run 在 synthesis 后显示 `Continue discussion / 继续讨论`；用户可指定追问某角色、要求重新找证据、整理总结或回答澄清；用户输入只写 `lastUserIntervention`，不被当作 AI 证据。完整 Chat message part composer routing 仍归 E01-C05-T08/T14。 |
| E01-C05-T05 | 在 AI Chat 渲染 Seminar run 卡片 | E01-C05-T01, E07 Chat UI | `AiSeminarRuntimePanel` first slice; AI Chat message part / run card widgets | 已完成第九片：AI Chat `+` -> `AI 研讨会` 会在当前 AI Chat 页面内展开 runtime panel，不改 active skill，并向 `conversationV2` 写入 `seminarRunCard` meta 和兼容 fallback assistant message；阅读页/外部 `研讨` 入口现在也会向 `conversationV2` 写入同一 `seminarSessionId` 的任务卡，确保用户可从 AI Chat 历史恢复这场讨论；历史重载后这张 `AI 研讨会` 卡片可点击重新打开同一类 inline runtime；如果本机 scoped running checkpoint 可续跑，历史卡会直接显示 `可从中断处继续`、`继续研讨` 和 `打开恢复`，`继续研讨` 会在 AI Chat 卡片内复用保存 evidence 并从缺失角色续跑，`打开恢复` 只打开内嵌面板。内嵌 runtime 运行、完成或刷新证据时，会按同一个 `seminarSessionId` 回写卡片 `status/sourceRefCount/snapshot`，历史卡可直接显示证据快照、角色观点、研讨总结、分歧数、开放问题数和 `研讨白板` 正文；历史卡已有 `全部 / 证据 / 角色 / 分歧 / 白板 / 总结 / 异常` 子视图，`分歧` 子视图可显示分歧正文、关联角色和关联 evidence 摘录，`异常` 子视图可显示异常处理预览、待送审内容计数、候选明细、知识卡候选证据摘录和复习候选综合证据。AI Chat inline panel、历史任务卡状态读取、卡内 `异常送审`、completed 卡片内低负担保存动作和 `读者参与` composer 已按 `seminarSessionId` 使用 scoped runtime，避免同一 AI Chat 内不同 Seminar 卡互相覆盖。用户现在可在历史卡里输入读者回合，选择让所选角色回应、重新找证据或整理总结；用户输入只写 user-turn ledger，不进入 formal evidence。剩余仍需升级完整异常送审详情表、完整 message part 信息架构、独立详情页 scoped store 和完整 contradiction/rebuttal loop，且不跳转独立 Seminar 页面也能走完整讨论。 |
| E01-C05-T06 | 迁移独立 Seminar 入口为可选详情页 | E01-C05-T05 | entry routing + compatibility tests | 已完成第一片：阅读页 `研讨` 和 AI Chat `AI 研讨会` 都进入 Chat 内嵌 runtime panel，且阅读页入口保留 reader SourceRef、不改 active skill；后续保留独立页面作为详情/恢复入口时必须共享同一 run-scoped runtime state。 |
| E01-C05-T07 | 定义 Chat Seminar director action contract | E01-C05-T01 | `SeminarDirectorAction` enum + reducer tests | Director 每轮只能输出 `runRole / refreshEvidence / askUser / synthesize / stop` 之一；非法 action、重复已完成角色、无证据 synthesis 都被拒绝。 |
| E01-C05-T08 | 接入 Chat composer 用户回合 | E01-C05-T04, E01-C05-T05 | Chat run input router | 当前 runtime panel 已支持 `askUser` 和 completed continuation composer 的读者回合；AI Chat 历史卡也已接入首片 run-scoped `读者参与` composer，可选择问某角色、重找证据或整理总结，输入写入 user-turn ledger，不触发普通 AI Chat 单轮回答。剩余是把同一 composer 抽成完整 message part 子视图，并覆盖更多 Director cue 状态。 |
| E01-C05-T09 | 接入 Chat 内角色配置入口 | E01-C05-T02, E06 skill governance | run-scoped role config sheet | 第一片已完成：AI Chat Add-to-Chat sheet 的 `AI 研讨会` 调参按钮打开 `本次研讨设置`，可编辑当前问题、最多讨论轮次、是否加入 verifier，以及每个角色的启用状态、显示名和 prompt；提交后配置只写入当前 `seminarRunCard` / `AiSeminarSessionContract`，不写回全局 Settings；历史卡重开 inline runtime 时会沿用卡片保存的 role profiles 和 maxRounds。剩余是空 prompt 显式提示、角色级证据过滤、角色级预算和更完整的 run-scoped composer 子视图。 |
| E01-C05-T10 | 接入分歧面板和证据刷新按钮 | E01-C05-T03, E01-C05-T05 | disagreement view + evidence refresh event | 已完成首片 AI Chat 卡片级入口：completed 历史卡已有 disagreement 且仍匹配当前 scoped runtime 时，显示 `分歧继续讨论`，用户可围绕第一条分歧直接点 `围绕分歧重找证据`；动作会保存 human intervention、重新检索只读 evidence、重跑角色并更新 synthesis，用户文本不进入 formal evidence。已完成卡内 snapshot `分歧` 子视图首片：用户可在 `全部 / 证据 / 角色 / 分歧 / 白板 / 总结` 中切到分歧聚焦视图。剩余是每个 contradiction 绑定两个以上 role turn/evidence ids 的结构化详情，以及 Director 基于完整 contradiction gap scan 决定反驳或总结。 |
| E01-C05-T11 | 升级 AI Chat Seminar run card 为完整 message part | E01-C05-T05, E01-C05-T08 | `seminarRun` message part schema + widgets + history migration | 已完成 evidence/role/synthesis snapshot、白板正文首片、首片异常 Review handoff、scoped runtime 读取、run-scoped 读者回合 composer、分歧快捷继续讨论入口、completed 卡内低负担保存动作、snapshot 子视图首片、异常送审内容计数、候选明细、知识卡候选证据摘录和复习候选综合证据、可续跑 checkpoint 状态条：历史重载后仍显示证据快照、角色观点、研讨总结、分歧数、开放问题数、`研讨白板` 中的分歧和开放问题正文；用户可在卡内切换 `全部 / 证据 / 角色 / 分歧 / 白板 / 总结 / 异常`；同 session scoped runtime 已完成且需要异常处理时，卡片显示 `异常送审` 并写 pending Review；同 session scoped runtime 恢复为可续跑 running checkpoint 时，卡片显示 `可从中断处继续`，可点 `继续研讨` 直接续跑缺失角色，也可点 `打开恢复` 打开恢复详情；completed 卡片显示 `读者参与`，可点名角色回应、重新找证据或整理总结；有分歧时可默认让 critical 围绕第一条分歧追加 follow-up turn，critical 未启用时退回当前可用角色，或围绕该分歧重找 evidence；Seminar 卡片不暴露普通 assistant 回答的 KnowledgeCard/Memory/regenerate 操作，避免伪造来源。剩余部分是完整异常送审详情表、完整 contradiction 详情 tab 和完整 message part schema migration。 |
| E01-C05-T12 | 增加 role profile governance v2 | E01-C05-T09, E06 governance | role enabled/scope/tools/budget schema + validator + UI | Settings 全局默认和 AI Chat `本次研讨设置` 第一片已完成：`AiSeminarRoleProfile` 支持 `enabled/evidenceScopes/allowedToolIds`，enabled profile 的 evidence scopes 会作为会话证据提示合并到 session scopes，当前可见 UI 只开放 current book/library；disabled role 会被跳过，只读工具白名单会过滤写工具、web、unknown 和 `spawn_sub_agent`，role prompt 会显示会话证据提示和允许工具；单次 run 也能保存 role prompt、启用状态、verifier 和 `maxRounds` 到任务卡。剩余是角色级证据过滤、角色级预算 UI、空 prompt 显式错误提示和完整工具执行闭环；当前不允许递归 sub-agent 或写工具。 |
| E01-C05-T13 | 接入 contradiction gap scan 和 rebuttal turn | E01-C05-T03, E01-C05-T10 | contradiction scanner + target rebuttal runner | 已完成首片 targeted rebuttal action：AI Chat completed 历史卡可从第一条 disagreement 直接触发默认 `让批判者反驳`，写入 run-scoped user intervention，并调用 active session 中的 critical 角色生成 follow-up turn；disabled critical 时降级到当前可用角色回应。剩余是结构化 contradiction scanner、分歧与两个以上 role turn/evidence ids 的绑定、Director 自动选择 targeted refresh/rebuttal、刷新预算耗尽后进入用户确认且不无限循环。 |
| E01-C05-T14 | 把用户插话接入 Chat run composer | E01-C05-T08, E07 Chat UI | run-scoped composer routing | 首片已完成：completed AI Chat Seminar 历史卡显示 `读者参与`，用户可在同一张 run card 中输入回复，选择让所选角色回应、重新找证据或整理总结；有分歧时还可不用手动复制文本，直接点默认 `让批判者反驳`，critical 未启用时退回当前可用角色，或点 `围绕分歧重找证据`；`分歧` 子视图已能展示每条分歧的关联角色和关联 evidence 摘录，`异常` 子视图已能展示待送审内容计数、候选明细、知识卡候选证据摘录和复习候选综合证据；实现复用 `recordUserIntervention` + `executeDirectorNextStep` 和同一个 `seminarSessionId` scoped runtime；用户输入只写 user-turn ledger，不进入 formal evidence。剩余是把 composer 扩展到 running/askUser cue 的完整 message part、完整异常送审详情表和独立详情页同源状态。 |
| E01-C05-T15 | 实现 per-run runtime state 隔离 | E01-C05-T11, E07 state recovery | run id keyed runtime store + detail page route | 第一片已完成：`aiSeminarRuntimeScopedProvider` 按 `seminarSessionId` 隔离 AI Chat inline panel、可见历史任务卡 snapshot、卡内异常送审、completed 卡内读者参与 composer 和本机恢复缓存；外部/阅读页入口未传 session id 时由 AI Chat 生成 `seminar-chat-*`，并写入同 session 的 AI Chat 任务卡，避免进程死亡后 scoped checkpoint 没有用户可见锚点；scoped cache 使用 `aiSeminarRuntimeStateV1:<seminarSessionId>`，普通 prefs backup 会跳过这些缓存；不同 scoped runtime 的模型调用通过本机 coordinator 串行化，不并发外发 Seminar。剩余是独立详情页读取同一 scoped store。 |
| E01-C05-T16 | 区分 `seminar_mode` 与 `AiSeminarRuntime` | E01-C05-T05, E06 skill governance | UI labels + entry copy + migration notes | `seminar_mode` 作为普通多视角回复风格保留降级用途；AI Chat `AI 研讨会`、阅读页 `研讨`、历史卡和 Settings 文案明确指向真正 Seminar runtime；不会把 active skill 切换伪装成多角色 runtime。 |

## 5. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `seminar_mode` skill、`SubAgentRunner`、`spawn_sub_agent`、`ToolOrchestrator`、current book/RAG tools、AnnotationLedger。 |
| Allowed Modules | `lib/service/ai/skills`, `lib/service/ai/sub_agent_runner.dart`, AI tool orchestration, AI chat UI entry points, Seminar runtime/settings, tests/docs. |
| Forbidden Changes | 不复制 OpenMAIC 代码；不新增无权限写工具；不绕过用户显式确认写 notes/memory/cards；不把普通低负担保存伪装成已确认长期资产；异常、冲突、低置信或来源断裂仍必须走 Review handoff；不默认 web。 |
| Verification Commands | Focused agent/tool tests for role whitelist, no recursion, timeout/cancel, evidence refs, runtime UI, Review handoff; `git diff --check`。 |
| Reviewer Gate | Mobile Resource Gate + Agent Safety And Privacy Gate + Retrieval Quality Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | Seminar orchestrator 可关闭并降级回 prompt-only `seminar_mode`。 |

## 6. Gates

- Mobile Resource Gate：默认串行 role execution；只读检索可并行。
- Agent Safety And Privacy Gate：普通笔记、Memory、Card、复习和图谱沉淀必须有当前页或 AI Chat 卡片内显式确认、可撤销边界和 SourceRef；异常、冲突、低置信或来源断裂必须走 Review 审批。
- Retrieval Quality Gate：Seminar 结论必须显示 evidence 状态。
- Review And Rescue Gate：确认没有把角色设定写成无约束人格 prompt。
- AI Chat Integration Gate：同一讨论在 Chat 内嵌 run、独立详情页和本机恢复缓存中必须共享同一 SourceRef、turn ledger、budget 和 Review handoff，不得产生两个互相冲突的 Seminar 状态源。

## 7. Non-Goals

- 不做完整在线课堂。
- 不做多人协作。
- 不做 OpenMAIC 代码移植。
- 不把 Seminar 输出自动写入长期记忆。

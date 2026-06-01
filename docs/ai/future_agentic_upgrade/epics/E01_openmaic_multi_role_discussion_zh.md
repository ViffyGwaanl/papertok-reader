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
- AI Chat composer 是同一输入入口；用户可以在角色之间插话、要求重新找证据、追问某个角色、回答澄清问题。
- 角色配置不再只藏在固定 prompt：每个角色有可编辑显示名、system prompt、发言目标、证据策略、工具白名单、是否启用和 token/cost guardrail。
- 讨论不是固定一轮：`evidence -> 角色观点 -> contradiction scan -> evidence refresh -> rebuttal -> synthesis -> Review handoff`，由 Director 根据 evidence gap、分歧和用户插话决定继续或暂停。
- AI Chat 中渲染为一条可展开的 Seminar run 卡片，包含 `证据 / 分歧 / 白板 / 总结 / 送审` 子视图；不强迫用户离开当前对话上下文。
- 任何 synthesis、candidate card、flashcard 仍只进入 Review，不直接写长期资产。

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
| E01-C04-T06 | 接入 Seminar local recovery | E01-C04-T02, E07 Ready | `aiSeminarRuntimeStateV1`, `AiSeminarRuntimeNotifier` restore, `AiSeminarRuntimePage` recovered banner | completed/cancelled/failed state 可在同一书籍/同一入口问题本机恢复；换书或换选区清除旧 runtime/cache；有连续、可追踪且 provider/model/pricing 匹配当前配置的 completed role turn 的 running state 重启后可复用已保存 evidence，从下一个缺失角色继续；无 completed turn、只有 active partial stream、checkpoint 无效、provider 已切换或 queued job 仍降级为 interrupted/retryable；恢复缓存不进普通 prefs backup。 |
| E01-C04-T07 | 接入 Seminar local token budget | E01-C04-T05, E07 Ready | `AiSeminarBudgetPolicy`, `AiSeminarRuntimeService` budget gate, `AiSeminarRuntimePage` budget UI | 用户可设置 role output/run token budget；超出本地估算时停止后续步骤、保留失败原因并可重试；不得当作 provider 账单或美元成本上限。 |
| E01-C04-T08 | 接入 Seminar provider token usage | E01-C04-T05, E01-C04-T07 | `CancelableLangchainRunner.stream` usage tracker、`AiSeminarModelRoleExecutor` usage delta、`AiSeminarRuntimePage` provider usage UI | provider/SDK 返回 usage metadata 时，role turn 和 run 保存 `provider-reported` token usage；无 usage metadata 时降级本地估算；local budget gate 仍只使用本地估算，不把 provider usage 当作实时账单或美元成本。 |
| E01-C04-T09 | 接入 Seminar estimated USD cost cap | E01-C04-T04, E01-C04-T08 | `AiModelCapability` pricing metadata、`AiSeminarBudgetPolicy.maxRunCostUsd`、`AiSeminarRuntimeService` cost gate、`AiSeminarRuntimePage` cost cap UI | provider capability cache 带 pricing metadata 时，用户可设置估算 `Run cost cap USD`；runtime 聚合 provider/local usage 估算美元成本，超出 cap 时停止后续步骤并可重试；无 pricing metadata 时禁用美元 cap；不得声明为真实 provider invoice。 |
| E01-C05-T01 | 定义 Chat Seminar DirectorState | E01-C03-T02, UFA-C02-T15 | `AiSeminarDirectorState` / migration | 能记录轮次、已发言角色、分歧、证据刷新次数、用户插话和下一步 intent；恢复时不得重放已完成角色。 |
| E01-C05-T02 | 增加角色 prompt 设置 | E01-C01-T02, E06 skill governance | Seminar role profile store + Settings/AI Chat 配置入口 | 用户可编辑默认角色 prompt、名称、启用状态、证据策略和工具范围；无效 prompt 或越权工具不进入 runtime。 |
| E01-C05-T03 | 接入多轮分歧与证据刷新 | E01-C02-T02, E01-C05-T01 | Director loop service | 至少支持初始证据、第一轮观点、contradiction scan、按 gap 重新检索、反驳轮和 synthesis；每次刷新证据都有 SourceRef。 |
| E01-C05-T04 | 接入用户插话/澄清回合 | E01-C05-T01, E07 Chat UI | Chat Seminar user-turn model | Director 可暂停为 `needsUserInput`；用户可指定追问某角色、要求重新找证据或回答澄清；用户输入不被当作 AI 证据。 |
| E01-C05-T05 | 在 AI Chat 渲染 Seminar run 卡片 | E01-C05-T01, E07 Chat UI | AI Chat message part / run card widgets | 同一 AI Chat 页面展示证据、角色发言、分歧、白板、总结和送审；不跳转独立 Seminar 页面也能走完讨论。 |
| E01-C05-T06 | 迁移独立 Seminar 入口为可选详情页 | E01-C05-T05 | entry routing + compatibility tests | 阅读页 `研讨` 和 AI Chat `AI 研讨会` 默认进入 Chat 内嵌 run；保留独立页面作为详情/恢复入口时必须共享同一 runtime state。 |

## 5. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `seminar_mode` skill、`SubAgentRunner`、`spawn_sub_agent`、`ToolOrchestrator`、current book/RAG tools、AnnotationLedger。 |
| Allowed Modules | `lib/service/ai/skills`, `lib/service/ai/sub_agent_runner.dart`, AI tool orchestration, AI chat UI entry points, Seminar runtime/settings, tests/docs. |
| Forbidden Changes | 不复制 OpenMAIC 代码；不新增无权限写工具；不绕过 Review 写 notes/memory/cards；不默认 web。 |
| Verification Commands | Focused agent/tool tests for role whitelist, no recursion, timeout/cancel, evidence refs, runtime UI, Review handoff; `git diff --check`。 |
| Reviewer Gate | Mobile Resource Gate + Agent Safety And Privacy Gate + Retrieval Quality Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | Seminar orchestrator 可关闭并降级回 prompt-only `seminar_mode`。 |

## 6. Gates

- Mobile Resource Gate：默认串行 role execution；只读检索可并行。
- Agent Safety And Privacy Gate：写入笔记、Memory、Card 前必须审批。
- Retrieval Quality Gate：Seminar 结论必须显示 evidence 状态。
- Review And Rescue Gate：确认没有把角色设定写成无约束人格 prompt。
- AI Chat Integration Gate：同一讨论在 Chat 内嵌 run、独立详情页和本机恢复缓存中必须共享同一 SourceRef、turn ledger、budget 和 Review handoff，不得产生两个互相冲突的 Seminar 状态源。

## 7. Non-Goals

- 不做完整在线课堂。
- 不做多人协作。
- 不做 OpenMAIC 代码移植。
- 不把 Seminar 输出自动写入长期记忆。

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
- 每场讨论有 token/成本预算。

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

## 5. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `seminar_mode` skill、`SubAgentRunner`、`spawn_sub_agent`、`ToolOrchestrator`、current book/RAG tools、AnnotationLedger。 |
| Allowed Modules | `lib/service/ai/skills`, `lib/service/ai/sub_agent_runner.dart`, AI tool orchestration, AI chat UI entry points, tests/docs. |
| Forbidden Changes | 不复制 OpenMAIC 代码；不新增无权限写工具；不绕过 Review 写 notes/memory/cards；不默认 web。 |
| Verification Commands | Focused agent/tool tests for role whitelist, no recursion, timeout/cancel, evidence refs, runtime UI, Review handoff; `git diff --check`。 |
| Reviewer Gate | Mobile Resource Gate + Agent Safety And Privacy Gate + Retrieval Quality Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | Seminar orchestrator 可关闭并降级回 prompt-only `seminar_mode`。 |

## 6. Gates

- Mobile Resource Gate：默认串行 role execution；只读检索可并行。
- Agent Safety And Privacy Gate：写入笔记、Memory、Card 前必须审批。
- Retrieval Quality Gate：Seminar 结论必须显示 evidence 状态。
- Review And Rescue Gate：确认没有把角色设定写成无约束人格 prompt。

## 7. Non-Goals

- 不做完整在线课堂。
- 不做多人协作。
- 不做 OpenMAIC 代码移植。
- 不把 Seminar 输出自动写入长期记忆。

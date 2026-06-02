# OpenMAIC Discussion Implementation Reference

> 状态：Ready
> 用途：记录 OpenMAIC 多角色讨论的实现结构，以及 PaperTok Reader 可以借鉴但不能直接复制的部分。

## 1. 结论

OpenMAIC 的“研讨会”不是服务端一次性跑完多 agent 长循环。它更像一个可暂停的对话调度器：

- 前端维护 `DirectorState`，持续串联多次 `/api/chat` 请求。
- 服务端每次请求只执行一次 `director -> agent_generate`。
- Director 每轮只决定下一步是某个 agent、`USER` 还是 `END`。
- agent 输出不是普通自由文本，而是结构化 text/action 流。
- 白板、动作、角色摘要和用户状态会回到下一轮 prompt。

对 PaperTok Reader 最有价值的是这个“短步调度 + 状态账本 + 用户可插话 + action 白名单”的结构，而不是 OpenMAIC 的课堂 UI、白板动作代码或提示词原文。

OpenMAIC 的 discussion loop 更强在角色调度和互动呈现；它并没有把每轮讨论都做成自动 RAG/evidence refresh。PaperTok 的差异化目标应更进一步：Director 发现角色分歧、证据不足、用户追问原文或准备送 Review 前，必须优先 current book 重找证据，再按用户许可扩展到 library 或 web。

## 2. OpenMAIC 实现锚点

基于 `THU-MAIC/OpenMAIC` 当前源码核对：

| 模块 | OpenMAIC 做法 | PaperTok 可借鉴点 |
| --- | --- | --- |
| `lib/chat/agent-loop.ts` | 客户端 `runAgentLoop()` 持有 `directorState`，每轮刷新 messages/storeState，再调用 `/api/chat`。遇到 abort、`cue_user`、`END` 或连续空轮停止。 | AI Chat 内嵌 Seminar 应该由 run-scoped state 串联短任务，不把整场讨论压成一次不可中断请求。 |
| `lib/orchestration/director-graph.ts` | LangGraph 拓扑是 `START -> director -> agent_generate -> END`，源码注释明确 single-round contract。 | PaperTok Director 每轮只输出一个明确动作：跑角色、重找证据、问用户、总结或停止。 |
| `app/api/chat/route.ts` | `/api/chat` 接收完整 request state，用 SSE 输出 `agent_start / text_delta / action / cue_user / done / error`，并用 request abort 与 heartbeat 管理流生命周期。 | PaperTok 的 AI Chat Seminar 应把 role turn、证据刷新和用户 cue 都做成可取消的 run event，不把长任务塞进不可观察的 Future。 |
| `lib/orchestration/director-prompt.ts` | Director prompt 注入可用 agent、已发言摘要、讨论主题、白板 ledger、用户 profile，再解析 JSON decision。 | PaperTok 的 DirectorState 应注入 evidence ledger、role turn summary、disagreement、user intervention 和 budget，而不是只拼一段长 prompt。 |
| `lib/prompts/templates/director/system.md` | Director 必须输出 `{"next_agent":"<agent_id>"}`、`{"next_agent":"USER"}` 或 `{"next_agent":"END"}`；规则强调不要重复、要推进讨论、未解决问题可 cue user。 | PaperTok 需要把“用户参与”做成正式状态，不把用户插话混进 evidence。 |
| `lib/orchestration/prompt-builder.ts` | agent prompt 按 role/persona/allowedActions/scene/whiteboard/context 构造，并按场景过滤 action。 | PaperTok 角色配置应拆成显示名、custom prompt、启用状态、证据策略、工具白名单和 token/cost guardrail。 |
| `lib/types/action.ts` | `discussion` 是 action 类型之一，agent 可以触发结构化讨论；其它 action 由前端执行并进 ledger。 | PaperTok 不需要复制课堂白板 action；应映射为 `openSourceRef`、`refreshEvidence`、`createKnowledgeCardDraft`、`sendToReview`、`askUser` 等阅读动作。 |
| `components/chat/use-chat-sessions.ts` 与 `lib/buffer/stream-buffer.ts` | Chat 侧接收 SSE 后进入 UI buffer，等待文本显示和 action 执行完成再进入下一轮。 | 移动端需要这种 pacing：role 发言、证据刷新、白板更新和 Review handoff 都要可见、可停、可恢复。 |

## 3. PaperTok 升级决策

### 3.1 Seminar 应融入 AI Chat 主路径

AI Chat 已经有插件、工具调用、thinking 能力和同一输入框。Seminar 的主路径应在 AI Chat 里完成：

- `AI 研讨会` 是 Chat run action，不是 `Choose style` 的一个普通 prompt 风格。
- `Choose style / 选择风格` 保留普通 skill/prompt 选择；其中的 `研讨会设置` 只进入配置页。
- 独立 `AiSeminarRuntimePage` 保留为详情、调试、恢复和兼容入口。
- 完整体验应是一张可展开的 Chat run card，含证据、角色发言、分歧、白板、总结、送审子视图。

### 3.2 当前实现事实

PaperTok 当前已经具备这些地基：

- 固定角色 contract：`critical / supportive / synthesizer`，可选 `verifier`。
- `AiSeminarRoleProfile` 已支持角色显示名和 custom prompt。
- Settings 全局默认已支持角色启用状态、会话证据提示和只读工具白名单；AI Chat 的 `本次研讨设置` 已支持单次 run 的角色 prompt、启用状态、verifier 和 `maxRounds`，不写回全局 Settings。
- runtime prompt 会注入角色 profile，同时仍要求只引用 supplied evidence ids。
- AI Chat 已可从 `+ -> AI 研讨会` 打开内嵌 runtime panel。
- 阅读页选中文本 `研讨` 已会进入阅读页 AI Chat 内嵌面板，并带入 reader `SourceRef`。
- `AiSeminarDirectorState` 已能记录轮次、已完成角色、证据账本、白板账本、分歧、用户插话和 next intent。
- `askUser` 状态下已支持让指定角色回应、重新找证据、整理总结。
- disagreement 在轮次预算内已能自动触发 evidence refresh。
- AI Chat 的 `AI 研讨会` 历史任务卡已能随 `conversationV2` 保存，并在 runtime 状态变化时按 `seminarSessionId` 回写 evidence/role/synthesis snapshot、分歧数、开放问题数和真实可追踪来源数量。

当前还不是完整 OpenMAIC-style Chat Seminar：

- 历史任务卡已有只读 snapshot，但还不是包含完整白板、送审子视图、run-scoped composer 子视图和 per-run 多实例隔离的完整结构化 Chat message part。
- 还没有完整 contradiction gap scan 和针锋相对的 rebuttal turn。
- 角色配置还缺空 prompt 显式提示、角色级证据过滤、角色级预算和真实角色工具调用 loop；当前证据提示会合并到整场 evidence bundle，不是每个角色独立检索。
- 仍是单个全局 runtime state，不支持同一 AI Chat 中多个 Seminar run 并存。
- `seminar_mode` 仍是普通 AI Chat prompt 风格，不等同于真正的 `AiSeminarRuntime`；文案和入口需要持续区分。
- OpenMAIC 当前源码没有强制最终总结节点，主要依赖角色自然总结或 Director `END`；PaperTok 必须保留明确的 `synthesizer` 终局节点，因为 Review、KnowledgeCard 和 Spaced Review 都需要结构化输出。

### 3.3 下一批任务

| TaskID | Goal | Acceptance |
| --- | --- | --- |
| E01-C05-T11 | 把 AI Chat Seminar run card 升级为完整 message part。 | 历史重载后仍显示证据、角色、分歧、白板、总结和送审；不把 Seminar 卡片当普通 assistant 回答生成知识卡或记忆。 |
| E01-C05-T12 | 增加 role profile governance v2。 | 已完成 Settings 全局默认和 AI Chat 本次 run 第一片：角色显示名、custom prompt、启用状态、会话证据提示和只读工具白名单可保存并注入新 run；secret-like prompt、写工具、联网工具、unknown tool 和递归 sub-agent 被拒绝。剩余验收是空 prompt 显式提示、角色级证据过滤、角色级预算和真实角色工具调用 loop。 |
| E01-C05-T13 | 接入 contradiction gap scan 和 rebuttal turn。 | 分歧必须绑定两个以上 role turns 和 evidence ids；Director 可选择重找证据或让指定角色反驳；预算耗尽进入用户确认。 |
| E01-C05-T14 | 把用户插话接入 Chat run composer。 | 用户可在同一 Chat run card 内选择继续讨论、问某角色、重找证据、整理总结；输入只写 user-turn ledger，不进入 formal evidence。 |
| E01-C05-T15 | 实现 per-run runtime state 隔离。 | 同一 AI Chat 会话中多个 Seminar run 不共享 turns/evidence/budget/job id；独立详情页和恢复缓存读取同一 run id。 |
| E01-C05-T16 | 区分 `seminar_mode` prompt 风格和 `AiSeminarRuntime` 多角色研讨。 | UI 文案、设置入口和历史卡都不把普通多视角回复风格描述成多 agent runtime；旧 skill 保留降级用途。 |
| E01-C05-T17 | 做 PaperTok evidence board action protocol。 | role turn 可以产生 `claim / counterclaim / evidence_request / open_question / review_candidate`；每个 formal claim 必须绑定 SourceRef 或保持 draft。 |

## 4. 许可边界

OpenMAIC 是 AGPL-3.0。PaperTok 只借鉴架构思想和产品模式，不复制 TypeScript 代码、prompt 模板、白板 action 实现或 UI 组件。任何直接移植代码都必须先经过许可证和发布策略审查。

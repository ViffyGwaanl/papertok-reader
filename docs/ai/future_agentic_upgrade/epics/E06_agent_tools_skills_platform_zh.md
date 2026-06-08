# E06 Agent Tools And Skills Platform

> 状态：In Review
> 目标：把 Skills、工具权限、sub-agent 执行和成本治理改成可审计、可测试的平台能力。

## 1. 现有基础

PaperTok Reader 已有：

- `AiToolRegistry`
- `AiToolScene`
- `ToolOrchestrator`
- `SubAgentRunner`
- `spawn_sub_agent`
- `AiSkillRegistry`
- `ToolApprovalDelegate`
- token/成本追踪

未来能力必须复用这些基础，不新建平行 agent runtime。

## 2. Capability

### E06-C01 Tool Permission Matrix

按场景限制工具：

- reading
- library
- global
- system
- seminar
- review

写工具默认需要审批。Seminar role agent 默认只读。

### E06-C02 Sub-Agent Governance

规则：

- 禁止递归 spawn。
- 默认串行。
- 只读检索可并行。
- 每个 sub-agent 有 max steps、timeout、cost budget。
- 错误必须归因到角色和工具。

### E06-C03 Custom Skills Contract

不写“支持 YAML Skills”一句话，拆成：

- schema
- parser
- validator
- permission declaration
- UI import
- runtime injection
- fixture tests

### E06-C04 Cost And Capability Matrix

Provider/model 需要声明：

- context size
- tool support
- vision support
- responses compatibility
- cost estimate
- streaming behavior

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E06-C01-T01 | 定义 tool permission matrix | 无 | permission spec | 每个 scene 有工具白名单和写入规则。 |
| E06-C02-T01 | 定义 sub-agent governance | E06-C01-T01 | governance spec | 禁止递归、取消、超时、预算可验证。 |
| E06-C02-T02 | 定义 agent run identity 与父子图 | E06-C02-T01 | `AgentRun`, parent/child edge schema, store tests | 每个 spawned agent / Seminar parent Director run / Seminar role run 有 runId、parentRunId、role/profile、status、started/completed 时间；可列出 children/descendants；open/closed 状态可恢复。 |
| E06-C02-T03 | 接入 sub-agent 状态流和 delta 回传 | E06-C02-T02, E07 Chat UI | agent event stream + AI Chat message parts | sub-agent 能输出 status、tool_call、message_delta、result、error；AI Chat 原生消息流可显示，不弹独立窗口。 |
| E06-C02-T04 | 改造 `spawn_sub_agent` 为可追踪 agent run | E06-C02-T03 | `spawn_sub_agent` run adapter + tests | 工具返回 agentRunId/status/result summary；支持 wait/cancel/resume；不再只返回纯文本；仍禁止递归和写工具。 |
| E06-C02-T05 | Seminar role agent 接入同一平台 | E06-C02-T03, P1-S7 | Seminar role adapter + regression tests | `critical/supportive/synthesizer/verifier` 角色 turn 使用同一 agent run/event/permission 模型；AI Chat 原生呈现工具调用、证据、角色输出和完成状态。 |
| E06-C03-T01 | 拆分 custom skills 任务 | E06-C01-T01 | skills task set | schema/parser/validator/UI/runtime/tests 分开。 |
| E06-C04-T01 | 定义 provider capability matrix | 无 | provider matrix | Seminar 可据此选择模型和预算。 |

当前实现切片：

- `CustomSkillContract` 已提供 schemaVersion `1`、JSON/Map parser、字段类型错误上报、unknown field 报错、unknown scene 报错、system scene 拦截、写工具拦截、`spawn_sub_agent` 拦截和 `canInject` runtime gate。
- `CustomSkillStore` 和 `CustomSkillsPage` 已提供 Settings -> AI 导入入口、safe fixture 示例、valid contract upsert、禁用/删除、unsafe JSON 拦截、Installed skills runtime 状态展示和 Active Skill 合并。
- `AiSkill.allowedToolIds/sceneIds` 与 `LangchainAiRegistry.enabledToolIdsForActiveSkill` 已把 active custom skill 的 runtime 工具集收窄到 contract 声明过且当前 scene/permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具。
- `AiSeminarProviderContextService` 已把 Provider Center 当前 provider/model、本地 `AiModelCapability` cache、context/max output、Tools/Vision/Thinking 状态和 pricing metadata 投影到 Seminar runtime state 和 `Provider readiness` UI；当前 schema 没有 streaming 字段时显示 `Streaming unknown`，缺少 pricing metadata 时显示成本未知原因。
- `AiSeminarTokenUsage` 已把 Seminar completed role turn 的 provider-reported token usage 写入 runtime state 和页面；没有 provider usage metadata 时降级为 `local-char-estimate-v1` 本地 input/output token 估算；两者都可作为 estimated USD cost cap 的 usage 输入，但不等于真实 provider 发票。
- `AiSeminarBudgetPolicy` 已把 Seminar role output / run token budget 和 estimated USD run cost cap 放入 session contract；runtime 使用 `local-char-estimate-v1` 在流式 partial 或 completed turn 超限时停止后续步骤，并在有 pricing metadata 时用 provider/local usage 聚合估算美元成本、超出 cap 时停止后续步骤；页面显示本地 budget guardrails、`Run cost cap USD` 和 pricing source。
- `AiSeminarRuntimeNotifier` 已把 Seminar completed/cancelled/failed state 保存为 `aiSeminarRuntimeStateV1` 本机恢复缓存；恢复只在同一书籍/同一入口问题显示，换书或换选区会清理旧 runtime/cache；restored running state 只要 evidence 可追踪、completed turns 是合法连续前缀且 provider/model/pricing 匹配当前配置，就会复用已保存 evidence 并从第一个缺失角色继续；已有 completed role 会跳过，没有 completed turn 但已有 evidence 时从首个角色重新生成；只有 active partial stream 时丢弃半截文本，不继续旧 LLM stream；checkpoint 无效、evidence 不可追踪、provider 已切换或 queued job 会恢复为 interrupted/retryable；该 key 被普通 prefs backup 排除。
- `AiToolPermissionMatrix`、`SubAgentGovernancePolicy`、`AiToolRegistry` governance filter、`SubAgentRunner.allowedToolIdsForAgent` 与 `ToolOrchestrator` 已有 focused tests 覆盖。
- `SubAgentRunner.runTracked(...)` 已提供普通 sub-agent 的可追踪结果首片，`SubAgentRunResult` 保存 `agentRunId`、`parentRunId`、normalized agent type、`completed/errored` status、max steps、scene、allowed tools、started/finished time、result/error；`spawn_sub_agent` 工具现在返回这份 metadata，而不是只返回 `{agentType, task, result}`，并会把结果写入 `AgentRunGraphStore`。旧 `SubAgentRunner.run(...)` 仍兼容纯文本调用方。
- `AgentRunGraphStore` 已提供 parent/child graph store 首片，写入 `.workflow/agent_runs_v1.json`，支持 `upsertRun`、`upsertFromSubAgentResult`、`listChildren`、`listOpenChildren`、`listDescendants`、`closeChildRun` 和 edge `open/closed` 状态恢复；测试覆盖 parent -> child -> grandchild、重建 store 恢复、open child 过滤、graph-store 级 close 和 AI Chat 卡内 close 回写。child run 终态自动闭合首片已接入：`pendingInit/running/waiting_input/interrupted` edge 保持 `open`，`completed/errored/shutdown/notFound` edge 自动转为 `closed`，普通 `spawn_sub_agent` 和 completed Seminar role turn 的 parent/child edge 都会在完成后 closed，避免 wait/close/resume 视图把已结束子 run 误判为活跃；`listOpenChildren(parentRunId)` 可直接列出仍 open 的 child run，供后续 AI Chat 原生 wait/close/resume 控制 UI 判断仍在运行、等待输入或可恢复的子 agent；`closeChildRun(parentRunId, childRunId)` 可把 open child run 写成 `shutdown`、关闭 edge 并落 status event，且 close timestamp 会保证不早于 child startedAt，避免时钟漂移后 status latest replay 仍选中旧 running。
- `AiSeminarRuntimeService` 在注入 `AgentRunGraphStore` 时，已能把 Seminar 父 Director run 和 role run 写入同一 parent/child graph：父 run 使用 `runId=<sessionId>`、`source=seminar`、`profile/roleId=director`，开始时写 `running`，synthesis terminal 写 completed/needsEvidence 与 summary result；取消、fetch failed、evidence gap、unsafe checkpoint、role executor error、role contract failure 和 token/cost budget failure 等主流程 early terminal 会写 `interrupted` 或 `errored`，避免 graph 停在假 running；Director 进入 `askUser` 时会写 `status:waiting_input` event，保留开放问题或分歧 prompt，并带本场可回应角色 ids 供 AI Chat 历史恢复；role run 使用 `runId=<sessionId>:role-<role>-<index>`、`parentRunId=<sessionId>`、role/profile、nickname、allowed tools、started/finished time 和 result/error；completed/errored role turn 会更新同一 run。
- `AgentRunEvent` replay store 已有首片，graph schema 新增 `events`，支持 `status/message_delta/tool_call/user_input/resume_request/result/error` 事件类型；`SubAgentRunStatus` 新增 `waiting_input`，用于表达父 Director 等待读者输入；`upsertRun(...)` 会自动为普通 sub-agent 和 Seminar 父 Director run 落 status/result/error 事件；Seminar role start/partial/completed 会分别落 running status、message_delta、completed status/result 事件；`tool_call` event 可保存 toolId、query、resultCount、roleIds、evidenceRefs 和 evidence SourceRef；`user_input` event 可保存读者给 waiting child run 的输入；`resume_request` event 可保存读者对 interrupted child run 的继续请求；`acknowledgedAt` 可标记控制事件已被 runner 消费；`listPendingControlEvents(parentRunId, childRunId)` 与 `acknowledgeControlEvent(...)` 已提供 child control inbox 首片，让 active scoped Seminar runtime 的 `send-input/resume-agent` 首片和后续 `sendInput/resumeAgent` runner 能读取并确认未消费的输入/继续请求；runtime evidence broker 已开始把 traceable evidence bundle 按 scope 写成 parent Seminar run 的 `tool_call` events；`getRun(runId)`、`listEvents(runId)` 与 `listChildEvents(parentRunId)` 可供 AI Chat 后续回放。
- `agent_run_event_message_part_adapter.dart` 已提供 event -> AI Chat message part 首片：`AgentRunEventType.messageDelta` 可转换为 Seminar `role_partial` message part，`AgentRunEventType.userInput` 可恢复为 `reader_turn(label=send-input)`，`AgentRunEventType.resumeRequest` 可恢复为 `reader_turn(label=resume-agent)`；AI Chat live role partial snapshot 已开始通过该 adapter 生成 stable event id，而不是旧 `active-role-*` id；service 层也已能通过 `seminarMessagePartsFromAgentRunGraphStore(store, parentRunId: ...)` 合并持久化 parent Director events 与 child events，恢复 `role_partial`、`director_state`、`role_turn`、`reader_turn`、`synthesis`、`tool_call` 和 Director waiting-input `reader_composer` parts；`AiChat.loadHistoryEntry(...)` 已能把同 session persisted `message_delta/status/result/error/tool_call/user_input/resume_request` 自动补进历史 Seminar 卡的 `snapshot.messageParts`；persisted `status/result/error/user_input/resume_request` 事件也已有首片可恢复为原生 parts：子角色状态/失败进入 `director_state(label=role-*)`，子角色结果进入 `role_turn`，子角色输入进入 `reader_turn(label=send-input)`，子角色继续请求进入 `reader_turn(label=resume-agent)`，父 Director completed 状态进入 `director_state(label=end)`，父 Director result 进入 `synthesis`，父 Director `waiting_input` 状态进入 `reader_composer(label=ask-user)`，并恢复 `roleIds/defaultRoleId/selectedRoleId` 与 `selectedActionId=ask-role`，历史卡可显示角色运行状态、完成输出、失败状态、读者给子角色的输入、继续请求、父 Director 总结、等待用户输入 cue 和可回应角色；persisted/runtime evidence `tool_call` 事件也可恢复为 Seminar `tool_call` message part，保留查询、命中数、可见角色和证据引用。
- `seminarMessagePartsFromAgentRunGraphStore(...)` 现在还会读取 `listOpenChildren(parentRunId)` 作为 fallback：如果 graph 里有仍 open 的 child run record / edge，但缺少对应 status event，它会合成同 event id 规则的 status event，再走原 event adapter 恢复为 `director_state(label=role-*)`；已有真实 event 时按 event id 去重，避免重复显示。status replay 还会折叠同一 run 的多条 status event，只保留最新状态；`AiChat._appendSeminarMessageParts(...)` 也会按 status run id 替换同一卡片里的旧状态，避免 child run 关闭后当前卡继续保留旧 `running` part。
- open child / role status message part 已开始携带原生 agent control action metadata：`pending_init/running` 对应 `wait-agent + close-agent`，`waiting_input` 对应 `send-input + close-agent`，`interrupted` 对应 `resume-agent + close-agent`，终态不带 actionIds；Director parent status 不再携带 role-level wait/close actionIds。AI Chat 历史 role status tile 已可把可解析 child `close-agent` 渲染成原生 `停止角色` ActionChip，并调用 `AiChat.closeSeminarRunCardAgent(...)` 关闭对应 child graph run、刷新当前卡为 `role-shutdown`；可解析 child `wait-agent` 也已可渲染为原生 `等待角色` ActionChip，并调用 `AiChat.waitSeminarRunCardAgent(...)` 从 graph replay 同 session events，把已完成 child run 刷新为 `role-completed + role_turn`；可解析 child `send-input` 已可渲染为原生 `发送输入` ActionChip，在同一状态块展开输入框，并调用 `AiChat.sendSeminarRunCardAgentInput(...)` 把读者输入写成 `user_input` event 后刷新当前卡为 `reader_turn(label=send-input)`；可解析 child `resume-agent` 已可渲染为原生 `继续角色` ActionChip，并调用 `AiChat.resumeSeminarRunCardAgent(...)` 把继续请求写成 `resume_request` event 后刷新当前卡为 `reader_turn(label=resume-agent)`；这些控制事件现在还能通过 pending control inbox 被 runner 查询并 ack。这让 `close-agent`、`wait-agent`、`send-input` 和 `resume-agent` 都已有用户可点击首片；其中 `send-input` 在同 session active scoped runtime 存在且已持有 evidence 时，已能由 `runPendingAgentControl(...)` 消费首个 pending `user_input`、调用目标 role 追加 follow-up turn 并 ack；`resume-agent` 在同 session active scoped runtime 存在且已持有 evidence 时，已能由同一入口消费首个 pending `resume_request`、重新运行目标 role follow-up turn 并 ack；历史卡或无 active runtime 时两者仍只是记录可恢复控制事件；真实 provider stream 阻塞/恢复、旧 stream 原地续传和完整 subagent 控制 UI 仍未完成。
- AI Chat Seminar 运行中卡片已有原生 `取消研讨` 首片：同 session runtime `canCancel` 时，任务卡直接调用 scoped runtime notifier `cancel()`，把状态转为 `cancelled`，不打开独立窗口。
- Seminar role agent 的完整 sendInput/resumeAgent 协作协议、角色自由工具调用、真实 provider stream 中断或阻塞等待、超时、价格版本/真实账单对账和后台任务队列仍保留为本 Epic 的剩余 Agent Task；Seminar parent Director run lifecycle / early terminal writeback、Director waiting-input event、role live event replay、partial adapter、persisted child delta -> role_partial service adapter、历史卡 `role_partial` hydration、persisted status/result/error/user_input/resume_request 可见化、control inbox + ack、active scoped runtime 消费 `send-input/resume-agent` 首片、status latest-only replay、persisted tool_call replay、runtime evidence tool_call event、graph-store `closeChildRun`、AI Chat 卡内 `close-agent`、AI Chat 卡内 `wait-agent` graph refresh、AI Chat 卡内 `send-input` 输入记录、AI Chat 卡内 `resume-agent` 请求记录和卡内 cancel 都只是底座/首片，不在当前切片中冒充完整平台。

Codex 开源参考带来的新增判断：

- `openai/codex` 把 sub-agent 表达为带来源和父子关系的 session/thread，而不是一个普通工具返回值：`SessionSource.subagent` 可携带 `parent_thread_id`、depth、agent path、nickname 和 role。
- 它有独立的 parent/child graph store，支持 upsert spawn edge、open/closed 状态、children 和 descendants 查询。
- 它把协作 agent 的生命周期暴露为状态和工具事件：`pendingInit/running/interrupted/completed/errored/shutdown/notFound`，以及 `spawnAgent/sendInput/resumeAgent/wait/closeAgent`。
- 它把 agent 输出拆成 message delta 和 tool call event，而不是只在结束时返回纯文本。
- PaperTok 不需要照搬 Codex 的远端 identity/JWT/task registration，但应该借鉴“agent run 有身份、有状态、有父子边、有可见事件、有关闭/恢复动作”的产品结构。
- 因此 AI Seminar 应归入同一 agent 平台：Seminar 角色是阅读场景预置 sub-agents，Director 是父 run 的调度策略，evidence broker 是共享只读工具输入。

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `AiToolRegistry`, `AiToolScene`, `ToolOrchestrator`, `SubAgentRunner`, `AiSkillRegistry`, Provider Center config。 |
| Allowed Modules | AI tools/skills runtime, provider capability docs/tests, settings UI specs。 |
| Forbidden Changes | 不绕过 tool approval；不允许 custom skill 声明任意写工具；不默认开 agent pool。 |
| Verification Commands | Focused tests for whitelist, no recursion, cancel/timeout, write approval, cost tracking; `git diff --check`。 |
| Reviewer Gate | Agent Safety And Privacy Gate + Mobile Resource Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | custom skills 可禁用；sub-agent governance 失败时回退到现有 prompt skill。 |

## 5. Gates

- Agent Safety And Privacy Gate：工具不能越权外发或写入。
- Mobile Resource Gate：sub-agent 并行必须受限。
- Review And Rescue Gate：测试必须覆盖白名单、禁止递归、写工具审批、取消、超时、成本记录。

## 6. Non-Goals

- 不做公开技能市场。
- 不让自定义技能绕过工具权限。
- 不在移动端默认开高并发 agent pool。

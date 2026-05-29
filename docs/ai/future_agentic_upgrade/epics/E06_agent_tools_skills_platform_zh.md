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
| E06-C03-T01 | 拆分 custom skills 任务 | E06-C01-T01 | skills task set | schema/parser/validator/UI/runtime/tests 分开。 |
| E06-C04-T01 | 定义 provider capability matrix | 无 | provider matrix | Seminar 可据此选择模型和预算。 |

当前实现切片：

- `CustomSkillContract` 已提供 schemaVersion `1`、JSON/Map parser、字段类型错误上报、unknown field 报错、unknown scene 报错、system scene 拦截、写工具拦截、`spawn_sub_agent` 拦截和 `canInject` runtime gate。
- `CustomSkillStore` 和 `CustomSkillsPage` 已提供 Settings -> AI 导入入口、safe fixture 示例、valid contract upsert、禁用/删除、unsafe JSON 拦截、Installed skills runtime 状态展示和 Active Skill 合并。
- `AiSkill.allowedToolIds/sceneIds` 与 `LangchainAiRegistry.enabledToolIdsForActiveSkill` 已把 active custom skill 的 runtime 工具集收窄到 contract 声明过且当前 scene/permission matrix 允许的只读工具；custom skill 激活时不加载 MCP 工具。
- `AiSeminarProviderContextService` 已把 Provider Center 当前 provider/model、本地 `AiModelCapability` cache、context/max output、Tools/Vision/Thinking 状态投影到 Seminar runtime state 和 `Provider readiness` UI；当前 schema 没有 streaming 字段时显示 `Streaming unknown`，缺少 pricing/usage metadata 时只显示成本未知原因。
- `AiSeminarTokenUsage` 已把 Seminar completed role turn 的本地 input/output token 估算写入 runtime state 和页面；这是 `local-char-estimate-v1`，不读取 provider billing metadata，不展示美元成本。
- `AiToolPermissionMatrix`、`SubAgentGovernancePolicy`、`AiToolRegistry` governance filter、`SubAgentRunner.allowedToolIdsForAgent` 与 `ToolOrchestrator` 已有 focused tests 覆盖。
- 取消、超时、真实 provider usage 成本记录、角色预算、成本上限和后台恢复状态仍保留为本 Epic 的剩余 Agent Task，不在当前切片中冒充完成。

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

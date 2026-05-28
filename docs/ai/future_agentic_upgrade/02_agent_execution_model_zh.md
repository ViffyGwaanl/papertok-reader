# Agent Execution Model

## 1. 执行语法

所有未来升级任务必须写成：

```text
Epic -> Capability -> Agent Task -> Gate -> Acceptance
```

不使用人日、月份、季度或“优先级 P1/P2”作为执行依据。排序只由依赖、风险和 Gate 决定。

## 2. Agent Task 模板

```text
TaskID:
Parent Capability:
Goal:
Depends On:
Input Truth:
Output Artifact:
Allowed Modules:
Forbidden Changes:
Pre-Gates:
Implementation Steps:
Verification Commands:
Acceptance:
Reviewer Gate:
Rollback / Degrade Path:
Out of Scope:
```

### 字段要求

| 字段 | 要求 |
| --- | --- |
| `TaskID` | 使用 `E##-C##-T##`，例如 `E01-C02-T03`。 |
| `Parent Capability` | 指向 Epic 内的能力名。 |
| `Goal` | 一句话说明交付的可观察行为。 |
| `Depends On` | 列出必须已 Accepted 的 task 或 gate；不得写 `Draft` 作为可执行依赖。 |
| `Input Truth` | 指向真实来源：代码路径、DB schema、现有文档、fixture。 |
| `Output Artifact` | 明确产物：代码、表结构、测试、文档、截图、日志。 |
| `Allowed Modules` | 允许修改的模块或目录。 |
| `Forbidden Changes` | 明确不能碰的模块、用户数据或旧行为。 |
| `Pre-Gates` | 执行前必须满足的 gate。 |
| `Implementation Steps` | 以 checkbox 写可执行步骤。 |
| `Verification Commands` | 写命令和预期结果，不写“跑相关测试”。 |
| `Acceptance` | 写可断言结果：DB 行、UI 文案、deep link、状态流转。 |
| `Reviewer Gate` | 指定 review/rescue gate。 |
| `Rollback / Degrade Path` | 写关闭开关、回退路径或兼容策略。 |
| `Out of Scope` | 防止 agent 顺手重构或扩范围。 |

## 3. 禁止写法

以下词在 Agent Task 中默认不合格，必须改成具体 Gate 或 Acceptance：

- `未来优化`
- `后续完善`
- `可接受`
- `稳定`
- `必要时`
- `大概支持`
- `尽量`
- `打磨`
- `支持 X`，但没有 schema、测试和验收

示例：

| 不合格 | 合格 |
| --- | --- |
| 后续完善 Seminar 体验。 | `E01-C03-T02`：给 Seminar 输出增加 `roleId/claim/evidenceRefs/finalSynthesis`，测试 fake role runner 返回 3 个角色时 UI 可展示并可恢复。 |
| 支持 YAML Skills。 | 拆成 schema、parser、validator、UI 导入、runtime 注入、权限 gate、测试样例。 |
| RAG 更稳定。 | 覆盖旧 DB 升级、新索引失效、书籍删除、provider 切换、FTS5 缺失、网络失败、重启续跑。 |

## 4. 数据归属标签

每个 task 必须标注涉及数据的归属：

| 标签 | 含义 | 默认策略 |
| --- | --- | --- |
| `source-of-truth` | 用户原始书籍、用户笔记、用户确认卡片、长期记忆。 | 必须备份/同步策略明确。 |
| `derived-cache` | `ai_index.db`、RAG chunk、RAPTOR、GraphRAG 自动索引。 | 可删除重建，默认不作为同步真相源。 |
| `user-authored` | 用户手写内容或用户确认写入。 | 不被 AI 静默覆盖。 |
| `AI-generated-draft` | AI 生成但未确认内容。 | 进入 Review 或留在会话，不进入正式资产。 |
| `AI-generated-approved` | 用户确认后的 AI 内容。 | 作为用户资产处理，保留 provenance。 |

## 5. 默认执行顺序

```text
contract/schema
  -> producer
  -> retrieval/tool
  -> review/write gate
  -> UI
  -> sync/backup/export
  -> release promotion
```

任何 agent 不得先做 UI 再补数据 contract。例外必须写在 `Pre-Gates` 并通过 rescue review。

## 6. Epic Task Defaults

Epic 文档可以为一组 Agent Task 声明共同默认项，例如共同的 `Input Truth`、`Allowed Modules`、`Forbidden Changes`、`Verification Commands`、`Reviewer Gate` 和 `Rollback / Degrade Path`。实现 agent 领取单个 task 时，必须合并：

```text
具体 task 行
+ 本 Epic 的 Task Execution Defaults
+ 本 Epic 引用的 gates
```

如果 task 行和默认项冲突，以更严格的限制为准。若仍无法判断，任务状态必须改为 `Blocked`，不能由实现 agent 自行决定。

## 7. Reviewer / Rescue Gate

每个 Epic 完成前必须有独立 review。若没有可调用的 `/codex:rescue` 工具，则派独立 reviewer subagent 执行同等审查。

Reviewer 必查：

- 数据归属是否清楚。
- AI 生成内容是否默认 draft。
- 证据链是否能跳回原文或 source chunk。
- 工具权限是否受场景限制。
- 测试是否能由命令证明。
- 是否含有“未来优化”式空话。

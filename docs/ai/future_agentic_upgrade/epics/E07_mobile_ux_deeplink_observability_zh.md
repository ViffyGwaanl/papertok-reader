# E07 Mobile UX, Deep Link, And Observability

> 状态：In Review
> 目标：统一 AI 面板、Seminar 入口、索引进度、生成进度、deep link、错误恢复和成本可见性。

## 1. Capability

### E07-C01 Reading Entry Points

入口必须贴合阅读：

- 选中文本 -> Seminar。
- 图片分析 -> KnowledgeCard draft。
- 章节标题 -> Study/Seminar。
- AI 回答片段 -> Card/Review。

默认不新增独立 OpenMAIC 页面。

### E07-C02 Progress And Recovery

必须可见：

- 当前生成是否仍在运行。
- 当前索引是哪本书、哪个章节、哪个阶段。
- 失败原因和重试入口。
- 断线后是否可恢复。

### E07-C03 Deep Link Contract

所有关键输出能回跳：

- KnowledgeCard
- ReviewItem
- Seminar claim
- Concept node
- Graph edge evidence
- Flashcard

统一使用 `paperreader://reader/open?...`。

### E07-C04 Cost And Source Transparency

用户能看到：

- 本次使用了哪些资料范围。
- 是否使用 library。
- 是否使用 web。
- `inputTokens`、`outputTokens`、`toolCalls`、`estimatedCostUsd`、`costPriceSource`；无法估算时显示 `costUnknownReason`。
- 哪些内容是模型推断。

## 2. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E07-C01-T01 | 定义阅读页入口矩阵 | E01-C01-T01 In Review slice, E03-C01-T01 In Review slice | UX entry matrix | 每个入口有输入、输出、回退。 |
| E07-C01-T02 | 接入 Review Inbox 设置入口 | E05-C01-T02 In Review slice | `ReviewInboxPage`, AI settings entry | 知识资产审批入口出现在设置导航和 AI 设置页，widget smoke 可编译。 |
| E07-C02-T01 | 定义 progress contract | E02 Ready | progress spec | 书籍级索引和生成状态可见。 |
| E07-C03-T01 | 定义 deep link 验收矩阵 | E00 Ready | deep link matrix | 所有输出可回跳或说明不可跳原因。 |
| E07-C03-T02 | 接入 SourceRef reader intent audit | E07-C03-T01 | `PaperReaderReaderIntent`, `PaperReaderSourceJumpAudit` | SourceRef 生成 `paperreader://reader/open?...` intent，非法 link 不算 evidence。 |
| E07-C04-T01 | 定义 source/cost UI contract | E06-C04-T01 In Review slice | transparency spec | 用户可见资料范围、web 状态、成本。 |

## 3. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | AI panel UX, reading page selection/image hooks, RAG progress, reader deep links, usage tracker。 |
| Allowed Modules | reading page UI, AI panel UI, progress/diagnostic UI, deep link tests/docs。 |
| Forbidden Changes | 不重写 AI chat provider ownership；不新增独立课堂首页；不隐藏失败原因。 |
| Verification Commands | Focused widget/service tests for source jump, progress state, cancel/retry; platform smoke checklist when UI changes; `git diff --check`。 |
| Reviewer Gate | Mobile Resource Gate + Retrieval Quality Gate + Release Promotion Gate。 |
| Rollback / Degrade Path | 新入口可 feature-flag 关闭；失败时保留原 AI panel/chat 入口。 |

## 4. Gates

- Mobile Resource Gate：长任务可取消、失败可恢复或重试。
- Retrieval Quality Gate：回跳链接和 source ref 一致。
- Release Promotion Gate：iPhone/iPad/Android 至少有 smoke checklist。

## 5. Non-Goals

- 不重做 AI 面板架构。
- 不默认加入复杂图谱画布。
- 不牺牲阅读页主体验换取课堂式首页。

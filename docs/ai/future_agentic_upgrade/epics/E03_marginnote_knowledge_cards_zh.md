# E03 MarginNote-Style Knowledge Cards

> 状态：In Review
> 目标：建立 PaperTok 原生 KnowledgeCard，让高亮、笔记、AI 摘要、Seminar 结论、图片分析和 RAG evidence 都能沉淀为可审核、可复习、可回跳原文的知识对象。

## 1. 融合方式

借鉴 MarginNote 的摘录卡、脑图节点、flashcard 和源文档双向链接，但 PaperTok 默认让 AI 先生成候选，用户再轻量确认。

## 2. Capability

### E03-C01 KnowledgeCard Contract

字段至少覆盖：

- `id`
- `title`
- `quote`
- `explanation`
- `userNote`
- `sourceRefs`
- `conceptRefs`
- `tags`
- `reviewState`
- `origin`
- `ownership`
- `createdAt`
- `updatedAt`

默认：AI 生成卡片是 `draft` 或 `pending`，不自动写入长期记忆。

### E03-C02 Card Producers

允许来源：

- 阅读页选中文本。
- 高亮/笔记。
- AI Chat 回答片段。
- Seminar synthesis。
- 图片分析结果。
- RAG evidence。
- Memory candidate。

### E03-C03 Deduplication And Merge

重复检测基于：

- `sourceHash`
- `bookId + href + cfi`
- normalized quote
- concept overlap

重复时进入合并建议，不静默覆盖用户内容。

### E03-C04 Card To Review

卡片进入 Review 状态流：

```text
draft -> pending -> approved/dismissed -> applied
```

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E03-C01-T01 | 定义 KnowledgeCard schema | E00 Ready | card contract | 字段、状态、归属、sourceRefs 明确。 |
| E03-C01-T02 | 接入 KnowledgeCard runtime model/store | E03-C01-T01 | `lib/models/knowledge_card.dart`, `KnowledgeCardStore` | AI-generated card 默认 draft/pending，applied 无 traceable evidence 会降级。 |
| E03-C02-T01 | 定义 producer matrix | E03-C01-T01 | producer table | 每个来源有输入、输出、失败策略。 |
| E03-C03-T01 | 定义重复检测策略 | E03-C01-T01 | dedupe spec | 同一段文字重复生成不产生重复正式卡。 |
| E03-C03-T02 | 接入 duplicate candidate guard | E03-C03-T01 | `KnowledgeCardStore.upsertCandidate` | 同 source hash、book anchor 或 normalized quote 不制造重复卡，不覆盖用户 note。 |
| E03-C04-T01 | 对齐 Review 状态流 | E03-C01-T01, E05-C01-T01 Accepted | review handoff spec | pending/apply/dismiss 可追踪。 |
| E03-C04-T02 | 接入 KnowledgeCard Review adapter | E03-C04-T01 | `KnowledgeCardReviewAdapter` | approve/apply/dismiss mirror 源资产，dismiss 保持 draft ownership。 |

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | book notes/highlights, Memory candidate, AI chat segment metadata, Seminar synthesis, RAG evidence SourceRef。 |
| Allowed Modules | Knowledge card models/services, review handoff, focused card/review tests/docs。 |
| Forbidden Changes | 不批量自动迁移旧高亮；不静默写长期记忆；不覆盖用户笔记；不把 raw full text 同步。 |
| Verification Commands | Focused tests for card schema, SourceRef, dedupe, review state transitions; `git diff --check`。 |
| Reviewer Gate | Agent Safety And Privacy Gate + Retrieval Quality Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | 生成失败时保留 AI chat 输出，不创建 card；重复检测失败时只进入 pending。 |

## 5. Gates

- Agent Safety And Privacy Gate：AI 卡片默认不进入长期记忆。
- Retrieval Quality Gate：正式卡片必须有 source ref 或标记 unverified。
- Review And Rescue Gate：删除书、改书 MD5、恢复备份时不产生不可解释悬空关系。

## 6. Acceptance Chain

最小端到端验收：

```text
选中文本 -> 生成 KnowledgeCard draft -> Review approve -> 进入复习项 -> 点击 source -> 跳回原文
```

## 7. Non-Goals

- 不先做复杂无限脑图。
- 不把旧高亮批量自动迁移为卡片。
- 不让 AI 静默合并或覆盖用户笔记。

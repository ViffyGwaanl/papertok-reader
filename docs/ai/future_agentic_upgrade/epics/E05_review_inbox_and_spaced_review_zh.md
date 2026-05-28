# E05 Review Inbox And Spaced Review

> 状态：Ready  
> 目标：把现有 Memory Review Inbox 扩展为 PaperTok 的知识资产审批、复习和回溯中心。

## 1. 设计原则

Review 是所有持久化知识变更的人审门。AI 可以提出候选，但不能静默把内容写入用户资产。

## 2. Capability

### E05-C01 Unified Review Item

ReviewItem 来源：

- Memory candidate
- KnowledgeCard draft
- Seminar synthesis
- ConceptGraph relation
- Flashcard candidate
- Image analysis card

状态流：

```text
draft -> pending -> approved/dismissed -> applied
```

### E05-C02 Spaced Review Contract

复习项必须能回溯：

- cardId
- sourceRefs
- prompt
- answer
- lastReviewedAt
- dueAt
- interval
- lapses
- reviewHistory

算法实现可替换，但字段必须稳定。

### E05-C03 Weak Concept Feedback Loop

用户答错或标记模糊时，系统生成：

- 重读建议。
- 相关卡片。
- 可重新开启的 Seminar。
- ConceptGraph 薄弱节点标记。

## 3. Agent Tasks

| TaskID | Goal | Depends On | Output Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| E05-C01-T01 | 定义 Unified ReviewItem | E00 Ready, E03 Ready | review contract | 每种来源有状态流和 source refs。 |
| E05-C02-T01 | 定义 Spaced Review 字段 | E05-C01-T01 | review scheduler contract | 复习记录可追踪且可导出。 |
| E05-C03-T01 | 定义错题反馈路径 | E05-C02-T01, E04-C01-T01 Accepted | feedback spec | 错题能回到卡片、原文、概念和 Seminar。 |

## 4. Task Execution Defaults

| 字段 | 默认值 |
| --- | --- |
| Input Truth | `MemoryWorkflowService`, existing Review Inbox behavior, KnowledgeCard contract, SourceRef。 |
| Allowed Modules | review service/UI, memory workflow adapters, review scheduler model/tests/docs。 |
| Forbidden Changes | 不自动 approve AI draft；不覆盖用户 memory；不绑定单一复习算法实现；不泄露学习弱点。 |
| Verification Commands | Focused tests for draft/pending/approved/dismissed/applied, source jump, due review fields; `git diff --check`。 |
| Reviewer Gate | Agent Safety And Privacy Gate + Sync Backup Export Gate + Review And Rescue Gate。 |
| Rollback / Degrade Path | 复习调度失败时保留 ReviewItem，不丢 source refs 或用户确认状态。 |

## 5. Gates

- Agent Safety And Privacy Gate：复习弱点是敏感用户数据，默认本地。
- Review And Rescue Gate：apply/dismiss 必须可追踪，不允许自动覆盖用户内容。
- Sync Backup Export Gate：跨设备同步前必须定义 per-entity conflict。

## 6. Non-Goals

- 不在第一版实现完整学习统计。
- 不把所有 Memory 自动转卡片。
- 不让复习算法绑定单一外部库。

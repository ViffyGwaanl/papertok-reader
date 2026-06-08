# P4 AI Assisted Artifact Review

> 状态：In Progress
> 最后更新：2026-06-05
> 目标：把 AI 产物保存做成低负担当前页闭环，并把 Review Inbox 收窄为 AI 辅助异常处理中心。

## 1. 用户价值

用户不应该每生成一张知识卡、一个研讨总结、一个图谱节点或一条记忆，都被迫去 Review Inbox 手工审批。普通学习动作应该就地完成：保存、编辑、撤销、查看来源。

Review Inbox 的价值是处理异常，而不是承接普通流程。它应该帮用户处理低置信、冲突、来源断裂、重复、同步冲突和批量导入不确定项。并且这些异常也不应该纯靠人手判断，AI 要先做预审和建议。

## 2. 当前状态

当前分支已有：

- 部分 AI Chat 知识卡、图片解析知识卡、Selection/RAG evidence 保存迁回 draft inline。
- completed Seminar 卡片内保存知识卡、加入复习、加入图谱、忽略和撤销。
- Memory 显式保存从默认 Review 迁回内联写入。
- Review Inbox 有多种 source-specific adapter。
- Review Inbox 能处理部分知识卡、图谱关系、flashcard、memory、sync conflict。
- completed AI Chat Seminar 的异常送审预览已能在 `异常` 子视图展示第一片 AI 预审建议、风险等级和建议动作，并把建议作为 `messageParts.review_triage label=ai-suggestion/risk/suggested-action` 随历史恢复；默认 `研讨流` 也会把这些 part 显示成 `AI 风险等级 / 中风险` 与 `建议动作 / 送入异常中心`，不再暴露 `medium/send-to-review` 这类内部值。

当前主要问题：

- AI 辅助预审仍不完整；目前 Seminar handoff 只有本地规则化建议首片，还没有统一 AI reviewer service。
- Review Inbox 对用户价值的表达不够清楚。
- 一些旧 producer 和兼容路径仍容易把普通产物送审。
- AI 对重复、冲突、证据不足、风险等级和处理建议还没有形成统一服务。
- Review Inbox 还需要从“审批列表”变成“异常处理队列”。

## 3. 目标形态

普通路径：

1. AI 生成内容。
2. 系统检查 SourceRef 和低风险条件。
3. 用户在当前页直接保存、编辑、撤销或忽略。
4. 保存后成为 draft 或用户可见资产，但不默认进入 Review Inbox。

异常路径：

1. 产物缺证据、低置信、重复、冲突、来源断裂、同步冲突或批量不确定。
2. AI reviewer 生成风险等级、原因、建议动作和差异说明。
3. Review Inbox 显示“为什么需要你处理”和 AI 建议。
4. 用户 approve、edit、merge、dismiss 或 retry。

## 4. AI reviewer 能力

需要新增或统一一个 AI-assisted review service，至少支持：

- SourceRef 检查：证据是否存在、能否打开、摘录是否足够。
- Duplicate 检查：是否和已有知识卡、图谱节点、复习题、记忆重复。
- Conflict 检查：是否和已有用户资产冲突。
- Risk 分类：low、medium、high、blocked。
- 建议动作：save inline、edit、merge、send to review、reject。
- 标题/标签/摘要生成：类似现有 AI 标题生成，但用于 Review 辅助。
- 审批说明：用用户能懂的话解释为什么需要处理。

## 5. 阶段计划

### P4-S1：普通保存路径审计

列出所有 AI 产物入口，确认普通路径是否已经默认 inline 保存。

验收：

- AI Chat answer -> KnowledgeCard。
- Image analysis -> KnowledgeCard。
- Selection/RAG evidence -> KnowledgeCard。
- Seminar synthesis -> KnowledgeCard / SpacedReview / ConceptGraph。
- Memory explicit save。
- ConceptGraph draft node/edge。

所有高置信普通路径都不默认写 ReviewItem。

### P4-S2：Review Inbox 定位和文案重写

把 Review Inbox 页面、空态、入口、说明改成异常中心。

验收：

- 用户能看懂 Review Inbox 是处理异常，不是普通学习入口。
- 空状态说明“没有需要处理的异常”。
- 普通保存入口不再引导用户去 Review。

### P4-S3：AI reviewer service 第一片

为知识卡和 Seminar synthesis 增加 AI 预审。

状态：In Review slice。Seminar synthesis 的异常 handoff 已有第一片：当 completed Seminar synthesis 满足可追踪异常送审条件时，AI Chat 原生任务卡会生成并渲染 `review_triage label=ai-suggestion/risk/suggested-action`，未解决分歧时提示 `建议送审：未解决分歧需要人工确认。`、`中风险` 和 `送入异常中心`；历史卡只有 message part、没有 active runtime synthesis 时，也能在 `异常` 子视图和默认 `研讨流` 中恢复 `AI 预审建议`、`AI 风险等级` 和 `建议动作`。这仍是本地规则化 triage suggestion，不是完整 LLM reviewer service，也不自动 approve。

验收：

- AI 能给出 risk、reason、suggestedAction；当前 Seminar 首片已覆盖本地规则化 `risk` 和 `suggested-action` message part。
- 无证据或冲突项进入 Review 时显示 AI 解释；当前 Seminar 首片仍不是统一 LLM reviewer service，也不覆盖重复/冲突检查。
- 高置信项仍可 inline 保存。

### P4-S4：重复和冲突合并

给 KnowledgeCard、ConceptGraph、Memory 增加重复/冲突检查。

验收：

- Review Inbox 能显示“疑似重复于哪条资产”。
- 用户可选择 merge，而不是只能 approve/dismiss。
- AI 建议不自动覆盖用户资产。

### P4-S5：批量异常处理

Review Inbox 支持按 AI 风险分组、批量确认低风险、逐条处理高风险。

验收：

- 批量 apply 只处理 traceable low-risk items。
- high-risk 必须逐条确认。
- 失败项可 retry，错误可见。

## 6. 不做事项

- 不让所有 AI 产物默认送审。
- 不让 AI 自动 approve 高风险写入。
- 不用 Review Inbox 替代当前页保存体验。
- 不把 AI reviewer 的判断写成不可追踪状态。

## 7. 更新要求

推进 P4 时必须更新：

- 本文件的入口审计和 Review 状态。
- `../implementation_status_zh.md` 的 adapter/reviewer 测试证据。
- `../04_user_facing_activation_plan_zh.md` 的保存入口。
- `../user_decision_summary_zh.md` 的 Review Inbox 用户价值说明。

## 8. 状态更新记录

- 2026-06-03：建立 P4 详细计划。当前状态为 In Progress；低负担保存已有多处切片，AI 辅助预审和异常中心表达仍需补完。
- 2026-06-04：P4-S3 / P1-S4 共享的 Seminar 异常送审 AI 预审建议首片进入 In Review：`review_triage label=ai-suggestion` 会随 completed Seminar snapshot 写入，`异常` 子视图可显示 `AI 预审建议`，历史恢复只靠 message part 也能显示。验证：`persisted Seminar chat card renders Review triage message parts` 和 `Seminar chat card sends active completed run to exception Review` 先红后绿；focused 合跑结果 `2 passed`，P1 卡片聚焦回归 `49 passed`，AI Chat Seminar 相邻回归 `89 passed`，format `0 changed`，`git diff --check` 通过。剩余缺口：还没有统一 AI reviewer service、risk 字段、重复/冲突检查或批量异常处理。
- 2026-06-05：P4-S3 / P1-S4 共享的 Seminar 异常送审 risk/suggestedAction 首片进入 In Review：`review_triage label=risk/suggested-action` 会随异常 handoff 写入并可从历史 message part 恢复，`异常` 子视图显示 `AI 风险等级`、`中风险`、`建议动作` 和 `送入异常中心`。验证：`flutter test --no-pub test/ai_chat_stream_seminar_entry_test.dart --plain-name 'persisted Seminar chat card renders Review triage message parts' -r expanded` 结果 `All tests passed`。剩余缺口：仍没有统一 LLM reviewer service、重复/冲突检查、Review Inbox risk 分组或批量异常处理。
- 2026-06-05：同一 risk/suggestedAction 首片补到默认 `研讨流`：`review_triage label=risk/suggested-action` 现在会在 AI Chat 原生线性流中显示为 `AI 风险等级 / 中风险` 和 `建议动作 / 送入异常中心`，不再把 `medium/send-to-review` 暴露成正文。验证：同一 focused 用例红绿 `All tests passed`；相邻组合里当时暴露的 completed overview 固定等待失败，已由 P1 测试等待边界切片改用 `_waitForReadySeminarCardRun(...)` 后复测通过。剩余缺口不变：仍没有统一 LLM reviewer service、重复/冲突检查、Review Inbox risk 分组或批量异常处理。
- 2026-06-05：active completed Seminar 点击 `异常送审` 的回归等待边界补齐：`Seminar chat card sends active completed run to exception Review` 不再直接 `await scopedRuntime.start(...)`，而是启动 scoped runtime 后复用 `_waitForReadySeminarCardRun(...)` 等待同 session terminal，再断言异常预览、pending ReviewItem / KnowledgeCard 和 `sent-to-review` artifact action。验证：focused `flutter test --no-pub test/ai_chat_stream_seminar_entry_test.dart --plain-name 'Seminar chat card sends active completed run to exception Review' -r expanded` 结果 `All tests passed`；异常预审/active 送审/completed overview/artifact action 相邻组合结果 `4 passed`；format `0 changed`；`git diff --check` 通过；analyzer 被 `custom_lint` pub.dev TLS plugin setup 阻塞，退出码 `4`，未返回代码级诊断。剩余缺口不变：这只是异常送审闭环测试稳定性修复，仍没有统一 LLM reviewer service、重复/冲突检查、Review Inbox risk 分组或批量异常处理。

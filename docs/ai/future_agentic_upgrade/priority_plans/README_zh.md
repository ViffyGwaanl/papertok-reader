# v7 Priority Plans

> 状态：Ready
> 最后更新：2026-06-03
> 用途：索引 v7 五个优先级的详细计划，并规定进度更新方式。

## 1. 文档结构

| 优先级 | 文档 | 目标一句话 |
| --- | --- | --- |
| P1 | `P1_ai_chat_native_seminar_zh.md` | 把 AI 研讨会重构为 AI Chat 原生运行模式。 |
| P2 | `P2_understand_anything_book_map_zh.md` | 做成 Understand-Anything 式全书 AI 理解地图。 |
| P3 | `P3_intelligent_index_retrieval_foundation_zh.md` | 补完支撑研讨会和理解地图的生产级索引/检索底座。 |
| P4 | `P4_ai_assisted_artifact_review_zh.md` | 让 AI 产物保存低负担化，Review Inbox 只处理异常，并加入 AI 预审。 |
| P5 | `P5_sync_recovery_release_zh.md` | 把新 AI 闭环做成可恢复、可同步、可测试、可发布的产品能力。 |

## 2. 状态更新协议

每个优先级文档都必须保持这些区域可用：

- 当前状态：用 `Draft`、`In Progress`、`In Review`、`Accepted`、`Blocked` 或 `Deprecated`。
- 已完成：只记录有代码、测试或文档证据的事实。
- 主要缺口：记录用户现在还不能完成的动作。
- 阶段计划：列出下一批 agent 可执行切片。
- 验收标准：写用户可见行为、测试命令和不可越界条件。
- 状态更新记录：每次推进后追加日期、变更、证据和剩余风险。

如果只改代码、不更新对应优先级文档，这个实现不能视为完整完成。五个 `P*.md` 是 v7 目标的实时执行计划；后续 agent 不能用聊天记录、临时草稿或个人上下文替代这些文件。

每次推进 P1-P5 中任一切片时，按下面顺序维护进度：

1. 更新对应 `P*.md` 的阶段状态，说明该阶段是 `Draft`、`In Progress`、`In Review`、`Accepted` 还是 `Blocked`。
2. 在对应 `P*.md` 的状态更新记录里追加一条记录，包含用户可见变化、代码 artifact、测试命令和剩余缺口。
3. 在 `../implementation_status_zh.md` 追加验证 ledger，记录实际命令和结果。
4. 如果入口、可用性、产品边界或用户价值变化，同步更新 `../04_user_facing_activation_plan_zh.md`、`../user_decision_summary_zh.md` 和 `../README_zh.md`。
5. 如果优先级或目标本身变化，同步更新 `../06_v7_goal_and_priority_plan_index_zh.md`。

`P*.md` 是实时状态文件，不是一次性规划稿。旧记录保留，新记录追加；如果旧判断被代码事实推翻，用新的状态记录说明原因，不直接抹掉历史。

## 3. 和其他文档的关系

`../06_v7_goal_and_priority_plan_index_zh.md` 是当前目标入口。

`../implementation_status_zh.md` 记录实际实现证据和验证命令。

`../04_user_facing_activation_plan_zh.md` 记录用户入口和可走通路径。

`../user_decision_summary_zh.md` 记录面向用户价值的取舍和边界。

`../epics/` 和 `../gates/` 仍是更细的工程规格和质量 gate；如果 v7 计划和旧 epic 冲突，以 v7 计划为当前目标，但必须同步修正文档，不能让冲突长期存在。

## 4. 当前推进顺序

第一顺位先做 P1。AI Chat 原生研讨会是所有后续 AI 工作流的主入口。

第二顺位做 P2，但 P2 的第一阶段可以和 P3 并行：先定义 AI semantic graph builder schema 和只读预览，再逐步接检索、索引、导读路径和图谱 UI。

P3 是 P1 和 P2 的底座，优先补阻塞用户体验的 readiness、修复、进度可见和移动端资源 gate。

P4 在 P1/P2 产物开始增多时同步推进，避免所有 AI 产物继续堆进 Review Inbox。

P5 贯穿全程，但不抢 P1/P2 的用户可见闭环；每个阶段进入发布前再集中收口。

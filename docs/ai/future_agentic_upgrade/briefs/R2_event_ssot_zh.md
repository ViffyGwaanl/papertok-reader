# R2 Brief — 事件流单一数据源(SSOT)

> 前置:R1 完成(小文件让本任务的读写成本可控)。
> DoD:Seminar 卡 UI 的全部状态只从 `AgentRunGraphStore` 事件 replay(经 adapter)渲染;runtime snapshot 双写路径与所有"兼容 fallback"读取路径被删除;一次性迁移(或经用户确认直接放弃旧运行历史)落地;相关测试改写为事件驱动。
> 最后更新:2026-06-11

## 问题

当前每个功能要写四遍:runtime snapshot、graph event、adapter replay、UI part + 旧字段 fallback。这是 P1 期间"改一个小显示也要一整个切片"的直接原因。事件层(`agent_run_graph_store.dart` + `agent_run_event_message_part_adapter.dart`)已经能承载全部信息,旧 snapshot 层只剩历史惯性。

## 决策

1. `AgentRunGraphStore` 事件流是唯一 source of truth;`messageParts` 是它的派生缓存,只能由 adapter 生成。
2. 删除 UI 里所有 `旧 snapshot.* 只作为兼容 fallback` 的读取分支。
3. 旧数据:写一次性迁移(读旧 snapshot → 合成事件 → 写 graph store →标记已迁移),或经用户确认后直接放弃旧研讨历史(预发布产品,倾向后者,需用户拍板)。
4. 迁移完成后删除 snapshot 写入路径和对应模型字段。

## 第一个 session 的产出:删除清单 ADR

用以下 grep 起步,产出 `briefs/R2_DELETE_LIST_zh.md`(文件+行号+处置:删/迁/留):

```bash
grep -rn "snapshot\.toolCalls\|snapshot\.evidence\|兼容\|fallback" lib/widgets/ai/ lib/providers/ai_seminar_runtime.dart
grep -rn "messageParts" lib/providers/ai_seminar_runtime.dart lib/service/ai/ | grep -v test
grep -rn "AgentRunEvent" lib/service/ai/ --include=*.dart -l
```

## 执行批次

- 批次 1:删除清单 ADR + 用户拍板迁移 vs 放弃旧历史。
- 批次 2..N:每 session 删一族 fallback(toolCalls → evidence → role/synthesis → artifact actions → checkpoint),同批改写对应测试为"喂事件 → 断言 UI"。
- 最后一批:删 snapshot 写入路径与模型冗余字段,跑全量 Seminar 测试。

## 验证

```bash
flutter analyze && flutter test test/widgets/ai/seminar/ test/providers/ai_seminar_runtime_test.dart test/service/ai/
bash tool/check_repo_budgets.sh
```

## 红线

- 删除即删除,禁止"先留着以防万一"。git 历史就是后悔药。
- 本任务不加任何新功能。

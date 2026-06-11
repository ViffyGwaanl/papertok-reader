# 状态表(唯一)

> 规则:每个切片只改本表对应行;状态只有 backlog / in progress / 待真机验收 / done;done 只能由用户标。
> 最后更新:2026-06-11

| 任务 | 内容 | 状态 | 下一步 | 验收/Brief |
| --- | --- | --- | --- | --- |
| P1 | AI Chat 原生研讨会(MVP 闭环) | 待真机验收 | 用户按 10 步脚本真机走一遍,失败项回报 | `briefs/P1_ACCEPTANCE_zh.md` |
| R1 | 拆分 ai_chat_stream.dart god file | backlog | P1 验收后立即开始,先做结构地图批次 | `briefs/R1_godfile_split_zh.md` |
| R2 | 事件流单一数据源,删 snapshot 双写与 fallback | backlog | R1 后;第一批产出删除清单 ADR | `briefs/R2_event_ssot_zh.md` |
| R3 | Seminar 并入 sub-agent 平台(原 P1.5/S7) | backlog | R2 后;自由工具 loop、统一 streaming 组件在此实现 | `briefs/R3_agent_platform_merge_zh.md` |
| P2 | Understand-Anything 式全书 AI 理解地图 | backlog | R1–R3 完成后,开工前重写 brief | 旧版 `priority_plans/P2_*.md` 仅作参考 |
| P3 | 智能索引/语义检索/ANN 底座 | backlog(暂停) | 生产级 ANN 打包、恢复式构建并入 R2 之后评估 | `priority_plans/P3_*.md` |
| P4 | AI 辅助产物保存与 Review 异常中心 | backlog(暂停) | 内联保存已可用;AI 预审并入 P2 之后评估 | `priority_plans/P4_*.md` |
| P5 | 同步/恢复/测试/发布 | in progress(按发布节奏) | 每次 release 跟随既有 SOP | `docs/SOP_RELEASE_AUTOMATION_zh.md` |

## P1 已知缺口(已明确移出 P1,归 R3)

- 角色自由多轮工具调用 loop。
- 与普通 AI Chat 统一的 streaming tool-call 组件。
- 旧 provider stream 原地续传:**明确不做**(决策于 2026-06,见 archive)。

## 真机验收记录

| 日期 | 任务 | 结果 | 失败项 |
| --- | --- | --- | --- |
| (待填) | P1 | | |

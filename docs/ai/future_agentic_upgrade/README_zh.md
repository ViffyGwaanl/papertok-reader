# v7 Agentic Upgrade — 总入口

> 最后更新:2026-06-11
> 本目录于 2026-06-11 做过一次文档破产重组:旧的巨型计划/状态文档全部移入 `archive/2026-06-11/`,被本文 + `STATUS_zh.md` + `briefs/` 取代。任何 agent 不得恢复旧文档体系。

## 持续目标(不变)

把 PaperTok Reader 从"阅读器 + 若干 AI 功能页"升级为:以 AI Chat 为原生入口、以书内证据为边界、以 Understand-Anything 式全书 AI 理解地图为核心差异化的深度阅读应用。所有 AI 结论必须可追溯到书内证据(SourceRef);普通高置信产物在当前上下文内联保存,Review Inbox 只处理异常。

## 文档地图(开工必读 = 前三个,合计 ≤10K token)

| 文件 | 用途 |
| --- | --- |
| `AGENT_PROTOCOL_zh.md` | 所有 agent 的工作契约(切片、状态、文档、验证规则) |
| `PLANNER_LOOP_zh.md` | 规划者(Claude)角色契约:三方分工、每轮工作流、判断原则 |
| `STATUS_zh.md` | 唯一状态表,P/R/B/E 各任务真实进度 |
| `EXPERIENCE_REBUILD_PLAN_zh.md` | 体验重建期(2026-07)总控:A/B/C 三线映射、顺序、冻结规则 |
| `GROWTH_PLAN_zh.md` | 增长计划(G 线,重建期后):传播/留存/获客六赌注与顺序 |
| `briefs/<当前任务>_zh.md` | 当前任务的一页 brief |
| `briefs/P1_ACCEPTANCE_zh.md` | P1 十步真机验收脚本 |
| `priority_plans/P2..P5_*.md` | 后续优先级的简版计划(开工前按协议重写为 brief) |
| `00/01/02/03/05_*.md` | 北极星、能力地图等背景文档(小文件,按需读) |
| `archive/` | 历史文档,只读,不更新,不必读 |

## 当前优先级顺序

1. **P1 收口**:用户按 `briefs/P1_ACCEPTANCE_zh.md` 真机验收,通过即标 done。
2. **R1 → P6 → R2 → R3 架构清债 + 对话树**(见 `briefs/*.md`):拆 god file;**R1 后插入 P6(AI Chat 多分支对话树状可视化,用户 2026-06-17 拍板前移)**;再做事件流单一数据源、Seminar 并入 sub-agent 平台。R3 完成 = 旧 P1.5(自由工具 loop、统一 streaming 组件)的地基就位。
3. **P2 Understand-Anything 图谱**:R1–R3 完成后启动,开工前重写 brief。
4. P3(ANN 底座)、P4(Review 异常中心)残余切片并入 R2/P2 顺带完成;P5(发布)按发布节奏走。

## 三条铁律(详见协议)

1. 状态只有 4 档:backlog / in progress / 待真机验收 / done;只有用户能标 done。
2. 每个切片只更新 `STATUS_zh.md` 一行 + commit message;禁止任何"最新进展"叙事段。
3. `tool/check_repo_budgets.sh` 必须通过(文档 ≤30KB,代码文件行数 ratchet)。

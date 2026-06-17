# R1 Brief — 拆分 ai_chat_stream.dart

> 前置:P1 真机验收通过。DoD:`ai_chat_stream.dart` ≤3000 行,Seminar UI 全部位于 `lib/widgets/ai/seminar/`,每文件 ≤1000 行;`flutter analyze` 0 error;Seminar 相关测试全绿且按视图拆分。
> 最后更新:2026-06-11

## 现状(为什么难)

- `lib/widgets/ai/ai_chat_stream.dart` 约 17000 行,其中 `AiChatStreamState` 单类约 16000 行(780–16816),含 2243 处 Seminar 引用。
- 对应 `test/ai_chat_stream_seminar_entry_test.dart` 约 19800 行。
- 这是所有后续工作(R2/R3/P2)成本高的根因:任何 agent 读不完、改不安全、测得慢。

## 策略:抽 builder 成无状态视图,不是搬类

巨型 State 类无法整类搬移。做法:每个 `_buildSeminarXxx(...)` 方法 → `lib/widgets/ai/seminar/seminar_xxx_view.dart` 的 `SeminarXxxView`(StatelessWidget),**所有依赖通过构造参数和回调显式传入**,不引用 State 私有字段。State 类里原方法体替换为对新 widget 的调用。

## 批次

- 批次 0(地图,半个 session):`grep -n "Widget _build" lib/widgets/ai/ai_chat_stream.dart` 全列,按 Seminar 子视图分组,把分组结果追加到本文件"批次清单"节,作为后续唯一依据。
- 批次 1(零风险热身):把文件内已独立的小类搬出:`_SeminarRunSetupSheet`/`_SeminarRunRoleProfileTile`/`_SeminarRunEvidenceScopeChip`(75–686 行段)→ `seminar/setup/`;文件尾部杂类(16816 起)→ 各自归位。
- 批次 2..N(每 session 1–3 个视图):按依赖从浅到深抽:tool call 块 → evidence 块 → role turn/partial 块 → synthesis/disagreement 块 → reader composer/reader turn 块 → artifact actions 块 → checkpoint/恢复块 → run setup 卡 → 卡片骨架。
- 每批次同步拆测试:该视图的用例移到 `test/widgets/ai/seminar/<view>_test.dart`,改为直接 pump 新 widget(不再 pump 整个 AiChatStream),长轮询 live-signal 用例降级为构造参数驱动的同步用例。

## 每批次验证(必须全过才算完)

```bash
flutter analyze
flutter test test/widgets/ai/seminar/ test/ai_chat_stream_seminar_entry_test.dart
bash tool/check_repo_budgets.sh
```

## 红线

- 纯机械移动 + 显式化依赖,**禁止顺手改行为/改文案/加功能**。
- 新文件一律 `pointer_interceptor` 等既有约定照旧;l10n 引用方式不变。
- 每批次一个 commit:`refactor(ai-chat): extract Seminar <view> view (R1 batch N)`。

## 拆分完成后的独立小增强(backlog,不在机械拆分内)

- 双击 `AI 对话` 标题栏一键回到顶部(与现有"回到底部"悬浮键对称)。等聊天头部拆为独立 widget 后,作为单独一个 `feat` 切片做,不混进任何 R1 机械搬移 commit。来源:P1 六轮用户请求(2026-06-15)。

## 批次清单(结构地图 + 执行顺序,规划者 2026-06-17 产出 = 原批次 0)

> Seminar UI 全部在 `ai_chat_stream.dart` 6368–15578 行,约 9200 行、约 50 个方法。`_buildSeminarRunSnapshot`(8813–15578,~6766 行)是吞文件的巨兽,其子渲染器以 `_seminarSnapshot*` 命名(非 `_build`)。
> 顺序原则:**叶子/共享件先抽,组合件后抽,快照编排器与卡片骨架最后**。每抽一个,快照里的调用点由 `_seminarSnapshotXxx(...)` 换成 `SeminarXxxView(...)`,god file 渐缩。
> 冻结层注记:reader composer / agent input composer / director cue 等仍被快照为历史会话渲染(9067/10659/12970 等有调用),是**活代码**——R1 只机械搬移、保持行为,**禁止当死代码删**(删=改行为)。死代码清理另案,不在 R1。

| 批次 | 目标目录/文件 | 方法(起始行) |
| --- | --- | --- |
| 1 共享叶子 | `seminar/shared/` | _seminarSnapshotHeading(11385)、_seminarSnapshotMissingSourceChip(11376)、_seminarSnapshotLabeledTinyChip(12849)、_seminarSnapshotLabelText(12863)、_seminarSnapshotDetailLabel(14609)、_seminarSnapshotTinyChip(15341)、_seminarMetaChip(15461)、_seminarMetaChips(15401)、_seminarExpandableText(13971) |
| 2 证据 | `seminar/evidence/` | _seminarSnapshotEvidenceTile(12061)、_seminarEvidenceReferenceChips(12198)、_seminarSnapshotCompactEvidenceRows(11318)、_seminarSnapshotCompactEvidenceRow(11338) |
| 3 工具调用 | `seminar/tools/` | _seminarSnapshotToolCallTile(11459)、_seminarToolCallAction(11940)、_seminarSnapshotAgentTraceRows(11405) |
| 4 角色发言 | `seminar/roles/` | _seminarSnapshotRoleTile(12267)、_seminarSnapshotDiscussionTimeline(12319)、_seminarSnapshotRolePartialTile(12357)、_seminarSnapshotLiveRoleTile(12429)、_seminarSnapshotTimelineTurn(13986)、_seminarSnapshotAgentStatusTile(12985) |
| 5 分歧 | `seminar/disagreement/` | _seminarSnapshotDisagreementDetails(14072)、_seminarSnapshotContradictionScanTiles(14149)、_seminarSnapshotContradictionScanOverviewTile(14300)、_seminarSnapshotContradictionGapSummaryTile(14383)、_seminarSnapshotDisagreementRebuttalTiles(14485) |
| 6 白板/总结/Review | `seminar/whiteboard/` | _seminarSnapshotWhiteboardSection(14635)、_seminarSnapshotWhiteboardGroup(15272)、_seminarSnapshotReviewPreview(14672)、_seminarSnapshotReviewItems(15166)、_seminarSnapshotReviewLine(15250) |
| 7 时间线消息部件 | `seminar/timeline/` | _seminarSnapshotNativeTimeline(10494)、_seminarSnapshotNativeTimelinePart(10581)、_seminarSnapshotReviewTriagePartTile(10707)、_seminarSnapshotArtifactActionsPartTile(10780)、_seminarSnapshotRunSetupPartTile(11129)、_seminarSnapshotNativeTextPartTile(11219) |
| 8 冻结参与层(活代码,原样搬) | `seminar/participation/` | _seminarSnapshotReaderTurnTile(12500)、_seminarSnapshotReaderComposerTile(12675)、_seminarSnapshotDirectorCueTile(12875)、_seminarAgentControlAction(13164)+其 label/icon/executable 辅助(13245/13289/13878)、_seminarAgentInputComposer(13313) |
| 9 设置+控制+resume | `seminar/setup/` | _buildSeminarRunCardSetup(6736)+4 字段(6951/7132/7252/7364)、_buildSeminarRunCardStartAction(7540)、_seminarRunCardHeaderControls(7578)、_buildSeminarRunCardCancelAction(7614)、resume 三件(7645/7774/7846) |
| 10 快照编排器+tabs(最后) | `seminar/snapshot/` | _buildSeminarRunSnapshot(8813)、_seminarSnapshotSubviewTabs(9799) |
| 11 卡片骨架(最外层) | `seminar/` | _buildSeminarRunCard(6368)、_buildSeminarRunCardIgnoredActionsNotice(6694)、_buildSeminarRunCardFollowUpHint(8052) |

> 8052–8813 间夹有若干非 Widget 辅助(字符串/判定),随所属视图搬迁。批次 1–8 为低风险机械抽取(叶子+中层),批次 9–11 风险递增(尤其 10 的 6766 行巨兽),需规划者审过 1–8 再放行。每批一个 commit:`refactor(ai-chat): extract Seminar <view> view (R1 batch N)`。

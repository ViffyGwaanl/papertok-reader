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

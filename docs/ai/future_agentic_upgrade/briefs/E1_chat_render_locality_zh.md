# E1 Brief — AI Chat 流式渲染局部化

> 前置:R2 完成(单一事件流,fallback 已删)。后继:R3(统一 streaming 组件落在本任务架构上)。
> DoD:流式生成期间,重建范围收敛到"正在生成的那条消息"——历史消息、输入框、AppBar 零重建;rebuild 探针 widget test 通过;真机长回答/长研讨全程无跳动、输入框打字不卡;god file 净变短。
> 最后更新:2026-07-03

## 问题(证据)

- `lib/widgets/ai/ai_chat_stream.dart` 11700 行,`AiChatStreamState`(行 374 起)一个 State 类承载整页;`setState` 84 处、`ref.watch/read` 83 处。
- `lib/providers/ai_chat.dart`(5169 行)`AiChat extends _$AiChat`,状态 = `AsyncData<List<ChatMessage>>` **整表替换**(见行 131/691/771 等)。流式期间每次内容追加都替换整个 List → 所有 watcher 整页 rebuild。
- 后果:P1 验收 20 个缺陷里 5 个是抖动/闪烁/卡顿(F1/F4/F9/F17/F20),每次靠局部补丁压制,源头从未处理。
- 消息列表渲染点:god file 行 1430、2011(`ListView.separated`)、5208(`ListView.builder`)。

## 目标形态(一段话)

每条消息是一个独立 widget,只订阅自己的数据;流式生成的"活跃尾部"走独立的细粒度通道(不经过整表 List 替换);列表容器只在消息增删时重建。生成 100 个流式事件,非活跃消息 build 次数 ≤1。

## 执行批次

1. **探针与基准(先测量后动刀)**:写 rebuild 计数探针(debug-only,或 widget test 内用 build 计数 wrapper);建立断言测试:向 provider 喂 N 条消息 + 对末条喂 100 次流式追加,断言非活跃消息 build ≤1(此测试现状必然红,作为 E1 的靶子)。新文件 `test/widgets/ai/chat_render_locality_test.dart`;pump 全页的 harness 模式抄现成的 `test/ai_chat_stream_*_test.dart`(已有 5 个测试在 pump `AiChatStream`,provider override 方式照搬)。
2. **ADR(要点列表,≤1 页,进本文件末尾附录,不新建文档)**:二选一并给依据——(a) 保持整表 state,消息条目用 `select` + 稳定对象标识做局部订阅(前提:流式追加时未受影响的 `ChatMessage` 对象引用不变,需实测);(b) 活跃尾部隔离:生成中的消息由独立小 provider(如 `StreamProvider`/`ValueNotifier`)驱动专用 widget,完成后一次性并入整表。倾向 (b),以探针测试结果定夺。
3. **消息条目组件化**:每条消息抽为独立 widget,新目录 `lib/widgets/ai/chat_message/`(每文件 ≤1500 行);god file 内对应内联构建代码删除(ratchet 硬上限 16620,现 11700;本任务性质是抽取,god file 必须逐批净减)。分多个子批次,每批一族消息类型(文本 / 工具块 / seminar 卡挂载点 / 图片)。seminar 卡只改挂载与订阅方式,内部逻辑与 83 个既有测试不动。
4. **流式通道落地**:按 ADR 实现活跃尾部通道;`AiChat` 整表替换只发生在消息完成/增删时。provider 测试:流式期间整表 state 不变更(或引用稳定)。**硬约束:`lib/providers/ai_chat.dart` 在 ratchet 白名单的余量只有 1 行(baseline 5170 / 现 5169)——新 provider 逻辑一律进新文件**(如 `lib/providers/ai_chat_stream_tail.dart`),ai_chat.dart 只许改既有行或做净删;新 provider 记得跑 codegen 并提交 `.g.dart`。
5. **setState 清理**:god file 剩余 84 处 setState 归类(输入框/滚动/消息/杂项),消息相关的随批次 3–4 迁走;滚动相关确认与 `seminar_autoscroll_policy.dart` 不冲突。
6. **收尾**:批次 1 的靶子测试转绿;真机验收。

## 验收(真机,用户执行)

1. 发起一次长回答(千字级),生成全程:页面无跳动/闪烁,输入框可流畅打字,历史消息区不闪。
2. 发起一次完整研讨,同上;各 seminar 卡功能与 P1 十步脚本抽查(展开/证据/回底按钮)无回归。
3. 生成中切走 tab 再切回,流式继续且不整页闪白。
4. `flutter test` 全绿(含新增探针测试、既有 83 个 seminar 测试)。

## 红线

- 不改 `ChatMessage` 持久化格式与 `conversationV2` 树持久化。
- 不动 `lib/widgets/ai/seminar/` 内部逻辑、不动 `book.js`、不动数据库。
- 禁止保留新旧两条渲染路径"以防万一"——替换即删旧,git 是后悔药。
- 本任务不加任何新功能、不改视觉样式(样式问题记 STATUS backlog)。

## 验证命令

```bash
dart run build_runner build --delete-conflicting-outputs   # 动 provider 的批次
flutter analyze
flutter test test/widgets/ai/chat_render_locality_test.dart test/widgets/ai/ test/ai_chat_stream_seminar_entry_test.dart
bash tool/check_repo_budgets.sh
```

commit 格式:`refactor(ai-chat): <批次内容> (E1 batch N)`

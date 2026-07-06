# E3 Brief — 全局糙感清扫

> 前置:无。立刻可开工,与所有线并行;各批次相互独立,可乱序、可单独验收。
> DoD:中文界面零漏翻;用户可见错误全部人话化;双击标题回顶落地;PaperTok 首屏单次请求;真机抽查通过。
> 最后更新:2026-07-03

## 批次 1 — zh 漏翻 372 条

- 现状:`docs/untranslated_messages.txt`(由 `flutter gen-l10n` 自动生成,见 `l10n.yaml` 的 `untranslated-messages-file`)zh 列表 372 个 key,覆盖备份加密、阅读页样式、全文翻译、记忆等高频界面。
- 做法:对照 `lib/l10n/app_en.arb` 补齐 `lib/l10n/app_zh.arb` 全部缺失 key。译名跟随既有 zh ARB 术语(研讨、知识卡、记忆、证据等);占位符(`{value}` 等)原样保留。只改 `app_zh.arb`,不改 dart。
- 验证:`flutter gen-l10n` 后 `python3 -c "import json;d=json.load(open('docs/untranslated_messages.txt'));print(len(d.get('zh',[])))"` 输出 `0`;`flutter analyze` 无新增。
- commit:`fix(l10n): fill missing zh translations (E3 batch 1)`

## 批次 2 — 裸错误文案人话化

- 现状:`lib/page/` + `lib/widgets/` 共 71 处 `e.toString()`,不少直接进 SnackBar/Dialog/页面正文(如 `papers_page.dart` 行 511 把异常原文当正文渲染)。
- 做法:逐处分类三档——(a) 用户可见提示:换 ARB 人话(说清发生了什么+能做什么,如"加载失败,检查网络后重试"),原始异常转入既有日志通道;(b) 诊断/日志页(`log_page.dart`、`share_inbox_diagnostics_page.dart` 等)**保留原文,不改**;(c) 纯内部(assert/debug):不改。分类清单(文件+行+档位)写进 commit message body,不新建文档。
- 可拆 2–3 个子 commit(按目录),每个都可独立验收。
- 验证:`grep -rn "e\.toString()" lib/page lib/widgets` 剩余项全部属于 (b)/(c) 档;真机断网操作书架/PaperTok/AI 设置,所见报错均为人话。
- commit:`fix(ux): humanize user-facing error messages <目录> (E3 batch 2.x)`

## 批次 3 — 双击标题回顶(AI Chat)

- 来源:P1 六轮用户请求(2026-06-15),原挂 R1 brief 行 40,R1 收口后无人认领,本批次承接。
- 现状:god file `ai_chat_stream.dart` 行 ~5541 `AppBar`;已有"回到底部"悬浮键,本功能与其对称。
- 做法:滚动控制逻辑放新文件 `lib/widgets/ai/chat_scroll_to_top.dart`(双击手势 wrapper + 动画滚顶,复用现有聊天 ScrollController);god file 只在 AppBar title 处加挂钩。ratchet 事实:god file 硬上限 16620、现 11700,有余量;但按协议惯例本批净增控制在 ≤5 行(包一层手势足够)。
- 验证:真机双击 AI Chat 标题,平滑滚到顶;长按/单击标题原行为不变;`flutter test` 全绿。
- commit:`feat(ai-chat): double-tap title scrolls to top (E3 batch 3)`

## 批次 4 — PaperTok 首屏与错误体验

- 现状:`lib/page/home_page/papers_page.dart` `_loadMore`(行 93–165):`latest` 每次 reset 先探测拉 50 条('all')求最新日期,再按日期正式拉 20 条 → 首屏两次网络往返;失败时 `_error = e.toString()` 裸展示(行 499–511)。
- 做法:① 探测结果直接复用——从 50 条探测结果中过滤出 maxDay 当日卡片直接填充首屏(不足 20 再补一次拉取,通常可省一次往返);② 错误态换人话 + 保留/补上"重试"按钮(接 `_loadMore(reset: true)`);③ 错误文案进 ARB(en+zh)。**不加缓存层、不改 API 客户端(`papertok_api.dart`)接口**。
- 验证:代码审查确认 latest 首屏常规路径单次请求;真机断网进 PaperTok tab,看到人话错误 + 重试可用;恢复网络重试成功。
- commit:`fix(papertok): single-fetch first paint + humane error state (E3 batch 4)`

## 批次 5 — E0 真机走查承接(占位)

- 用户 30 分钟真机走五条主干(开书阅读+翻译 / AI Chat / PaperTok / 搜索 / 记忆),每个别扭点一行记入 STATUS 的 E3 行"下一步"或口头交规划者;由规划者转成 5.x 子批次追加到本节。**执行 agent 不得自行发明批次 5 内容。**

## 红线(全批次)

- 不动 `book.js`、数据库 schema、`lib/service/ai/`、`lib/providers/ai_chat.dart`。
- 不改视觉风格/主题/布局(错误态的文案与按钮除外)。
- 每批收尾:`flutter analyze` 无新增 + `flutter test` + `bash tool/check_repo_budgets.sh`。

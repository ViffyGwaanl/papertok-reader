# E2 Brief — 阅读翻译体验简化

> 前置:无(可与 A 线并行,但不得触碰 `lib/widgets/ai/`、`lib/providers/ai_chat*.dart`、`lib/service/ai/`)。
> DoD:全文翻译"开了就翻、坏了自动重试、只在需要用户行动时说一句人话";阅读设置主面不再出现并发/重试统计/失败原因等工程仪表;真机验收(§验收)通过。
> 最后更新:2026-07-03

## 问题(证据)

- 阅读页翻译设置(`lib/widgets/reading_page/more_settings/reading_settings.dart`)向用户暴露:并发数(`readingPageTranslateConcurrencyValue`:"Concurrency: {value}")、翻译进度 HUD 开关、手动重试、上次重试统计(`readingPageTranslateLastRetryStats`)、失败原因分类(`readingPageTranslateFailureReasons` / `...ReasonRateLimit` / `...ReasonAuth` / `...ReasonNotConfigured` / `...ReasonUntranslated`)。这是调试台,不是阅读器设置。
- 失败恢复依赖用户手动点重试(`readingPageRetryTranslation`);限流/瞬时网络错误本应自动恢复。
- 运行时:`lib/service/translate/fulltext_translate_runtime.dart`;引擎:`lib/service/translate/`(12 文件,共 2156 行,deepl/google/microsoft/ai 多引擎)。
- 相关 prefs 在 `lib/config/shared_preference_provider.dart`,且被 `lib/service/sync/ai_settings_sync.dart` 同步 → **key 不可删、不可改名**。

## 目标形态(一段话)

用户只做一个决定:开/关全文翻译(+选引擎/目标语言,已有)。失败分两类:可自愈的(限流、瞬时网络)由 runtime 自动退避重试,过程静默;需用户行动的(未配置、鉴权失败)弹一条人话提示 + 一个直达按钮(去设置/重试),不出现错误码和统计数字。

## 执行批次

1. **自动重试**:`fulltext_translate_runtime.dart` 内失败项按类型处理——rate-limit:指数退避自动重试(上限可硬编码,如 5 次、初始 2s);瞬时网络:同上短退避;auth / not-configured:不重试,标记"需用户行动";untranslated 残留:整轮结束后自动补跑一轮。单测:各失败类型的重试/不重试行为,放新目录 `test/service/translate/`(现不存在,新建)。
2. **提示人话化**:失败原因 → 用户语言映射(新 ARB key,en+zh 同批);"需用户行动"时在阅读页出一条安静的横幅/Snackbar:一句话 + 一个按钮(`去设置` 或 `重试`);自动重试过程不打扰用户。删除面向用户的重试统计文案展示(统计可保留在日志)。
3. **设置面收纳**:并发滑块、HUD 开关、重试统计、失败原因明细从阅读设置主面移入折叠的"高级"区(或移除展示,倾向移除,批次内先做折叠、经用户真机看过再定删);**prefs key 与 runtime 读取逻辑不动**,只动 UI 层。
4. **选区菜单一致性**:阅读页选区菜单中 高亮/复制/翻译/AI 研讨/知识卡 的排序与措辞统一审查,一次 commit 只调文案与顺序(ARB + 菜单构建处),**不改任何行为、不动 `book.js`**。

## 验收(真机,用户执行)

1. 开全文翻译 → 开飞行模式几秒 → 关闭:翻译自动恢复补齐,全程无需手点重试。
2. 故意填错 API key:出现一条人话提示 + 直达设置按钮;修好后翻译继续。
3. 阅读设置主面板看不到"并发/Concurrency"、重试统计、失败原因分类。
4. 选区菜单各动作措辞一致、顺序合理(用户主观认可)。
5. 正常翻译路径(中英互译、切换引擎)无回归。

## 红线

- 不改翻译引擎协议与请求格式(`deepl.dart` / `google_api.dart` / `microsoft_api.dart` / `ai.dart` / `ai_fulltext.dart`)。
- 不删/不改名任何 prefs key(`ai_settings_sync.dart` 依赖)。
- 不动 `assets/foliate-js/`、不动缓存格式(`fulltext_translate_cache.dart` 的存储结构)。
- 不加新设置项;本任务是做减法。

## 验证命令

```bash
flutter analyze
flutter test test/service/translate/
flutter gen-l10n && python3 -c "import json;d=json.load(open('docs/untranslated_messages.txt'));print('zh missing:',len(d.get('zh',[])))"
bash tool/check_repo_budgets.sh
```

commit 格式:`feat(translate-ux): <批次内容> (E2 batch N)`(批次 3/4 用 `refactor`/`chore` 视性质)

## Scope
吸收上游 `Anxcye/anx-reader`（v1.12.0..v1.14.0 范围内）**Phase A（低风险）+ Phase B（中风险）**的可复用改动；明确不包含 Phase C（AI/chat 主干、翻译后端大迁移等）。

> 说明：此 PR 为「只含 A+B 的干净分支」，不夹带 App Store 文档提交。

---

## Phase A（低风险，高收益）
- 阅读器崩溃修复：read theme 颜色为空/非法导致 RangeError
- TOC：长章节标题换行显示（wrap），不再省略号截断
- EPUB 图片溢出修复（列宽/分页布局）
- i18n：系统 locale 不支持时 fallback 到英文
- Android 10+ 保存图片：移除不必要的存储权限

---

## Phase B（中风险，挑点吸收，不整包搬）
### Reader 背景图
- 背景图 **Blur / Opacity** 控制（仅作用于背景层）
- 背景图 **Fit mode：Cover / Stretch**

### Header / Footer section styling
- `ReadingInfo` 升级为 header/footer section（left/center/right + vertical/left/right margin + fontSize）
- Prefs 兼容迁移旧结构（旧 headerLeft/footerRight + pageHeader/pageFooter margin -> section.verticalMargin）
- 阅读页渲染按 section margin/fontSize 生效（保留你 fork 的“章节进度点击→AI chat”交互）
- 设置页提供 section 的边距/字体大小调节项

### TTS（只吸收低风险修复增强）
- 修复 SystemTts 首句为空导致的 crash
- 阅读页 TTS 快捷控制 FAB（播放时 prev/pause/next/stop）

---

## Extra（修复一个潜在缺口）
- `InlineFullTextTranslateEngine` 使用的 JSON blocks prompt helper：补齐 `generatePromptTranslateFulltextBlocksJson(...)`（避免编译/运行缺口）

---

## Verification
已跑通最小回归单测：
- `test/service/shortcuts/papertok_shortcuts_pending_queue_test.dart`
- `test/providers/ai_chat_new_conversation_test.dart`

建议合入后手工 QA（10 分钟版）：
1. 打开任意 EPUB：不崩、图片不溢出
2. TOC：长章节名可换行
3. 背景图：无/有背景图都正常；blur/opacity/fit 即时生效并持久化
4. Header/Footer：调整 margin/fontSize 即时生效并持久化
5. TTS：系统 TTS 朗读不崩；菜单隐藏时右下角 FAB 出现且可控

---

## Rollback
此 PR 内改动按功能拆成多个 commit，可按模块逐个 revert：
- bgimg（blur/opacity / fit）
- header/footer section styling
- SystemTts crash fix / TTS FAB
- 其余 Phase A 稳定性修复

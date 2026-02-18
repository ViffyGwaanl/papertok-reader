# 上游贡献指南（Anx Reader）

本文档说明如何把 papertok-reader 中的 **AI + 翻译** 通用能力贡献到上游：`Anxcye/anx-reader`（base 分支：`develop`）。

## 1. 上游/分支
- Upstream：`Anxcye/anx-reader`
- Base：`develop`
- Fork：`ViffyGwaanl/anx-reader`
- Contrib 基线：`contrib/ai-translate`

## 2. 当前上游入口 PR
- Draft PR：`Anxcye/anx-reader#780`
  - Head：`ViffyGwaanl:contrib/ai-translate`
  - 内容：AI 对话 + 翻译（明确排除 PaperTok）

链接： https://github.com/Anxcye/anx-reader/pull/780

## 3. PR 拆分策略（当维护者要求拆分时）

因为上游仓库通常不允许我们创建中间 base 分支来做“堆叠 PR”，因此更推荐：
- 每个 PR 都直接 base 到 `upstream/develop`
- 在本地从 `contrib/ai-translate` 按模块 cherry-pick 到独立分支

建议拆分顺序（可按维护者反馈调整）：
1) Provider Center（元数据 + UI + models fetch/cache）
2) Chat UX（provider/model switch、thinking 档位、sections 展示策略）
3) OpenAI Responses provider（/v1/responses 专用实现 + tests）
4) Conversation tree v2（edit/regen、variants、rollback）
5) WebDAV AI settings sync（不含 api_key）
6) EPUB inline 全文翻译（HUD、可靠性、缓存、并发、失败原因）

## 4. 质量门槛（每个 PR 必跑）
```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

## 5. 范围约束（硬规则）
- 任何 PR 不得包含 PaperTok/Papers Tab：
  - `lib/service/papertok/**`
  - `lib/page/home_page/papers_page.dart`
  - `lib/page/papers/**`
  - `docs/papertok/**`
  - 以及 home tabs mandatory papers 等发行版策略

原因：PaperTok 属于产品化入口，容易降低上游接受度。

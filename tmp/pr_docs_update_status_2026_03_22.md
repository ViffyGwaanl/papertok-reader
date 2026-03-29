更新文档以反映最近一轮交付（上游 v1.14 Phase A+B 吸收 + TF 1.68.5(6376)）以及后续计划。

## 更新点
- `docs/engineering/PROJECT_STATUS_AND_PLAN_zh.md`
  - 更新时间更新为 2026-03-22
  - 新增：上游吸收 Phase A+B 交付记录（PR #7 / TF 6376）
  - Remaining 增补：上游吸收后续（合并后回归/可选 alignment 保留/TTS 增强拆分）

- `docs/engineering/ROADMAP_zh.md`
  - 新增：阅读器质量提升（上游 v1.14 Phase A+B）条目
  - 构建/发布回归处标注当前回归包 TF 6376

- `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md`
  - 更新“当前发布候选”到 2026-03-22
  - 更新推荐 TestFlight Release Notes，聚焦 A+B 变更

- `docs/engineering/SOP_RELEASE_AUTOMATION_zh.md`
  - 强化验证口径：不再依赖 `pilot builds` 作为硬验证（fastlane 版本/API 关系字段变更可能报错）
  - 补充故障处理：pub get/build_runner 卡住、Xcode build.db disk I/O error 的处置
  - 外测分发：增加 processing/`No build to distribute` 的等待与重试脚本示例，以及从 `.env` 生成 `/tmp/asc_api_key_papertok.json` 的脚本

## 关联交付
- 上游吸收 PR：#7
- TestFlight：1.68.5 (6376)

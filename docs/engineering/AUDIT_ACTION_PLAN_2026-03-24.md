# PaperTok Reader 审计行动清单（2026-03-24）

## 本轮已直接修复

- `bgimgFit` 非法偏好值会导致崩溃：已为 `BgimgFitEnum.fromCode()` 增加 fallback 到 `cover`
- AI 供应商中心 smoke test：移除硬编码旧文案，改为稳定的“构建成功 + 无异常”检查
- 新增测试：
  - `test/config/shared_preference_bgimg_fit_test.dart`
  - `test/config/shared_preference_reading_info_migration_test.dart`
- `flutter analyze` 的硬错误收口：排除 vendored `packages/langchain_openai/test/**`，避免其缺失依赖拖垮应用分析门槛
- 文档口径收口：
  - `docs/engineering/苹果商店上线缺口审计.md` 中 TF build 号更新为 `1.68.5 (6376)`
  - `docs/ai/ios_testflight_build.md` / `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md` 明确 fastlane/state-file 才是当前 TF build number 真值
- 仓库卫生：已关闭过期 PR #1、PR #5

## 当前仍需人工完成（我无法替你完全完成）

### P0：提审级 App Store 收口

1. 上线真实 URL
- 将以下草稿真正发布到可访问 URL：
  - 隐私政策
  - 支持页
- 参考草稿：
  - `docs/engineering/苹果商店隐私政策草稿.md`
  - `docs/engineering/苹果商店支持页草稿.md`

2. ASC 后台配置
- App Privacy 问卷
- Support URL / Privacy Policy URL / Marketing URL
- Review Information
- Export Compliance
- 分类 / 年龄分级 / 地区 / 定价

3. 截图资产
- iPhone / iPad 截图制作与最终上传
- 建议按 `docs/engineering/苹果商店上线缺口审计.md` 的缺口逐项收口

4. 冻结版 QA 留证
- 选择一个冻结 build（当前建议从 `1.68.5 (6376)` 开始）
- 按以下文档做完整记录：
  - `docs/engineering/IOS_IPADOS_QA_CHECKLIST_zh.md`
  - `docs/engineering/QA_METHOD_zh.md`
  - `docs/engineering/QA_GUIDED_RUNBOOK_zh.md`

### P1：发布级回归

1. 真机专项回归（建议至少覆盖）
- 背景图：Blur / Opacity / Fit（分页/滚动、浅色/深色、横竖屏）
- Header/Footer：旧配置迁移、左右边距、字号、不同设备宽度
- TTS：SystemTts 首句为空不崩、TTS FAB 不遮挡关键交互

2. Android / 桌面端 smoke
- 当前主线主要修的是 iOS/阅读器路径，Android / 桌面端仍需做一轮系统性 smoke

### P1：后续可选增强（非阻塞）

1. 背景图旧语义是否保留
- 评估是否要恢复 `alignment/repeat` 语义
- 若要保留，建议单独做一个小 PR，而不是混入主线稳定性修复

2. TTS 增强（建议拆小 PR）
- fromCfi 选区朗读
- 点击高亮暂停/继续
- OnlineTts pitch/rate 动态调整修复
- 键盘翻页模式

## 建议执行顺序

1. 先从 `main` 再发一个冻结 TF（如基于已合并的 #7/#8）
2. 做 iPhone + iPad QA 留证
3. 并行准备 URL / 截图 / ASC 配置
4. 完成 P0 后再决定是否提审

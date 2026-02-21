[English](README.md) | **简体中文**

<br>

# Paper Reader（papertok-reader）

**Paper Reader** 是一个以 iOS/iPadOS 为主做验证的“产品发行版”，基于上游 **[Anx Reader](https://github.com/Anxcye/anx-reader)**（MIT）进行定制与增强。

本仓库主要聚焦：**PaperTok 集成 + AI/翻译体验增强 + 产品默认值 + iOS 侧 QA/发布工作流**。

## 多端状态（重要）

- ✅ **本仓库已测试：** iOS（iPhone）+ iPadOS（iPad）
- ⚠️ **本仓库尚未验证：** Android / 桌面端（macOS/Windows/Linux）

如果你现在就需要稳定的多端体验，建议直接使用上游项目 **Anx Reader**。

## 功能亮点

### PaperTok（论文流 / Papers Tab）
- PaperTok 学术论文流作为一级 Tab 集成。
- 导航与默认值更偏“论文阅读”工作流。

### AI 对话（Provider Center）
- Provider Center 供应商中心（Flutter 原生实现，Cherry 风格参考但不复用代码）。
- 内置供应商 + 自定义供应商（OpenAI-compatible / Anthropic / Gemini / OpenAI Responses）。
- 对话内切换供应商与模型。
- “思考档位”选择 + 思考内容折叠展示。
- 支持编辑历史消息、从任意用户轮次重新生成。
- 对话树 v2 + 多版本/回滚（不丢失后续对话）。
- 多模态附件（当前：**图片 + 纯文本**；每次最多 **4** 张图）。
- EPUB 图片解析：点图 → 多模态模型解析图注/图表。

### 阅读器内翻译（EPUB）
- 沉浸式全文翻译：**译文在下**。
- 右上角进度 HUD（可关闭/可再唤起）。
- 按书缓存 + 清理；支持对失败段落重试。
- 翻译可独立指定供应商/模型（与对话分离）。

### 同步与备份（安全优先）
- WebDAV 同步 **非敏感** AI 设置（供应商/模型/提示词/UI 偏好等），Phase 1 为“整文件时间戳 newer-wins”。
- Files/iCloud Drive 手动备份/恢复，支持方向性覆盖。
- **明文备份绝不包含 API key**（包括 `api_key` 和 `api_keys`）。
- 只有在**加密备份**（口令）时才允许包含 API keys。

## 文档入口（建议从这里开始）

- 文档索引：**[`docs/README.md`](./docs/README.md)**

### 工程 / iOS（强烈建议先读）
- iOS 真机安装 / 签名 / TestFlight 全流程：**[`docs/engineering/IOS_DEPLOY_zh.md`](./docs/engineering/IOS_DEPLOY_zh.md)**
- Identifiers 真值源（Display Name / Bundle ID / App Group / Android applicationId）：**[`docs/engineering/IDENTIFIERS_zh.md`](./docs/engineering/IDENTIFIERS_zh.md)**
- iOS TestFlight 发布清单：**[`docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md`](./docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md)**
- 平台测试状态：**[`docs/engineering/PLATFORM_TEST_STATUS_zh.md`](./docs/engineering/PLATFORM_TEST_STATUS_zh.md)**
- 故障排除：**[`docs/troubleshooting.md`](./docs/troubleshooting.md)**

### AI / 翻译
- AI 对话/翻译总览：**[`docs/ai/README.md`](./docs/ai/README.md)**
- AI 设置 WebDAV 同步设计：**[`docs/ai/ai_settings_sync_webdav.md`](./docs/ai/ai_settings_sync_webdav.md)**
- 备份/恢复（Files/iCloud）：**[`docs/ai/backup_restore_icloud.md`](./docs/ai/backup_restore_icloud.md)**

## 开发快速开始

```bash
flutter pub get
flutter gen-l10n
# 本仓库忽略部分生成文件，需要时再跑 build_runner
# dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

> 如果 build_runner 遇到 Flutter/Dart SDK 不匹配问题，可以改用：
> `flutter pub run build_runner build --delete-conflicting-outputs`

## 与上游的关系 / 工作流

本仓库以“产品交付”为主：

- PaperTok 与产品专属 UX 改动在本仓库演进。
- 如需把通用 AI/翻译能力贡献回上游，会走**独立 contrib track**，保证提交干净（不混入 PaperTok/产品专属改动）。

详见：**[`docs/engineering/WORKFLOW_zh.md`](./docs/engineering/WORKFLOW_zh.md)**、**[`docs/engineering/UPSTREAM_CONTRIB_zh.md`](./docs/engineering/UPSTREAM_CONTRIB_zh.md)**。

## License

MIT（与上游 Anx Reader 保持一致）。
见 [LICENSE](./LICENSE)。

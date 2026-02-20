[English](README.md) | **简体中文**

<br>

# Paper Reader（papertok-reader）

**Paper Reader** 是一个基于 **[Anx Reader](https://github.com/Anxcye/anx-reader)** 的阅读器发行版，主要集成：

- **PaperTok**（论文流 / Papers Tab）
- 增强的 **AI 对话**（供应商中心、思考档位、对话树/回滚）
- 阅读器内 **沉浸式全文翻译**（译文在下）

## 多端状态（重要）

- ✅ **已测试：** iOS（iPhone）+ iPadOS（iPad）
- ⚠️ **本仓库暂未测试：** Android / 桌面端（macOS/Windows/Linux）

如果你现在就需要稳定的多端体验，建议直接使用上游项目 **Anx Reader**。
本项目后续会对 Android 做测试与适配，但目前还未验证。

## 文档入口

- 文档索引：**[`docs/README.md`](./docs/README.md)**
- iOS 真机安装 / 签名 / TestFlight：**[`docs/engineering/IOS_DEPLOY_zh.md`](./docs/engineering/IOS_DEPLOY_zh.md)**
- 标识真值源（Bundle ID / App Group / Android applicationId）：**[`docs/engineering/IDENTIFIERS_zh.md`](./docs/engineering/IDENTIFIERS_zh.md)**

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

## 截图

![](./docs/images/main.jpg)

## 与上游的关系

本仓库更偏“产品发行版”：
- PaperTok 一级入口 + 产品默认值 + iOS 优先的 QA/发布流程
- 通用的 AI/翻译改造尽量保持可上游化（必要时通过独立 contrib track 提交回 Anx Reader）

## License

MIT（与上游 Anx Reader 保持一致）。
见 [LICENSE](./LICENSE)。

# iOS TestFlight 发布清单（PaperTok Reader / papertok-reader）

本文档记录 **papertok-reader（产品发行版）** 的 iOS TestFlight 发布流程、产品化（branding + identifiers）改造要点与常见问题。

> 如果你是第一次跑通 iOS 真机安装/签名，建议先读：`docs/engineering/IOS_DEPLOY_zh.md`。

> 适用范围
> - 本仓库：`ViffyGwaanl/papertok-reader`（private）
> - App 显示名：**PaperTok Reader**

## 当前发布候选（2026-03-07）

- 目标版本：`1.68.2`
- 本轮目标：发一版新的 TestFlight，把 `1.68.1` 之后的主线更新一起带进去。

### 1.68.1 -> 1.68.2 更新摘要

本轮建议在 TestFlight / App Store Connect 的版本说明中整理为：

- Share diagnostics 增强：
  - 搜索
  - 状态筛选
  - destination 筛选
  - kind 筛选
  - 结构化 receive / routing / handoff / cleanup 状态链路
- Memory M1：
  - 显式保存到今日日记
  - 保存到长期记忆
  - 加入 Review Inbox
  - Memory 页最小 Review Inbox
  - 统一 Markdown memory 写协调器
- Memory M1.5 / M2 稳定子集：
  - 结束会话时生成记忆候选
  - session-end candidate digest
  - auto-daily 路由策略
  - 长期记忆写入前确认开关
- 高级日志页增强：
  - 搜索
  - 仅错误
  - 级别筛选
  - 来源筛选
- 低风险命名收口：
  - 对外产品名统一为 `PaperTok Reader`
  - App 内文案 / l10n / iOS / Android 显示名统一

### 本轮推荐 TestFlight 更新说明（中文）

```text
1. 分享诊断页支持搜索、状态筛选、目的地筛选和类型筛选，更容易定位分享问题。
2. Memory 新增显式保存到今日日记、长期记忆和 Review Inbox，并补齐最小记忆工作流。
3. 结束会话时可生成记忆候选，支持 Review Inbox 或自动写入今日日记。
4. 高级日志页新增搜索、错误筛选、级别筛选和来源筛选，排障更方便。
5. 产品对外名称统一为 PaperTok Reader。
```

---

## 0. 当前默认标识（Source of Truth）

> 这些值用于 Apple Developer / App Store Connect / Xcode 签名。
> **以总表为准**：[`docs/engineering/IDENTIFIERS_zh.md`](./IDENTIFIERS_zh.md)

（iOS 重点关注：主 App Bundle ID / Share Extension Bundle ID / App Group）

相关文件：
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/Info.plist`（显示名等）

---

## 1. 产品化改造要点（Branding & Identifiers）

为了：
- 与官方 Anx Reader/其他分支 **可并存安装**（同一设备不冲突）
- 拥有独立的签名与发布通道（TestFlight / App Store）

需要确保：
- Display Name（用户看到的名字）与 Bundle ID（系统识别的唯一标识）都已产品化。

### 1.1 Display Name（显示名）

当前显示名为：**PaperTok Reader**。

检查：
- `ios/Runner/Info.plist`：`CFBundleDisplayName`
- `ios/Runner.xcodeproj/project.pbxproj`：`INFOPLIST_KEY_CFBundleDisplayName`

> 备注：如果你希望主 App 与 Share Extension 在系统“分享面板”中显示不同名字，需要分别设置 extension target 的 Display Name（一般不建议，保持一致即可）。

### 1.2 Bundle ID（主 App + Share Extension + Tests）

当前 Bundle IDs 已统一为：
- `ai.papertok.paperreader`
- `ai.papertok.paperreader.shareExtension`
- `ai.papertok.paperreader.RunnerTests`

检查位置：
- `ios/Runner.xcodeproj/project.pbxproj`：`PRODUCT_BUNDLE_IDENTIFIER`

### 1.3 App Group（Share Extension 共享容器）

Share Extension 与主 App 通过 App Group 共享数据。当前默认：
- `group.ai.papertok.paperreader`

检查位置：
- `ios/Runner.xcodeproj/project.pbxproj`：`CUSTOM_GROUP_ID`
- `ios/Runner/Info.plist`：`AppGroupId = $(CUSTOM_GROUP_ID)`
- `ios/ShareExtension/Info.plist`：`AppGroupId = $(CUSTOM_GROUP_ID)`

> 注意：App Group 需要在 Xcode 的 **Signing & Capabilities → App Groups** 中启用，并在 Apple Developer Portal 里创建同名 group。否则会出现 share extension 运行时写入失败/找不到共享容器。

---

## 2. “一键切换到你自己的反向域名根”指南（强烈建议收藏）

当你需要把标识从：

- `ai.papertok.paperreader`

切到比如：

- `ai.yourdomain.paperreader`

请遵循 **“单点真值 + 清单式替换 + 验证命令”**，避免漏改。

### 2.1 需要替换的标识集合

建议把下面四个值当作一组同时替换：

- `APP_BUNDLE_ID = ai.papertok.paperreader`
- `EXT_BUNDLE_ID = ai.papertok.paperreader.shareExtension`
- `TEST_BUNDLE_ID = ai.papertok.paperreader.RunnerTests`
- `APP_GROUP_ID = group.ai.papertok.paperreader`

### 2.2 iOS 必改文件清单

| 文件 | 必改项 | 说明 |
|---|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER`（Runner/Tests/ShareExtension） | Bundle ID 真值源 |
| `ios/Runner.xcodeproj/project.pbxproj` | `CUSTOM_GROUP_ID` | App Group 真值源 |
| `ios/Runner/Info.plist` | `CFBundleDisplayName` | 显示名（PaperTok Reader） |
| `ios/fastlane/Matchfile` | `app_identifier(...)` | match/签名脚本使用 |
| `ios/fastlane/Fastfile` | identifiers mapping | match/上传流程 |

> 如果你不用 fastlane，可以忽略 fastlane 两项，但推荐保留一致性（未来 CI 会用到）。

### 2.3 快速验证命令（改完必须跑）

```bash
# 1) 确认 bundle ids / app group 已替换
rg -n "PRODUCT_BUNDLE_IDENTIFIER =|CUSTOM_GROUP_ID =" ios/Runner.xcodeproj/project.pbxproj

# 2) 生成 iOS 构建配置（刷新 Generated.xcconfig）
flutter clean
flutter pub get
flutter gen-l10n
# 如项目使用 build_runner：
dart run build_runner build --delete-conflicting-outputs

# 3) 最快的回归：跑单测（避免改包名引入字符串/路径问题）
flutter test -j 1
```

---

## 3. 发布流程（完整清单）

### Step 1: 确认版本号（pubspec.yaml）

```yaml
version: 1.2.3+46  # Build Number 递增
```

- `1.2.3`：Version（CFBundleShortVersionString）
- `46`：Build Number（CFBundleVersion，TestFlight 每次必须递增）

### Step 2: 清理并生成 iOS 构建配置

```bash
flutter clean
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter build ios --release --no-codesign
```

### Step 3: 验证 Generated.xcconfig（Build Number）

```bash
cat ios/Flutter/Generated.xcconfig | rg FLUTTER_BUILD_NUMBER
```

### Step 4: Xcode Archive

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中：
1. Scheme: **Runner**（Release）
2. Device: **Any iOS Device (arm64)**
3. Product → **Archive**

### Step 5: 上传到 App Store Connect

Organizer → Distribute App → App Store Connect → Upload。

### Step 6: TestFlight 配置与分发

App Store Connect → TestFlight：添加内测/外测测试人员。

---

## 4. Troubleshooting（常见坑）

### 4.1 Archive 显示旧版本号

原因：`ios/Flutter/Generated.xcconfig` 没刷新。

解决：
```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

### 4.2 Provisioning Profile 与 Bundle ID 不匹配

症状：Archive 报错 profile 不匹配。

解决：
1) Apple Developer Portal 为 **新的 Bundle ID** 创建 App ID
2) 生成对应的 Distribution profile（App Store）
3) Xcode 里选择正确的 Team/Profile（Runner 与 shareExtension 都要配）

### 4.3 Share Extension 能打开，但导入/写入失败

高概率原因：App Groups 未正确配置（或 group 名不一致）。

检查：
- Xcode → Runner / ShareExtension → Signing & Capabilities → App Groups 是否都勾选了同一个 `group.*`
- Apple Developer Portal 里是否创建了该 App Group

### 4.4 TestFlight Processing 卡住

一般是 Apple 延迟（5–30 分钟），或 entitlements/签名有问题。

做法：
- 先等 30 分钟
- 看 App Store Connect 的 Build 详情警告
- 看 Apple 邮件通知

### 4.5 构建时报 “iOS XX.X is not installed”

如果 `flutter build ios` / Xcode Archive 报类似：

- `iOS 26.x is not installed. Please download and install the platform from Xcode > Settings > Components.`

说明当前 Xcode 缺少对应 iOS Platform 组件。
请在 **Xcode → Settings → Components** 安装后重试。

---

## 5. 未来可能要做的发布准备（与 Bundle ID 相关）

这些不是本次发布必需，但一旦做就会与 Bundle ID 强绑定：

1) **Universal Links（iOS）/ App Links（Android）**
- 需要在 `papertok.ai` 部署 AASA / assetlinks，并填入 **TeamID + BundleID / packageName**。

2) OAuth / 登录回调（Redirect URI）
- 若把 App 作为 OAuth client，回调与包名/Bundle ID 绑定。

---

## 6. 快速检查清单

发布前确认：

- [ ] Bundle ID：`ai.papertok.paperreader`（Runner）
- [ ] Share Extension：`ai.papertok.paperreader.shareExtension`
- [ ] App Group：`group.ai.papertok.paperreader`
- [ ] `pubspec.yaml` Build Number 已递增
- [ ] 已执行：`flutter clean && flutter pub get && flutter gen-l10n`
- [ ] 已执行：`dart run build_runner build --delete-conflicting-outputs`（如适用）
- [ ] `flutter test -j 1` 通过
- [ ] Xcode Archive 成功
- [ ] 上传 App Store Connect 成功

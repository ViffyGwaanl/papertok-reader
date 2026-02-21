# iOS 部署/安装测试教程（Paper Reader / papertok-reader）

本文档面向 **papertok-reader（产品发行版）**，提供从“拉代码 → 真机安装 → TestFlight 分发”的完整 iOS 部署/安装测试流程。

> 本文档聚焦“工程可执行流程”。标识（Bundle ID / App Group 等）以总表为准：
> - `docs/engineering/IDENTIFIERS_zh.md`

---

## 0. 你需要做出的选择（先选路线）

iOS 安装测试通常分两条路线：

### 路线 A：开发机直装（最快验证）
适合：
- 验证能编译、能启动、核心页面可用
- 快速排查签名/Bundle ID/App Groups 相关问题

特点：
- 需要 Xcode + 数据线连接（或 Wi‑Fi 调试）
- 安装包是“开发安装”，不适合长期分发

### 路线 B：TestFlight（接近真实分发，安装更持久）
适合：
- 你希望“长期保留安装、可更新、可分发给测试者”
- 更贴近最终发布/升级路径

特点：
- 需要 App Store Connect 配置
- 需要 Archive → Upload 流程

> 结论：第一次跑通建议用路线 A；需要“持久安装”再上路线 B。

---

## 1. 前置条件（一次性准备）

### 1.1 环境
- macOS + Xcode（建议最新版稳定）
  - 如果构建时报 `iOS XX.X is not installed`：到 **Xcode → Settings → Components** 安装对应 iOS Platform
- Flutter SDK（与项目兼容的版本）
- CocoaPods（通过 Xcode/Pods 自动处理即可，必要时手动安装）

> 备注：本项目的 iPhone 浮动 TabBar 使用 `cupertino_native`（原生 UITabBar / Liquid Glass），因此对 Xcode/平台组件完整性更敏感。

### 1.2 设备
- iPhone/iPad 打开 **开发者模式**（iOS 16+）：
  - 设置 → 隐私与安全性 → 开发者模式
- 首次连接电脑：设备上选择“信任此电脑”

### 1.3 Apple Developer 账号
- 你需要能在 Apple Developer Portal / App Store Connect 中创建与管理 App。

---

## 2. 项目真值源（Identifiers）

在动手之前，先打开总表确认当前默认值：

- `docs/engineering/IDENTIFIERS_zh.md`

你会看到当前默认：
- Display Name：**Paper Reader**
- iOS Bundle ID（主 App / Share Extension / Tests）
- App Group（用于 share extension 共享）

> 重要：你现在已经产品化并切换到 `ai.papertok.*`。这意味着与旧包名（例如 `com.*`）**不会覆盖安装**，属于正常现象。

---

## 3. 获取代码并准备构建输入（推荐标准流水线）

在仓库根目录：

```bash
git pull

flutter clean
flutter pub get
flutter gen-l10n

# 如果你在本项目中遇到“生成文件缺失/冲突”，请用 Flutter 驱动 build_runner：
flutter pub run build_runner build --delete-conflicting-outputs

# 可选：跑单测，尽早发现问题
flutter test -j 1
```

### 3.1 为什么要跑 build_runner？
- 该仓库忽略了部分生成文件（例如 `*.g.dart/*.freezed.dart`），新环境/清理后可能缺失。
- 用 `flutter pub run ...` 比 `dart run ...` 更稳（避免 Dart 版本不一致）。

---

## 4. 路线 A：开发机直装（Run 到真机）

### 4.1 打开 Xcode（必须用 workspace）

```bash
open ios/Runner.xcworkspace
```

> 不要打开 `Runner.xcodeproj`，否则 Pods/脚本阶段可能缺失。

### 4.2 配置 Signing（Runner + Share Extension 都要配）

在 Xcode：

#### Target：Runner（主 App）
- Signing & Capabilities：
  - Team：选择你的 Team
  - 勾选 **Automatically manage signing**（第一次跑通建议开启）
  - Bundle Identifier：应与 `IDENTIFIERS_zh.md` 一致

#### Target：Share Extension
- 同样选择 Team，并确保 Bundle Identifier 正确

### 4.3 App Groups（如果需要测试分享导入/共享容器）

如果你要测试 Share Extension 导入（强烈建议测）：
- Runner 与 Share Extension 两个 Target 都需要添加相同的 App Group：
  - `group.ai.papertok.paperreader`（见 `IDENTIFIERS_zh.md`）

注意：
- App Group 可能需要你在 Apple Developer Portal 创建同名 group
- 如果 group 不一致或未启用，可能出现“分享导入能打开但写入失败/找不到容器”的问题

### 4.4 运行安装
- 选择目标设备（顶部 Device selector）
- 点击 ▶︎ Run

### 4.5 验收点（最小安装测试）
- [ ] 桌面显示名：Paper Reader
- [ ] App 能启动进入首页
- [ ] 设置页可打开
- [ ] （可选）Share 导入：从 Files/其他 App 分享 PDF/EPUB 到 Paper Reader，能唤起并完成导入

---

## 5. 路线 B：TestFlight（Archive → Upload）

TestFlight 发布更接近真实分发。更详细流程请读：
- `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md`

这里给一份最短执行清单：

### 5.1 递增 build number
编辑 `pubspec.yaml`：

```yaml
version: 1.2.3+46
```

### 5.2 生成 Release 构建配置（刷新 Generated.xcconfig）

```bash
flutter clean
flutter pub get
flutter gen-l10n
flutter pub run build_runner build --delete-conflicting-outputs
flutter build ios --release --no-codesign
```

### 5.3 Xcode Archive
- 打开 `ios/Runner.xcworkspace`
- Scheme：Runner（Release）
- Destination：Any iOS Device (arm64)
- Product → Archive

### 5.4 Upload → TestFlight
Organizer → Distribute App → App Store Connect → Upload。

---

## 6. 常见问题（高频）

### 6.1 “Provisioning profile / Signing 相关报错”
典型原因：
- Bundle ID 已更换，但 Apple Developer Portal 上没有对应 App ID
- Runner 与 Share Extension 没有用同一 Team 或 profile

处理：
- 先用 Automatically manage signing 跑通（路线 A）
- 再按 TestFlight 要求切换到正确的 Distribution 配置（路线 B）

### 6.2 “Share Extension 能出现，但导入失败/共享容器报错”
高概率：App Groups 没开或 group id 不一致。

检查：
- Runner 与 Share Extension 都启用了 App Groups，并勾选同一个 group

### 6.3 “我没跑 build_runner 也能 build，但换机器就炸”
这是因为你本机可能残留了旧生成文件。建议按第 3 节标准流水线走，保证可复现。

---

## 7. 建议的最小记录（方便你截图/复盘）

当你卡住时，建议记录并发我：
- Xcode 报错的第一条完整 error（含 Target 名）
- 当前选择的 Team
- 你是否启用了 App Groups（以及 group id）

这样定位会快很多。

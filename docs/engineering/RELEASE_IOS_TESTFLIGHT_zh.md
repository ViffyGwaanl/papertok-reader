# iOS TestFlight 发布清单

本文档记录 papertok-reader iOS 版本的 TestFlight 发布流程、"新项目化"改造要点与常见问题。

---

## 1. 新项目化改造要点

为避免与 Anx Reader 官方版本（或其他分支）在同一设备上冲突，建议修改 Bundle ID 并独立管理签名。

### 1.1 修改 Bundle ID

编辑 `ios/Runner.xcodeproj/project.pbxproj` 和 Xcode 项目配置：

- 原值（示例）：`com.anxcye.anx-reader`
- 新值（示例）：`com.papertok.reader` 或 `ai.papertok.reader`

确保在 Xcode 中同步修改：
- Target: Runner → General → Bundle Identifier
- 所有 Build Configurations (Debug/Profile/Release) 保持一致

### 1.2 签名与 Provisioning Profile

- **开发签名**：本地调试可使用 "Automatically manage signing"
- **发布签名**：TestFlight 需要 **App Store Distribution** 证书与对应的 Provisioning Profile
  - 在 Apple Developer Portal 创建新的 App ID（使用新 Bundle ID）
  - 创建 Distribution Provisioning Profile（类型：App Store）
  - 下载并在 Xcode 中选择

**常见错误**：
- `Provisioning profile doesn't include the currently selected device` → 确认使用的是 Distribution profile（不是 Development）
- `Code signing "Runner" failed` → 确认证书在 Keychain 中有效且未过期

### 1.3 版本号策略

版本号由 `pubspec.yaml` 中的 `version` 字段控制：

```yaml
version: 1.2.3+45
```

- `1.2.3`：Version（CFBundleShortVersionString）
- `45`：Build Number（CFBundleVersion）

**注意**：
- TestFlight 要求每次上传的 Build Number 必须递增（即使 Version 不变）
- 修改 `pubspec.yaml` 后需确保 `ios/Flutter/Generated.xcconfig` 已更新（见下文）

---

## 2. 发布流程（完整清单）

### Step 1: 确认版本号

编辑 `pubspec.yaml`：

```yaml
version: 1.2.3+46  # Build Number 递增
```

### Step 2: 清理并生成 iOS 构建配置

```bash
flutter clean
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter build ios --release --no-codesign
```

**用途**：
- `flutter clean`：清理缓存，确保 `Generated.xcconfig` 重新生成
- `flutter build ios --release --no-codesign`：生成 Release 配置但不签名（签名由 Xcode Archive 完成）

### Step 3: 验证 Generated.xcconfig

检查 `ios/Flutter/Generated.xcconfig` 中的版本号是否正确：

```bash
cat ios/Flutter/Generated.xcconfig | grep FLUTTER_BUILD_NUMBER
```

预期输出示例：

```
FLUTTER_BUILD_NUMBER=46
```

如果显示旧的 Build Number，重新执行 Step 2。

### Step 4: 打开 Xcode 并 Archive

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中：
1. 选择 Target: **Runner**
2. 选择 Scheme: **Runner** (Release)
3. 设备选择：**Any iOS Device (arm64)**
4. 菜单：**Product → Archive**

**常见问题**：
- Archive 显示的 Build Number 仍是旧值 → 见 [Troubleshooting: Archive 显示旧版本号](#troubleshooting-archive-显示旧版本号)
- Archive 失败提示 `Signing for "Runner" requires a development team` → 在 Target → Signing & Capabilities 中选择正确的 Team 和 Provisioning Profile

### Step 5: 上传到 App Store Connect

Archive 成功后，Organizer 窗口自动打开：
1. 选择刚才的 Archive
2. 点击 **Distribute App**
3. 选择 **App Store Connect**
4. 选择 **Upload**
5. 确认签名选项（通常选 "Automatically manage signing"）
6. 点击 **Upload**

上传成功后，Apple 会进行处理（通常 5-15 分钟），处理完成后可在 App Store Connect 中看到新的 Build。

### Step 6: 在 App Store Connect 中配置 TestFlight

1. 登录 [App Store Connect](https://appstoreconnect.apple.com/)
2. 进入 **My Apps** → 选择你的 App
3. 进入 **TestFlight** 标签
4. 等待 Build 处理完成（状态从 "Processing" 变为 "Ready to Submit"）
5. 添加测试人员（Internal Testing 或 External Testing）
6. 如果是首次发布，需要填写 **Export Compliance Information**（通常选 "No" 如果不涉及加密）

---

## 3. Troubleshooting

### Archive 显示旧版本号

**症状**：修改了 `pubspec.yaml` 的 Build Number，但 Xcode Archive 仍显示旧值。

**原因**：`ios/Flutter/Generated.xcconfig` 未刷新。

**解决方案**：

```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

然后重新 Archive。

### Archive 失败：Provisioning profile doesn't match

**症状**：Archive 时提示 Provisioning Profile 与 Bundle ID 不匹配。

**解决方案**：
1. 在 Apple Developer Portal 确认已为新 Bundle ID 创建 App ID
2. 创建对应的 Distribution Provisioning Profile（类型：App Store）
3. 下载并在 Xcode 中手动选择（Target → Signing & Capabilities → Provisioning Profile）

### TestFlight 上传成功但一直"Processing"

**症状**：上传成功，但 Build 在 App Store Connect 中长时间显示 "Processing"。

**可能原因**：
- Apple 服务延迟（通常 5-30 分钟）
- Build 包含问题（例如缺少必要的 Entitlements）

**解决方案**：
- 等待 30 分钟
- 检查邮件（Apple 会发送错误通知）
- 在 App Store Connect 中查看 Build 详情是否有警告

### 本地调试正常，但 Archive 失败

**常见原因**：
- Debug 配置使用的签名与 Release 配置不同
- Entitlements 配置不完整（例如 iCloud、App Groups）

**解决方案**：
1. 在 Xcode 中检查 Target → Signing & Capabilities
2. 确保 Release 配置选择了正确的 Distribution Provisioning Profile
3. 检查 `ios/Runner/Runner.entitlements` 与 Provisioning Profile 权限一致

### 构建时提示 "Multiple commands produce..."

**症状**：构建时提示多个命令生成同一文件。

**常见原因**：Xcode 项目配置冲突（例如重复的 Build Phase）。

**解决方案**：
```bash
flutter clean
cd ios
pod deintegrate
pod install
cd ..
flutter build ios --release --no-codesign
```

---

## 4. 参考资料

- [Apple Developer - TestFlight](https://developer.apple.com/testflight/)
- [Flutter - Build and release an iOS app](https://docs.flutter.dev/deployment/ios)
- [Troubleshooting: iOS Archive 版本号问题](../troubleshooting.md#ios-archive-shows-old-build-number-testflight)

---

## 5. 快速检查清单

发布前确认：

- [ ] `pubspec.yaml` 中的 Build Number 已递增
- [ ] 已执行 `flutter clean && flutter pub get && flutter build ios --release --no-codesign`
- [ ] `ios/Flutter/Generated.xcconfig` 中的 `FLUTTER_BUILD_NUMBER` 正确
- [ ] Xcode 中的 Bundle Identifier 正确（与 Apple Developer Portal 一致）
- [ ] Xcode Target → Signing & Capabilities 中选择了正确的 Team 和 Provisioning Profile
- [ ] Archive 成功且版本号正确
- [ ] 上传到 App Store Connect 成功
- [ ] App Store Connect 中 Build 状态为 "Ready to Submit"

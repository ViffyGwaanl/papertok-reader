# Identifiers 总表（Paper Reader / papertok-reader）

本文件是 **papertok-reader 产品发行版** 的“标识真值源（Single Source of Truth）”。

当你需要：
- 更换域名根（reverse-domain，例如 `ai.papertok.*` → `ai.yourdomain.*`）
- 让 App 与官方 Anx Reader 并存安装
- 配置 TestFlight / App Store / Google Play / App Links / Universal Links

请先更新本文件，再按各平台清单执行替换与验证。

---

## 0. 当前默认值（Source of Truth）

### 0.1 Display Name（用户看到的名字）
- **Paper Reader**

> Display Name ≠ Bundle ID / applicationId。
> Display Name 用于系统桌面/启动器展示；Bundle ID / applicationId 用于签名、发布、系统唯一识别。

### 0.2 Reverse-domain 根（基于 papertok.ai）
- Domain：`papertok.ai`
- Reverse-domain prefix：`ai.papertok`

---

## 1. Android

### 1.1 applicationId / namespace
- **applicationId**：`ai.papertok.paperreader`
- **namespace**：`ai.papertok.paperreader`

位置：
- `android/app/build.gradle`

### 1.2 MainActivity Kotlin package
- `package ai.papertok.paperreader`

位置：
- `android/app/src/main/kotlin/ai/papertok/paperreader/MainActivity.kt`

### 1.3 MethodChannel（安装信息）
- Channel：`ai.papertok.paperreader/install_info`

位置：
- Android：`android/app/src/main/kotlin/ai/papertok/paperreader/MainActivity.kt`
- Flutter：`lib/service/iap/play_store_iap_service.dart`

### 1.4 App label（显示名）
- `@string/title = "Paper Reader"`

位置：
- `android/app/src/main/res/values/strings.xml`
- `android/app/src/main/res/values-zh/strings.xml`

---

## 2. iOS

### 2.1 Bundle IDs
- **主 App**：`ai.papertok.paperreader`
- **Share Extension**：`ai.papertok.paperreader.shareExtension`
- **RunnerTests**：`ai.papertok.paperreader.RunnerTests`

位置：
- `ios/Runner.xcodeproj/project.pbxproj`（`PRODUCT_BUNDLE_IDENTIFIER`）

### 2.2 App Group（主 App + Share Extension 共享容器）
- **App Group**：`group.ai.papertok.paperreader`

位置：
- `ios/Runner.xcodeproj/project.pbxproj`（`CUSTOM_GROUP_ID`）
- `ios/Runner/Info.plist`（`AppGroupId = $(CUSTOM_GROUP_ID)`）
- `ios/ShareExtension/Info.plist`（同上）

### 2.3 Display Name
- `CFBundleDisplayName = "Paper Reader"`

位置：
- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj/project.pbxproj`（`INFOPLIST_KEY_CFBundleDisplayName`）

---

## 3. macOS

### 3.1 Bundle ID
- `ai.papertok.paperreader`

位置：
- `macos/Runner/Configs/AppInfo.xcconfig`
- `macos/Runner.xcodeproj/project.pbxproj`

### 3.2 Display Name / Product Name
- `Paper Reader`

位置：
- `macos/Runner/Configs/AppInfo.xcconfig`（`PRODUCT_NAME`）
- `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

---

## 4. 本地配置/偏好文件名（跨设备迁移相关）

### iOS / macOS SharedPreferences plist 文件名
- `ai.papertok.paperreader.plist`

位置：
- `lib/utils/get_path/shared_prefs_path.dart`

> 影响：当你更换 bundle id 后，系统偏好文件名也会变化。手动备份/恢复逻辑若依赖该文件名，需要按此同步更新。

---

## 5. 未来能力与域名绑定点（做之前先看这里）

以下能力一旦启用，会与 **域名 + identifiers** 强绑定：

1) **iOS Universal Links**
- 需要在 `https://papertok.ai/.well-known/apple-app-site-association` 里配置 `TEAMID.BundleID`。

2) **Android App Links**
- 需要在 `https://papertok.ai/.well-known/assetlinks.json` 里配置 `package_name = ai.papertok.paperreader` + 证书指纹。

3) OAuth / 登录回调（Redirect URI）
- 如果把 App 作为 OAuth Client，回调/白名单可能会与包名、scheme、Associated Domains 绑定。

---

## 6. 改域名根（“一键切换”执行顺序建议）

推荐顺序：
1) 先更新本文件（0-4 节的真值）
2) 按 iOS/Android 发布文档的清单替换文件
3) 跑验证命令

统一验证命令：

```bash
# 检查是否还残留旧 identifiers
rg -n "ai\\.papertok\\.paperreader|group\\.ai\\.papertok\\.paperreader" -S ios android macos lib

flutter clean
flutter pub get
flutter gen-l10n
# 如适用：
dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

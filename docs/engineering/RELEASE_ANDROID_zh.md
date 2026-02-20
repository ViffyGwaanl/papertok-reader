# Android 发布清单（Paper Reader / papertok-reader）

本文档记录 **papertok-reader（产品发行版）** 的 Android 发布流程、产品化（branding + identifiers）改造要点与常见问题。

> ⚠️ 现状说明（非常重要）
> - 本仓库目前只完成了 **iOS（iPhone/iPad）真机测试**。
> - **Android 端尚未进行系统性回归测试**（后续会补）。
> - 如果你当前必须稳定使用 Android/桌面端，请优先使用上游项目 **Anx Reader**。

> 适用范围
> - 本仓库：`ViffyGwaanl/papertok-reader`（private）
> - App 显示名：**Paper Reader**

---

## 0. 当前默认标识（Source of Truth）

> **以总表为准**：[`docs/engineering/IDENTIFIERS_zh.md`](./IDENTIFIERS_zh.md)

相关文件：
- `android/app/build.gradle`
- `android/app/src/main/kotlin/ai/papertok/paperreader/MainActivity.kt`
- `android/fastlane/Appfile`

---

## 1. 产品化改造要点（Branding & Identifiers）

为避免与官方 Anx Reader/其他分支在同一设备上冲突，Android 侧必须修改：
- `applicationId`（安装包唯一标识）
- `namespace`（R/Manifest/编译命名空间）
- Kotlin package 路径（与 namespace 保持一致）

### 1.1 修改 applicationId / namespace

编辑 `android/app/build.gradle`：

```gradle
android {
    namespace "ai.papertok.paperreader"

    defaultConfig {
        applicationId "ai.papertok.paperreader"
        // ...
    }
}
```

### 1.2 Kotlin 包路径与 MethodChannel

当前 MainActivity 位于：

- `android/app/src/main/kotlin/ai/papertok/paperreader/MainActivity.kt`
- `package ai.papertok.paperreader`

同时，安装信息通道（用于 IAP/安装时间读取）需要与 Dart 端一致：

- Android（Kotlin）：`ai.papertok.paperreader/install_info`
- Flutter（Dart）：`lib/service/iap/play_store_iap_service.dart`

### 1.3 显示名（App Label）

Android 的显示名来自：
- `android/app/src/main/res/values/strings.xml`：`@string/title`

当前值：`Paper Reader`

---

## 2. “一键切换到你自己的反向域名根”指南

当你需要把标识从：
- `ai.papertok.paperreader`

切到比如：
- `ai.yourdomain.paperreader`

请按清单替换，改完必须跑验证命令。

### 2.1 Android 必改文件清单

| 文件 | 必改项 | 说明 |
|---|---|---|
| `android/app/build.gradle` | `namespace` + `applicationId` | 核心标识 |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `package ...` | 与 namespace 对齐 |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `INSTALL_INFO_CHANNEL` 字符串 | 与 Dart 端 MethodChannel 一致 |
| `lib/service/iap/play_store_iap_service.dart` | MethodChannel 字符串 | 与 Android 一致 |
| `android/fastlane/Appfile` | `package_name(...)` | fastlane 使用（如适用） |

### 2.2 快速验证命令（改完必须跑）

```bash
# 1) 搜索确认已替换
rg -n "applicationId|namespace" android/app/build.gradle
rg -n "package " android/app/src/main/kotlin/**/MainActivity.kt

# 2) 基础回归
flutter clean
flutter pub get
flutter gen-l10n
# 如项目使用 build_runner：
dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

---

## 3. 签名配置（Release）

Android 发布建议使用 **Release Keystore**。

### 3.1 生成 Keystore（首次）

```bash
keytool -genkey -v -keystore ~/paperreader-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias paperreader-release
```

> Keystore 与密码务必备份（密码管理器 + 冷备份），否则后续无法升级同一应用条目。

### 3.2 配置签名

创建 `android/key.properties`（不要提交到 Git）：

```properties
storePassword=你的Keystore密码
keyPassword=你的Key密码
keyAlias=paperreader-release
storeFile=/path/to/paperreader-release-key.jks
```

并在 `android/app/build.gradle` 中配置 `signingConfigs.release`。

---

## 4. 版本号策略

版本号由 `pubspec.yaml` 控制：

```yaml
version: 1.2.3+46
```

- `1.2.3` → `versionName`
- `46` → `versionCode`（必须递增）

---

## 5. 发布流程（完整清单）

```bash
flutter clean
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs

# APK（直接分发）
flutter build apk --release

# AAB（Google Play）
flutter build appbundle --release
```

输出：
- APK：`build/app/outputs/flutter-apk/app-release.apk`
- AAB：`build/app/outputs/bundle/release/app-release.aab`

---

## 6. Troubleshooting

### 6.1 安装提示“应用未安装”

常见原因：
- 设备上已存在相同 `applicationId` 但签名不同的版本
- 多渠道混用 debug/release keystore

解决：
- 卸载旧版本后重装
- 确保发布始终使用同一个 keystore

### 6.2 Google Play 提示 versionCode 已使用

解决：
- `pubspec.yaml` 的 `+` 后数字递增，重新 build AAB。

---

## 7. 未来可能要做的发布准备（与包名相关）

1) **Android App Links**
- 需要在 `papertok.ai/.well-known/assetlinks.json` 增加 `package_name = ai.papertok.paperreader` 与证书指纹。

---

## 8. 快速检查清单

- [ ] applicationId：`ai.papertok.paperreader`
- [ ] `pubspec.yaml` versionCode 已递增
- [ ] `flutter test -j 1` 通过
- [ ] Release 构建产物生成（APK/AAB）
- [ ] Keystore 与密码已备份

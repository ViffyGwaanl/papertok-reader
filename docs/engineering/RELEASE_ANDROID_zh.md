# Android 发布清单

本文档记录 papertok-reader Android 版本的发布流程、"新项目化"改造要点与常见问题。

---

## 1. 新项目化改造要点

为避免与 Anx Reader 官方版本（或其他分支）在同一设备上冲突，建议修改 Application ID 并独立管理签名。

### 1.1 修改 Application ID

编辑 `android/app/build.gradle`：

```gradle
android {
    ...
    defaultConfig {
        applicationId "com.papertok.reader"  // 原值: com.anxcye.anx_reader
        minSdkVersion 21
        targetSdkVersion 34
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
```

**注意**：
- Application ID 必须全局唯一（建议使用 `com.papertok.reader` 或 `ai.papertok.reader`）
- 修改后需要卸载旧版本才能安装新版本（Application ID 不同视为不同 App）

### 1.2 签名配置（Release）

Android 发布需要使用 **Release Keystore** 签名。

#### 1.2.1 生成 Keystore（首次）

如果还没有 Keystore，使用以下命令生成：

```bash
keytool -genkey -v -keystore ~/papertok-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias papertok-release
```

按提示输入：
- Keystore 密码（妥善保存，后续需要）
- 组织信息（CN、OU、O、L、ST、C）
- Key 密码（建议与 Keystore 密码相同）

生成后，将 `papertok-release-key.jks` 保存到安全位置（**不要**提交到 Git）。

#### 1.2.2 配置签名

创建 `android/key.properties`（添加到 `.gitignore`）：

```properties
storePassword=你的Keystore密码
keyPassword=你的Key密码
keyAlias=papertok-release
storeFile=/path/to/papertok-release-key.jks
```

编辑 `android/app/build.gradle`：

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            ...
        }
    }
}
```

### 1.3 版本号策略

版本号由 `pubspec.yaml` 中的 `version` 字段控制：

```yaml
version: 1.2.3+45
```

- `1.2.3`：versionName（用户可见版本号）
- `45`：versionCode（内部版本号，必须递增）

Flutter 会自动将这些值映射到 Android 的 `versionName` 和 `versionCode`。

---

## 2. 发布流程（完整清单）

### Step 1: 确认版本号

编辑 `pubspec.yaml`：

```yaml
version: 1.2.3+46  # versionCode 递增
```

### Step 2: 清理并生成代码

```bash
flutter clean
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

### Step 3: 构建 Release APK 或 App Bundle

#### 构建 APK（直接分发）

```bash
flutter build apk --release
```

输出文件：`build/app/outputs/flutter-apk/app-release.apk`

#### 构建 App Bundle（推荐，用于 Google Play）

```bash
flutter build appbundle --release
```

输出文件：`build/app/outputs/bundle/release/app-release.aab`

**App Bundle 优势**：
- Google Play 会根据设备生成优化的 APK
- 减小下载大小
- 支持动态功能模块

### Step 4: 验证签名

检查 APK 是否已签名：

```bash
jarsigner -verify -verbose -certs build/app/outputs/flutter-apk/app-release.apk
```

预期输出包含：

```
jar verified.
```

### Step 5: 发布

#### 5.1 直接分发（APK）

- 上传 `app-release.apk` 到你的网站、GitHub Releases 或其他分发平台
- 用户下载并安装（需要允许"未知来源"）

#### 5.2 Google Play Store（App Bundle）

1. 登录 [Google Play Console](https://play.google.com/console/)
2. 选择你的 App（如果是新 App，先创建）
3. 进入 **Production** 或 **Testing** → **Create new release**
4. 上传 `app-release.aab`
5. 填写 Release Notes
6. 提交审核

#### 5.3 其他应用商店（如小米、华为等）

- 通常使用 APK
- 按各平台要求上传并填写应用信息
- 部分平台可能需要特殊签名或权限说明

---

## 3. Troubleshooting

### 构建失败：签名配置错误

**症状**：构建时提示 `Execution failed for task ':app:packageRelease'` 或签名相关错误。

**可能原因**：
- `android/key.properties` 不存在或路径错误
- Keystore 密码错误
- `storeFile` 路径不正确

**解决方案**：
1. 确认 `android/key.properties` 存在且配置正确
2. 检查 Keystore 文件路径（使用绝对路径或相对于 `android/` 的路径）
3. 测试 Keystore 密码：
   ```bash
   keytool -list -v -keystore /path/to/papertok-release-key.jks
   ```

### APK 安装后提示"应用未安装"

**可能原因**：
- Application ID 冲突（设备上已安装同 ID 的 App）
- 签名不匹配（之前安装的版本使用不同签名）
- APK 损坏

**解决方案**：
1. 卸载旧版本（如果 Application ID 相同）
2. 确保使用相同的 Keystore 签名（不要混用 Debug 和 Release 签名）
3. 重新构建 APK

### Google Play 上传失败："Version code X has already been used"

**症状**：上传 App Bundle 时提示 versionCode 已存在。

**解决方案**：
1. 修改 `pubspec.yaml` 中的 versionCode（`+` 后的数字）
2. 重新构建 App Bundle

### 构建时提示 "Execution failed for task ':app:lintVitalRelease'"

**症状**：Release 构建时 Lint 检查失败。

**临时解决方案**（不推荐长期使用）：

编辑 `android/app/build.gradle`：

```gradle
android {
    lintOptions {
        checkReleaseBuilds false
        abortOnError false
    }
}
```

**建议**：修复 Lint 警告（通常是权限声明或资源问题）。

### Keystore 丢失或密码忘记

**后果**：
- 无法更新已发布的 App（Google Play 要求签名一致）
- 用户需要卸载旧版本才能安装新版本

**预防措施**：
- 备份 Keystore 文件（多地备份）
- 记录密码（使用密码管理器）
- 考虑使用 Google Play App Signing（Google 托管 Keystore）

**补救方案**：
- 如果使用 Google Play App Signing，可以在控制台重新生成 Upload Key
- 否则需要发布新的 App（新 Application ID）

---

## 4. App Bundle vs APK 对比

| 特性 | App Bundle (.aab) | APK (.apk) |
|------|-------------------|-----------|
| 推荐用途 | Google Play 发布 | 直接分发、其他应用商店 |
| 文件大小 | 较大（包含所有资源） | 较小（单一 APK） |
| 用户下载大小 | 较小（Google Play 优化） | 与文件大小相同 |
| 多设备支持 | Google Play 自动生成多 APK | 单一 APK 支持所有设备 |
| 签名 | 可使用 Google Play App Signing | 自行签名 |

**建议**：
- Google Play 发布 → 使用 App Bundle
- 直接分发 → 使用 APK

---

## 5. 参考资料

- [Flutter - Build and release an Android app](https://docs.flutter.dev/deployment/android)
- [Google Play Console](https://play.google.com/console/)
- [Android - App signing](https://developer.android.com/studio/publish/app-signing)

---

## 6. 快速检查清单

发布前确认：

- [ ] `pubspec.yaml` 中的 versionCode 已递增
- [ ] Application ID 正确（与之前版本一致或已规划好新 ID）
- [ ] `android/key.properties` 配置正确
- [ ] Keystore 文件存在且密码正确
- [ ] 已执行 `flutter clean && flutter pub get && dart run build_runner build`
- [ ] 已成功构建 APK 或 App Bundle：
  - APK: `flutter build apk --release`
  - App Bundle: `flutter build appbundle --release`
- [ ] 签名验证通过（APK）
- [ ] 已备份 Keystore 文件和密码
- [ ] （Google Play）已登录 Play Console 并准备上传
- [ ] Release Notes 已准备

# 平台测试状态（Paper Reader / papertok-reader）

本文档记录本仓库的“实际验证过的平台范围”，用于对外说明与内部 QA 规划。

## 当前结论

- ✅ 已验证：iOS（iPhone） / iPadOS（iPad）
- ⏳ 计划验证：Android
- ⏳ 计划验证：桌面端（macOS/Windows/Linux）

> 如果你当前必须稳定使用 Android/桌面端，请优先使用上游项目 **Anx Reader**。

## iOS（已验证）

### 覆盖点（最小集）

- 首页导航 / Papers Tab / 阅读流程
- Reading page AI：dock / bottom sheet（iPad/iPhone）
- AI Provider Center：选择、启用/禁用、模型切换、思考档位
- 全文翻译：HUD、缓存、失败重试
- WebDAV 同步：不包含 api_key
- 备份恢复：plain 不含 api_key；可选加密携带 api_key

### 推荐的回归脚本

```bash
flutter pub get
flutter gen-l10n
# 如需：dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

## Android（计划中）

- 先跑 `flutter test -j 1` + `flutter run -d <android>`
- 验证 identifiers（applicationId/namespace）
- 验证 PaperTok / AI / 翻译基本链路

详见：`docs/engineering/RELEASE_ANDROID_zh.md`

## 桌面端（计划中）

- macOS：重点验证窗口尺寸、拖拽、快捷键、WebView
- Windows/Linux：重点验证 WebView2/依赖、文件权限、字体

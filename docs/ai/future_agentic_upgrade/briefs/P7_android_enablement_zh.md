# P7 Brief — Android 平台启用

> 前置:S1 批次 1(DB migration)必须先落地——全新安装建表 bug 在 Android 上同样致命,先修后测,否则 Android 回归第一轮就会被它污染。
> 用户拍板(2026-07-09):Android 要做;**不上大陆应用商店**(华为/应用宝/小米/OPPO 等全部不做),只走 Google Play + GitHub Releases APK 直发。大陆商店的 ICP/软著/多渠道打包合规工作全部出范围。
> DoD:Android 真机按 QA 清单系统性回归通过;Google Play internal track 上传链路验证可用;GitHub Releases 附 APK;`RELEASE_ANDROID_zh.md` 的"尚未系统性回归测试"免责声明移除。
> 最后更新:2026-07-09

## 现状(已核实)

- 代码/CI 已在:compileSdk 36、`build-android.yaml`/`build-playstore.yaml` CI、`android/fastlane/Fastfile` 的 Play 上传 lane、`android-v*` git tag 显示 Android 包一直在随版本切。
- 但 `docs/engineering/RELEASE_ANDROID_zh.md` 明言"本仓库目前只完成了 iOS 真机测试,Android 端尚未进行系统性回归测试"。
- 已知平台缺口(2026-07 审查):`assets/foliate-js/dist/` 自 3 月后未重建,Chrome<100 的老 WebView 走 legacy bundle 拿不到 B1 修复(现代 Android 走 src 路径不受影响);TTS 的 `system_tts` 后端行为需在 Android 上单独验证。

## 批次

1. **回归执行**:按 `docs/engineering/ANDROID_QA_CHECKLIST_zh.md` 在真机/模拟器走一遍主干(导入/阅读/选区高亮/AI Chat/研讨/PaperTok/搜索/TTS/同步),产出失败项清单记入本批 commit message(不新建文档);清单里逐项标 P0(崩溃/数据)/P1(功能)/P2(体验)。
2. **P0/P1 修复**:每个失败项一切片一 commit,遵循全局协议;Android 特有修复不得改动 iOS 已验收行为(改共享代码时必须说明 iOS 影响面)。
3. **发布链路验证**:`bundle exec fastlane supply` 到 internal track 走通一次;GitHub Releases 挂 APK 的产物脚本(复用现有 CI);Play 商店素材(截图/文案)最小集。
4. **收尾**:更新 `RELEASE_ANDROID_zh.md` 移除免责声明,记录 Android 发布 SOP 与 iOS SOP 的差异点(≤20 行)。

## 红线

- 不做任何大陆商店打包/合规/多渠道工作(用户拍板出范围)。
- 不为 Android 引入平台分叉的功能实现;共享代码的修复必须双平台过测试。
- 排期在 S1 批次 1 之后;与 E 线/G 线不抢真机验收带宽(Android 验收由模拟器+一台真机完成,不占 iOS 验收窗口)。

## 验证命令

```bash
flutter build apk --release
flutter analyze && flutter test
bash tool/check_repo_budgets.sh
```

commit 格式:`fix(android)/chore(release): <内容> (P7 batch N)`

# Swift Native 分支状态（PaperTok Reader / papertok-reader）

> 口径：本文档只描述 `swift-native` 工程轨，不替代 `product/main` 的产品状态文档。
>
> 更新时间：2026-04-13

## 0. 当前结论

- `swift-native` 已不是“初始化中的原型分支”，而是一个具备完整 App + Packages 结构、可持续收口的原生工程轨。
- 当前最新完成项是“中文增强闭环”的审计驱动收口：以 `Localizable.xcstrings` / `AppShortcuts.xcstrings` 为唯一字符串源，清理了已审计范围内的用户可见英文残留，并补上了自动化防回归。
- 本轮已用新鲜验证证据确认：
  - PTCore 本地化 helper 回归通过
  - PTFeatures 的 AIChat tool-failure 中文展示回归通过
  - App 侧的 catalog 完整性、硬编码英文审计、用户可见错误映射、Flutter migration 本地化回归通过
- 当前**可以**认为：`swift-native` 在“已审计的中文增强范围”内具备可持续维护的工程闭环。
- 当前**不应**认为：`swift-native` 已经完成全量产品对齐、全平台发布级验证，或可直接替代 `product/main` 成为唯一发布主线。

## 1. 已完成事项

### 1.1 原生工程基础已经建立

- 分支内已形成清晰的原生工程分层：
  - `App`
  - `Packages/PTCore`
  - `Packages/PTNetworking`
  - `Packages/PTAIServices`
  - `Packages/PTReader`
  - `Packages/PTFeatures`
  - `Packages/PTUI`
- 这意味着后续收口不再是“边搭架子边试错”，而是可以在既有模块边界上持续补齐功能、测试和文档。

### 1.2 中文增强闭环已完成的收口点

- 字符串源统一：
  - Swift Native 用户可见文案统一以 `Localizable.xcstrings` / `AppShortcuts.xcstrings` 为真值源。
  - 非 UI 层统一走 `AppLocalization`，减少散落英文字面量和多套调用风格。
- 共享 UI 与展示层：
  - notes / reader / settings / AI surfaces 中已审计范围的用户可见文案完成 catalog 驱动化。
  - AI tools 相关展示文案新增了独立的 UI 本地化层，不再直接把 tool raw name / description 当作中文界面文案使用。
- 用户可见错误：
  - share / shortcut / deeplink / migration 等会直接进入 UI 的错误信息已映射到 catalog key。
  - 修复了 `AppLocalization.format(...)` 重载歧义导致的 `...(null)` 插值问题。
- AI 聊天中文体验：
  - tool failure 在用户界面侧改为 `summary-first`，不再默认把底层英文错误或 JSON 机器负载直接暴露给用户。
- 审计和自动化防线：
  - catalog 覆盖测试
  - helper-based key 提取测试
  - 硬编码英文审计测试
  - 用户可见错误映射测试
  - built-in AI tool display key 覆盖测试

### 1.3 本轮新增的工程护栏

- `AppLocalization.format` 的 fallback 调用改为显式 `fallback:`，避免未来再次踩到无标签参数误选重载的问题。
- 新增 `AIToolPresentation`，把：
  - LLM contract 使用的 tool raw metadata
  - UI 展示使用的本地化 display text
  做了明确分层。
- 审计测试现在可以识别：
  - `localizedCatalogString(...)`
  - `localizedCatalogFormat(...)`
  - `aiChatLocalizedCatalogString(...)`
  - `aiChatLocalizedCatalogFormat(...)`
  避免 helper 包装把 catalog 覆盖测试绕空。

## 2. 最新验证证据

以下命令已在 2026-04-13 新鲜执行并通过：

### 2.1 PTCore 本地化 helper

```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTCore --filter AppLocalizationTests
```

结果：

- `AppLocalization` suite 通过
- `9` 个测试全部通过

### 2.2 PTFeatures AIChat 本地化回归

```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PTFeaturesPackageTests \
  -destination 'platform=iOS Simulator,id=62F2B125-7F4B-49EB-87A2-6493953A80D5' \
  -derivedDataPath /tmp/papertok-reader-ptfeatures-0413f \
  -clonedSourcePackagesDirPath /tmp/papertok-reader-apptests-targeted-0413e/SourcePackages \
  -only-testing:PTFeaturesTests/AIChatViewModelExtTests \
  test -quiet
```

结果：

- `AIChatViewModelExtTests` 通过
- 本轮新增的“tool failure 只显示本地化摘要”“JSON tool error 不外泄”回归通过

### 2.3 App 侧本地化闭环测试

```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PaperTokReaderAppTests \
  -destination 'platform=iOS Simulator,id=62F2B125-7F4B-49EB-87A2-6493953A80D5' \
  -derivedDataPath /tmp/papertok-reader-apptests-final-0413g \
  -clonedSourcePackagesDirPath /tmp/papertok-reader-apptests-targeted-0413e/SourcePackages \
  -only-testing:PaperTokReaderTests/HardcodedEnglishAuditTests \
  -only-testing:PaperTokReaderTests/MigrationLocalizationCatalogTests \
  -only-testing:PaperTokReaderTests/UserFacingLocalizationMappingTests \
  -only-testing:PaperTokReaderTests/FlutterMigrationServiceTests \
  test -quiet
```

结果：

- `HardcodedEnglishAuditTests` 通过
- `MigrationLocalizationCatalogTests` 通过
- `UserFacingLocalizationMappingTests` 通过
- `FlutterMigrationServiceTests` 通过

## 3. 当前仍然不应过度宣称的事项

### 3.1 还不能宣称“全量产品对齐完成”

- 这轮完成的是“中文增强闭环 + 防回归护栏”的一条主线。
- 这不等于：
  - `main` Flutter 产品行为的全量 parity 已重新验收
  - 所有 reader / settings / AI / import / share / sync / platform surfaces 都完成了新鲜人工 walkthrough
  - iPhone / iPad / macOS 三端都完成了发布级 UX 回归

### 3.2 还不能宣称“所有底层英文都已根除”

- 当前用户界面层的已审计范围已经闭环。
- 但一些底层 tool implementation 仍可能保留英文 / JSON / machine-oriented payload，这些现在主要被 UI 层安全地屏蔽掉了。
- 如果未来这些 payload 需要在更多系统表面复用，仍建议继续把高频错误逐步下沉到 PTAIServices 源头本地化。

### 3.3 仍存在预存警告

- Readium / WebKit / AVFAudio 相关并发与 `Sendable` 警告仍在。
- 它们不是这轮引入的失败，但如果要进入更严格的发布硬化阶段，建议单独开一轮 warning cleanup。

## 4. 建议的下一阶段工作

### P0：扩大验证面

- 继续跑与本轮改动邻近的 targeted suites：
  - `PTAIServices`
  - `PTUI`
  - `PTReader`
- 在 iPhone / iPad / macOS 做一轮人工本地化 walkthrough：
  - notes 空态
  - reader settings
  - AI tools settings
  - tool approval / tool result
  - share / shortcut / deep link 失败态

### P1：继续收口 spec parity

- 对照 `swift-native` 的 gap matrix / verification report，继续推进尚未重新验证的功能面。
- 重点不是“继续写代码”，而是把“已实现但未重新证实”的区域逐一转成有证据的完成状态。

### P1：补强源头级错误本地化

- 对当前最常出现的 tool errors 做源头 catalog 化，而不只依赖 UI 摘要兜底。
- 优先级建议：
  - utility tools
  - calendar / reminders
  - reader context tools
  - memory / search 工具

### P1：发布硬化

- 清理高噪声 warning
- 做签名 / 打包 / TestFlight / App Store 说明材料对齐
- 补 accessibility / performance / crash-path 检查

### P2：持续文档治理

- 保持“状态变化即更新文档”的节奏。
- 避免把 Swift Native 的状态散落在多份 plan / review / verification 草稿里。
- 后续如果 `swift-native` 成为长期并行工程轨，建议把：
  - branch status
  - parity matrix
  - verification report
  进一步收束为少数几份真值文档。

## 5. 建议的文档真值分工

- 如果你要看“当前产品主线状态”：优先看 [PROJECT_STATUS_AND_PLAN_zh.md](./PROJECT_STATUS_AND_PLAN_zh.md)
- 如果你要看“当前工程优先级”：优先看 [ROADMAP_zh.md](./ROADMAP_zh.md)
- 如果你要看“Swift Native 分支真实进展和最新验证证据”：优先看本文档


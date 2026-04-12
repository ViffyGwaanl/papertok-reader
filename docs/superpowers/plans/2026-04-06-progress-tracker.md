# Swift 原生迁移 — 整体进度追踪

**最后更新：** 2026-04-11
**分支：** `swift-native`

---

## 2026-04-11 Wave A macOS 编译穿透

今天新增的 fresh evidence：

- `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReader-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
  - ✅ 2026-04-11 fresh 通过

这条证据的意义不是“macOS 已完成”，而是：

- `PaperTokReaderMac` 不再只是 `xcodegen generate` / `xcodebuild -list` 层面的壳 target；
- Wave A 已经把最初的 macOS blocker 从“包图和共享代码根本编不过”推进到了“签名配置与后续产品 parity 仍待收口”；
- 当前剩余问题已经从 `Readium` 依赖图崩塌，收缩为后续 reader parity、app-shell 继续拆分，以及本机 development signing。

这轮实际解决的根因：

- `PTReader` 原先把 iOS-only `Readium` 依赖无条件带进 macOS 包图，导致 SwiftSoup / ZIPFoundation 最低平台要求先于业务代码炸掉；
- 共享 `ContentView` 里有直连 `ReadiumShared` / EPUB reader 的路径，会把整个 macOS app target 一起拖下水；
- 共享 SwiftUI 里仍有少量 iOS-only API，例：`topBarLeading`、`textInputAutocapitalization(.characters)`、`EditButton`。

当前结论：

- standalone macOS target 现在已有 fresh no-sign build path；
- signed development build 仍然是本机 team / provisioning 配置问题，不应再和代码编译根因混为一谈；
- macOS EPUB surface 目前是显式 gated 状态，这是 Wave A 为了让目标真正可编译而做的结构性穿透，不代表 FR-04 已闭环。

## 2026-04-11 Wave A app shell / DeepLink 收口

今天补上的另一组 fresh evidence：

- `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-deeplink-router CODE_SIGNING_ALLOWED=NO -only-testing:PaperTokReaderTests/DeepLinkRouterTests test`
  - ✅ 2026-04-11 fresh 通过
- `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReader-macOS -showBuildSettings | rg 'GENERATE_INFOPLIST_FILE|INFOPLIST_FILE|PRODUCT_BUNDLE_IDENTIFIER'`
  - ✅ 2026-04-11 fresh 通过
  - `GENERATE_INFOPLIST_FILE = NO`
  - `INFOPLIST_FILE = App/Platform/macOS/Info.plist`
  - `PRODUCT_BUNDLE_IDENTIFIER = ai.papertok.paperreader.mac`

这组收口的意义：

- `RootNavigationCoordinator` 不再只是把 `ContentView` 里的零散状态搬个位置，而是真正开始承担 app-shell 级 root request translation；
- `paperreader://reader/open?bookId=...` 现在不会再把 `open` 误判成书籍 ID，至少在 root route ingestion 这一层已经对齐 `main` 的主干 contract；
- route 切换时旧的 `pendingBookRequest` / `pendingAIRequest` / `sharedInboxImportRequest` 现在会被清掉，减少“隔一个 tab 又触发旧请求”的隐藏状态污染；
- standalone macOS target 现在也不再偷偷继承 share extension 的 `Info.plist`，而是有独立 app plist，说明这条 target 已进一步脱离“生成出来能编”但产品元数据仍然错位的阶段。

---

## 2026-04-10 收官重置

当前执行不再只依赖 2026-04-07 的 wave 文档，而是正式切换到“三层真相”：

- 最终契约：
  - `docs/superpowers/specs/2026-04-03-swift-migration-requirements.md`
  - `docs/superpowers/specs/2026-04-03-swift-native-migration-design.md`
- 收官设计：
  - `docs/superpowers/specs/2026-04-10-swift-native-full-spec-closure-design.md`
- 当前执行矩阵：
  - `docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md`
- 当前脏 worktree 分桶台账：
  - `docs/superpowers/plans/2026-04-10-swift-native-dirty-delta-ledger.md`
- 当前执行总计划：
  - `docs/superpowers/plans/2026-04-10-swift-native-full-spec-closure-master-plan.md`

新的控制原则：

- `2026-04-03` requirements/design 是最终验收契约；
- `2026-04-07` closure/verification 继续作为当前实现基线和历史证据；
- `main` Flutter 分支作为行为对照物；
- `iOS / iPad / macOS` 三端都必须达到原生规格，不能再把 “iOS app 兼容跑在 Mac 上” 当成完成。

今天新增的 fresh evidence：

- `swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'`
  - ✅ 2026-04-10 fresh 7 tests / 2 suites
- `swift test --package-path Packages/PTAIServices --filter 'ToolRegistryTests|ToolRuntimeContextTests'`
  - ✅ 2026-04-10 fresh 28 tests / 2 suites

核心结论：

- 当前分支已经进入完整收官工程，而不是“补几个尾项”；
- `Wave A` 的首要任务是统一 truth table、分桶当前 dirty delta、补独立 macOS target、拆解 app shell 热点文件，然后再进入大规模 subagent 并行。

---

## 2026-04-07 真相基线

这份文档不再把“能构建 / 能跑 TestFlight lane”当成“已完成 Swift 原生迁移”。

当前 authoritative 文档只有三份：

- `docs/superpowers/specs/2026-04-03-swift-migration-requirements.md`
- `docs/superpowers/specs/2026-04-03-swift-native-migration-design.md`
- `docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`

当前 fresh verification 文档：

- `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

核心结论：

- 当前分支已经拿到一组新的 build/test 证据，证明 repo 的**已实现面**可以继续稳定推进；
- 但当前分支仍然**不能**宣称已经完成 2026-04-03 规格中的全量 Swift-native 重写；
- TestFlight 现在只能算 release gate，不能再被当成规格完成的替代证明。

---

## 当前已 Fresh 验证

| 验证面 | 命令 | 结果 |
|------|------|------|
| Xcode 工程生成 | `xcodegen generate` | ✅ 通过 |
| Scheme 清单 | `xcodebuild -list -project PaperTokReader.xcodeproj` | ✅ `PaperTokReader` / `PTFeaturesPackageTests` / `PTReaderPackageTests` 均存在 |
| PTCore | `swift test --package-path Packages/PTCore` | ✅ 49 tests / 17 suites |
| PTCore 阅读时长子集 | `swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'` | ✅ 2026-04-09 fresh 7 tests / 2 suites；✅ 2026-04-10 fresh 7 tests / 2 suites |
| PTNetworking | `swift test --package-path Packages/PTNetworking` | ✅ 29 tests / 6 suites |
| PTUI | `swift test --package-path Packages/PTUI` | ✅ 5 tests / 2 suites |
| PTAIServices | `swift test --package-path Packages/PTAIServices` | ✅ XCTest 24 + Swift Testing 46 |
| Flutter migration 定向测试 | `xcodebuild ... -scheme PaperTokReaderAppTests ... -only-testing:PaperTokReaderTests/FlutterMigrationServiceTests test` | ✅ 3 tests / 1 suite |
| PTFeatures 目标回归矩阵 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/PapersViewModelTests -only-testing:PTFeaturesTests/PaperDetailDataLoaderTests -only-testing:PTFeaturesTests/PaperDownloadPlanTests -only-testing:PTFeaturesTests/PaperDownloadWorkerTests -only-testing:PTFeaturesTests/BookImportServiceEPUBTests -only-testing:PTFeaturesTests/BookshelfViewModelTests test` | ✅ 29 tests / 6 suites |
| PTReader iOS 全量测试 | `xcodebuild ... -scheme PTReaderPackageTests ... test` | ✅ 42 tests / 9 suites |
| PTAIServices runtime honesty 子集 | `swift test --package-path Packages/PTAIServices --filter 'ToolRegistryTests|ToolRuntimeContextTests'` | ✅ 2026-04-09 fresh 28 tests；✅ 2026-04-10 fresh 28 tests |
| PTReader PDFContentBridge 子集 | `xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/PDFContentBridgeTests test` | ✅ 2026-04-08 fresh 9 tests / 1 suite |
| PTReader PDFAnnotationBridge 子集 | `xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/PDFAnnotationBridgeTests test` | ✅ 2026-04-09 fresh 2 tests / 1 suite |
| PTReader EPUB 图片桥/协调器子集 | `xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/EPUBImageScriptBridgeTests -only-testing:PTReaderTests/EPUBNavigatorCoordinatorImageTests test` | ✅ 2026-04-09 fresh 3 tests / 2 suites |
| PTFeatures Reader/AI 子集 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/AIChatViewModelExtTests -only-testing:PTFeaturesTests/ReaderViewModelTests -only-testing:PTFeaturesTests/ReaderAIPanelPreferencesStoreTests test` | ✅ 25 tests / 3 suites |
| PTFeatures Reader Controls 子集 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test` | ✅ 2026-04-08 fresh 通过 |
| PTFeatures Reader Annotations + Controls 子集 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/EPUBReaderAnnotationsViewModelTests -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test` | ✅ 2026-04-08 fresh 21 tests / 4 suites |
| PTFeatures Reader 图片体验子集 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/ReaderImageAnalysisPromptTests -only-testing:PTFeaturesTests/ReaderImageExperienceControllerTests -only-testing:PTFeaturesTests/ReaderImageFileStoreTests test` | ✅ 2026-04-09 fresh 5 tests / 3 suites |
| PTFeatures PDF 注释 ViewModel 子集 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/PDFReaderAnnotationsViewModelTests test` | ✅ 2026-04-09 fresh 4 tests / 1 suite |
| PTFeatures Notes/Statistics 子集 | `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/NotesViewModelTests -only-testing:PTFeaturesTests/StatisticsViewModelTests test` | ✅ 2026-04-09 fresh 8 tests / 2 suites |
| App Platform iOS 测试 | `xcodebuild ... -scheme PaperTokReaderAppTests ... -only-testing:PaperTokReaderTests/AppAIToolContextFactoryTests ... -only-testing:PaperTokReaderTests/SharedInboxTests test` | ✅ 12 tests / 8 suites |
| App Share / Import 定向测试 | `xcodebuild ... -scheme PaperTokReaderAppTests ... -only-testing:PaperTokReaderTests/DeepLinkRouterTests -only-testing:PaperTokReaderTests/SharedInboxTests -only-testing:PaperTokReaderTests/ShareHandlerTests -only-testing:PaperTokReaderTests/SharedInboxImportProcessorTests test` | ✅ 通过 |
| App DeepLink Router 子集 | `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-deeplink-router CODE_SIGNING_ALLOWED=NO -only-testing:PaperTokReaderTests/DeepLinkRouterTests test` | ✅ 2026-04-11 fresh 通过 |
| App iOS 模拟器构建 | `xcodebuild ... -scheme PaperTokReader ... build` | ✅ 2026-04-07 fresh 通过；2026-04-08 与 2026-04-09（含 PDF 注释与 EPUB 图片查看器 delta）以 `iPhone 17 Pro (iOS 26.2)` destination 复跑也通过 |
| macOS target build settings | `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReader-macOS -showBuildSettings | rg 'GENERATE_INFOPLIST_FILE|INFOPLIST_FILE|PRODUCT_BUNDLE_IDENTIFIER'` | ✅ 2026-04-11 fresh 通过 |

---

## 这轮已实际收口的问题

### 1. 验证基线恢复

- `project.yml` 重新补回了 `PaperTokReader` app scheme。
- `xcodegen generate` 后，主 app 的 scheme 再次可被 `xcodebuild` 直接验证。
- `PTFeatures` / `PTReader` 现在有可用的 package test schemes，可以在 iOS Simulator 下跑真实测试。

### 2. Papers / 导入链路

- 书籍导入落盘路径改为稳定的 MD5 文件名，不再是随机 UUID。
- EPUB 导入现在会从真实样本提取 metadata 与 cover art，并落盘到 `Covers/`。
- Paper 下载取消现在会取消真实 `Task`，而不是只改 UI 状态。
- Paper detail 现在按当前 live API 真实 payload 解码，不再只依赖旧字段假设。
- 论文详情的 `zh/en` explanation / dialogue 选择已经贯通到 detail 加载与展示。
- 下载按钮现在有真实字节进度、导入阶段状态、原文链接和 raw markdown 链接。
- 已补上 EPUB 导入与下载策略相关测试；其中真实 EPUB fixture 现在覆盖 metadata + cover extraction。

### 3. Bookshelf 可操作性

- 书架删除现在保留 `pendingUndo` 状态，可以在 UI 上执行 Undo 恢复。
- `BookDAO` 新增恢复接口，Undo 会把软删除的书恢复回列表。
- 书架列表 context menu 现在包含 `Open` / `Edit` / `Delete` / `Move to Group` / `Tags`。
- 已补上书籍标题/作者的持久化编辑路径，并有 fresh regression test 证明会落库。
- 现在已有标签管理/筛选 sheet，与分组管理 sheet，用来真正 surfacing 现有 tag/group CRUD 能力。

### 4. AI Runtime 诚实性

- `spawn_sub_agent` 接受 `agentType` / `agent_type` 等别名，不再因参数名漂移而报错。
- `ToolRegistry.availableDefinitions(for:)` 会按运行时上下文过滤不可用工具。
- `AIChatViewModel` 只向模型暴露当前真正可运行的工具，避免“广告了但运行不了”。

### 5. 平台壳层集成已落到代码面

- `ContentView`、DeepLink、Share、Migration、App Intents、EventKit 相关文件已有一轮实装，不再只是空壳目录。
- 这些部分已经进入需要继续做规格对齐和行为补完的阶段，而不是从零开始搭脚手架。
- 这轮又补上了一组 app-level platform tests，fresh 覆盖了 `AppAIToolContextFactory`、`DeepLinkRouter`、`FlutterMigrationPlanner`、`FlutterMigrationService`、`MigrationLocalizationCatalog`、`PendingAIRequestStore`、`ShareExtensionInfoPlist`、`SharedInbox`。
- `AppAIToolContextFactoryTests` 现在改成纯 mock 依赖，不再把真实 EventKit 服务拖进测试运行时。
- `FlutterMigrationService` 的 schema/table preflight 现在接受 `<= expectedLegacySchemaVersion` 的受支持旧库，并有 fresh 定向测试证明。
- Deep-link 冷启动 pending destination 消费、Share Extension 激活规则、SharedInbox TTL cleanup 现在都有 fresh app-test 证据。
- Shared inbox 导入现在有独立 processor：全成功会消费 event，部分成功只保留失败书籍重试，丢失文件会被丢弃而不是无限 pending，并有 fresh app-test 覆盖。
- Share routing 现在已有 first-class `ask` contract：event 会持久化 `requestedRoute` 与 fallback 原因，`shortcuts/ask` 不再只是 `aiChat` 的解析别名。
- `directory scanning` 不再被模糊算进“已接近完成”的书架导入；它已被明确拆成单独 follow-up wave，需要后续专门做 bookmark / monitoring / unavailable-folder 流程。

### 6. Notes / Statistics 产品面收口

- Notes tab 现在已经有真实书名分组、总量 summary、note type 表达、markdown reader note 渲染，以及 Markdown / CSV / TXT 的 share/copy/export。
- Statistics tab 现在已经有 current/longest streak、week/month/year trends、nearly finished books、daily highlight 刷新，以及 dashboard tile 自定义持久化。
- Statistics 的日期 key 现在统一绑定到注入 `calendar.timeZone`，不再出现 streak / trend 的时区漂移。
- Statistics 现在加载全历史日阅读数据，而不是只取近 91 天，因此 longest streak 和 year view 不会再被 heatmap 窗口静默截断。
- Statistics 现在已经补上 FR-13.3 的 per-book trend breakdown，并在 UI 里有 `By Book` 细分面。
- PDF / EPUB reader 现在会通过共享 `ReadingSessionRecorder` 把原生 Swift 阅读会话落回 `tb_reading_time`，统计数据不再只能依赖 Flutter 迁移过来的旧记录。
- Statistics 的可见 label formatter 现在也绑定注入 `calendar.timeZone`，不会再出现 bucket date key 正确但周几/日期标签漂移的问题。
- `swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'` fresh 通过，证明 core 层的同日合并落库与 pause/resume/flush 会话累计行为成立。
- `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/NotesViewModelTests -only-testing:PTFeaturesTests/StatisticsViewModelTests test` 已在 2026-04-09 fresh 通过 8 tests / 2 suites，说明 Wave 5A 当前 Notes/Statistics delta 已补齐匹配的 iOS-side 复验证据，而不再只有 PTCore 层信心。

---

### 7. Reader parity 新增进展

- EPUB reader 现在已经有用户可见的 TOC 与全文搜索 sheet，背后直接走 `EPUBContentBridge`，不再只有底层 bridge/AI tool 能搜索。
- PDF reader 现在也补上了用户可见的全文搜索入口、结果列表与页跳转，背后复用了共享 `ReaderControlsViewModel` 和现有 `PDFContentBridge`。
- `ReaderViewModel` 现在显式暴露 live `contentBridge` 给 reader controls seam，避免 PDF 搜索 UI 继续靠重复解析文档或临时状态拼接。
- `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test` 已在 2026-04-08 fresh 通过。
- `xcodebuild ... -scheme PaperTokReader ... -destination 'id=725F8480-FA37-431F-B369-84059728E299' build` 已在 2026-04-08 fresh 通过，说明这轮 reader controls delta 不只是 package-level 自洽，也进了主 app 构建面。
- `PDFContentBridge.searchContent` 现在改成直接对原文做 Unicode-aware case/diacritic-insensitive 匹配，并修正最后一页结果的 `progression = 1.0`；`xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/PDFContentBridgeTests test` 已在 2026-04-08 fresh 通过 9 tests / 1 suite。
- EPUB 注释创建现在会拒绝“空选区 + highlight/note”这种非法组合，注释编辑器在这类 draft 下也会禁用保存按钮，不再把空内容笔记写入库；`xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/EPUBReaderAnnotationsViewModelTests -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test` 已在 2026-04-08 fresh 通过 21 tests / 4 suites。
- PDF 注释现在除了创建 / 书签 / 持久化 / 渲染外，还支持直接点击已渲染批注重新打开编辑器做更新或删除；`xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/PDFAnnotationBridgeTests test` 与 `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/PDFReaderAnnotationsViewModelTests test` 已在 2026-04-09 fresh 通过，分别证明 bridge 层和 view-model 编辑 draft 路径成立。
- EPUB reader 现在也补上了 FR-04.6 的图片查看器：Readium 会把图片点击经 JS bridge 转成原生图片资产，reader 可全屏查看、缩放/平移、双击回到 fit，并把该图片连同上下文 prompt 推送给现有 AI panel；`PTReader` 的 `EPUBImageScriptBridgeTests` / `EPUBNavigatorCoordinatorImageTests` 与 `PTFeatures` 的 `ReaderImageAnalysisPromptTests` / `ReaderImageExperienceControllerTests` / `ReaderImageFileStoreTests` 已在 2026-04-09 fresh 通过。

### 8. 2026-04-09 当前阻塞与未闭环点

- `swift test --package-path Packages/PTFeatures --filter StatisticsViewModelTests` 在跑到测试前就失败，根因是现有 Readium / SwiftSoup / ZIPFoundation 的 macOS deployment target 约束冲突，不是本次统计逻辑回归。
- 早先的 Xcode simulator destination / runtime mismatch 已不应再被视为当前 blocker：`xcrun simctl list devices available --json` 与 `xcodebuild -showdestinations` 现在都能看到 iOS 26.2 / 26.4 simulators，且 2026-04-08 的 destination-based package tests 与 app build 已再次成功。
- 但这不等于 Wave 2/5A 已经完全闭环：Wave 5A 的 PTFeatures/app 侧 fresh 证据现在已补齐，PDF 注释 bridge/view-model 新回归也已独立 fresh 通过，EPUB 图片查看器也已 fresh 落地；剩余 reader 侧主要缺口已经转移到 PDF 侧更深的设置对齐、TTS 的产品面与锁屏/后台行为，以及更完整的 FR-08 AI panel 产品面。

## 规格完成度快照

| 子系统 | 当前判断 | 说明 |
|------|------|------|
| FR-01 导航与基础壳 | 部分完成 | 6 tab 壳层、AI/Bookshelf/Settings 基础路径已存在，但 iPad/macOS/full customization 仍未验收 |
| FR-02 Papers | 部分完成 | 基础列表/筛选/下载/导入链路有实现，`zh/en` 与 detail metadata/progress 也已有一轮收口；但 authors/venue 仍受当前 API payload 限制，整体 UX 仍未完全对齐 |
| FR-03 Bookshelf | 部分完成 | 基础导入、列表、打开阅读器、tag/group 管理面、书籍编辑、EPUB cover extraction、shared inbox partial-failure hardening 已落地；但 custom order、拖拽重排、AI organize，以及已显式拆波次的 directory scanning 仍未完成 |
| FR-04/05 Reader | 部分完成 | EPUB/PDF reader-session 桥、统一 content bridge、PDF OCR fallback、EPUB 可见 TOC/搜索、PDF 可见全文搜索、EPUB 注释 create/edit/bookmark、PDF 注释 create/edit/delete/bookmark、EPUB 图片查看器 + AI 分析入口、EPUB per-book settings、以及 exact-locator EPUB 搜索跳转都已落地；但 PDF 侧设置对齐、以及完整 TTS 产品面仍未闭环 |
| FR-06/07/08/09/10/11 AI 系统 | 部分完成 | provider/tool/runtime 基础已打通，reader-aware tools 现在按 live session 诚实暴露；FR-08 也已有 dock/sheet/minimized bar 的 AI panel baseline，但 provider center、附件、历史、thinking/usage、完整工具与 RAG/Memory 体验仍未完成 |
| FR-12/13 Notes & Statistics | 部分完成 | Notes 的真实书籍上下文、类型表达、markdown note 显示、导出与 fresh regression 已落地；Statistics 的 streak/trends/completion/random highlight/tile customization、全历史准确性、per-book breakdown，以及原生 reader session 回写阅读时长的核心链路都已补上，且 2026-04-09 已补齐匹配的 PTFeatures iOS 复验证据；当前主要欠缺是 screen-level 交互验证深度 |
| FR-14 Sync & Backup | 明显未完成 | 只有部分底层 WebDAV / migration plumbing，远没有 fresh evidence 证明达到规格要求 |
| FR-15 TTS | 部分完成 | 基础 service 与测试存在，但完整用户功能未验收 |
| FR-16 Settings | 部分完成 | 页面壳层与部分偏好持久化存在，但 share presets/diagnostics/TTL、导航定制、AI/provider 深设置等规格深度远未覆盖 |
| FR-17 Platform Integration | 部分完成 | DeepLink / App Intents / Share / Migration 已进入集成阶段，`reader/open?bookId=...` 路由解析与 root request clearing 已 fresh 落地；但 shortcuts callback、reader locator parity、presets/diagnostics/headless parity 等仍未完成 |
| FR-18 Localization | 部分完成 | `.xcstrings` 在增长，但还没有完整覆盖验收 |
| FR-19 Flutter → Swift 数据迁移 | 部分完成 | migration service 已有实现，legacy schema preflight 兼容性也已补上；但远未能声称 1:1 迁移完成 |
| FR-20/21/22/23 MCP / KAIROS / Sub-Agent / Skills | 明显未完成 | 基础能力与内部运行时有雏形；其中 sub-agent 参数兼容性 bug 已修，MCP/KAIROS/skills 的终端产品面仍有明显差距 |

---

## 当前最重要的执行顺序

1. **Reader parity**
   - reader-session shell、OCR fallback、in-reader AI panel baseline、EPUB visible TOC/search、PDF visible search、EPUB annotation UX、EPUB per-book settings、以及 exact-locator EPUB 搜索跳转都已经落地；下一步最高杠杆切片应切到 PDF annotation，然后是图片查看器 / PDF 侧 settings parity / TTS。

2. **Wave 5A: Notes + Statistics productization**
   - FR-13.3 的结构性缺口已经补到 core + view-model + UI，并把 native reader reading-time persistence 接上；当前真正剩下的是补齐 PTFeatures / app 侧 fresh iOS 复验，以及必要的 screen-level 验证补强。

3. **AI Chat / Tools / Provider 体验对齐**
   - 在 reader-session seam 基础上，补 provider center、附件、历史、thinking/usage、reader-aware 工具闭环。

4. **Platform Integration + Migration**
   - 把 share / deep link / App Intents / Flutter 迁移做成真实可验收的行为，不再停留在“壳层已接线”。

5. **Bookshelf 外部目录扫描 follow-up**
   - 单独完成 directory scanning / bookmark / monitoring，不再和已闭环的 copy-import 混为一谈。

6. **Release / TestFlight**
   - 只在前面这些规格波次收口后再做 fresh archive/upload；
   - 否则 TestFlight 只能证明“当前壳层可以发包”，不能证明迁移完成。

---

## 当前不应再说的话

以下表述当前都不成立：

- “代码已基本收口”
- “只剩 provisioning 阻塞”
- “Swift 原生迁移已经完成，只差上传”
- “TestFlight 是最后唯一 blocker”

更准确的说法是：

- 当前 repo 的**构建与测试基线已经恢复并 fresh 通过**；
- 但离 2026-04-03 的完整 Swift-native 规格，仍有多波次子系统工作要做。

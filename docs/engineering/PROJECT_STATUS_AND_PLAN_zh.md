# 项目状态与完整计划（PaperTok Reader / papertok-reader）

> 口径：以 `product/main` 为准；以可审计（commit + 测试）为标准。
>
> 更新时间：2026-04-13

## 0. 当前结论

- RAG + Memory Phase 1-5 已完整交付并合入 `product/main`。
- Share / Shortcuts 主线已完成产品化收口，并在 `1.68.1 (6339)` 上完成真机验证：
  - `.md`
  - `.docx`
  - 网页分享（URL-first 可接受）
- 统一设置页 `Share & Shortcuts Panel` 已支持：
  - share 路由
  - prompt presets
  - cleanup / TTL
  - diagnostics
  - 会话目标（复用当前会话 / 新建会话）
  - 图片 / 文本附件上限配置
- 2026-03-07 已完成 3 个收口项：
  - diagnostics 搜索 / 筛选增强
  - Memory M1（manual-first）
  - `PaperTok Reader` 低风险命名收口
- 当前主线已从“补核心缺口”转入“后续增强 / 发布回归 / 下一阶段规划”。
- 上游吸收（`Anxcye/anx-reader` `v1.12.0..v1.14.0` 范围内）**Phase A + Phase B** 已完成落地与可回滚拆分，并已产出 TestFlight 包用于回归：`1.68.5 (6376)`。
  - PR：`https://github.com/ViffyGwaanl/papertok-reader/pull/7`
- 并行工程轨 `swift-native` 已进入“可持续收口”阶段；截至 2026-04-13，中文增强闭环与审计防回归已完成一轮工程化收口，但仍不应对外宣称为全量产品对齐完成。
  - 详见：`docs/engineering/SWIFT_NATIVE_STATUS_zh.md`

## 1. 已完成交付（Done）

### 1.1 RAG Phase 1-3（单书 -> 全书库）

- 单书 RAG：`semantic_search_current_book` + 引用跳转（`paperreader://reader/open?...`）。
- 全书库 RAG：`semantic_search_library`（Hybrid：FTS/BM25 + vector + 可选 MMR）+ 诊断字段。
- AI 索引（书库）：持久化队列（并发 = 1、失败自动重试一次、重启恢复 running -> queued、UI 可控）。

### 1.2 Memory Phase 4（Markdown source-of-truth + 可检索系统）

- Source-of-truth：`<documents>/memory/`（`MEMORY.md` + `YYYY-MM-DD.md`）。
- 本地检索：派生索引 `memory_index.db`（FTS/BM25/snippet），无 FTS5 时 best-effort 回退。
- 语义检索（Auto-on）：embeddings 可用时自动启用；不可用时自动关闭。
- Hybrid tuning：对齐 OpenClaw（vectorWeight/textWeight/candidateMultiplier）。
- 可选增强：MMR + temporal decay（默认 off）。
- 索引新鲜度：dirty + debounce 后台刷新；搜索不阻塞。
- Embedding cache：开关 + 上限 + LRU 清理（只清 embedding 字段，不删文本 chunk）。

### 1.3 Phase 5（备份 / 恢复与同步策略）

- WebDAV 同步：AI settings snapshot（排除 `api_key/api_keys`），timestamp newer-wins。
- Files/iCloud 备份：明文不含密钥；加密备份可包含密钥；导入回滚安全。
- 可选包含：`memory/` 与 `databases/ai_index.db(+wal/-shm)`。

### 1.4 OpenAI Responses 兼容性（第三方网关）

- 默认使用 `previous_response_id` 做 tool-call continuation（避免 brittle reasoning replay）。
- Provider Center 显式开关：
  - `responses_use_previous_response_id`
  - `responses_request_reasoning_summary`

### 1.5 Share / Shortcuts 产品化收口

- Share Sheet -> AI / Bookshelf 统一设置页。
- ask-after-open 流程稳定。
- mixed share policy B：混合分享默认去 AI，书架文件只作为 UI import cards。
- `.docx` / 文本文件以 AI 文本附件形式进入聊天。
- inbox cleanup / TTL / diagnostics 基础能力已交付。
- iOS 分享链路关键问题已修复：
  - docx/text-only share 不再“打开 App 但无效果”
  - iOS 附件路径编码问题（`Illegal percent encoding in URI`）已修复
  - Web share 保持 URL-first，富文本网页内容改走 Shortcuts

### 1.6 diagnostics 增强（2026-03-07）

- diagnostics 页支持：
  - 搜索
  - overall status 筛选
  - destination 筛选
  - kind 筛选
- 诊断事件结构化字段增强：
  - receive / routing / handoff / cleanup 状态链路
  - provider / host / eventId / failureReason
- 修复成功事件被误显示为 `pending` 的状态语义问题。

### 1.7 Memory 完整版（2026-04-14，TF 6442）

M1 已在 2026-03-07 上线。**2026-04-14 完成 B1+B2+B3 三阶段闭环**（详见 `docs/superpowers/plans/2026-04-14-memory-completion.md`）：

- **B1 源跳转** ✅
  - MemoryCandidate schema v1→v2 迁移（新增 bookId/cfi/chapter/sourceKind/tags/rationale 字段，读旧数据时自动补默认）
  - captureSessionDigest 自动记录当前阅读上下文
  - Review Inbox 每行新增 `Open in reader` / `Open conversation` 跳转按钮
  - 数据丢失回归测试（dismiss on legacy v1 data）
- **B2 顶层 Memory 入口** ✅
  - 新的 `MemoryHomePage` tab（可选加入底部导航，默认关闭）
  - 浏览 MEMORY.md 段落 + 最近 14 天日记
  - 长按进入多选模式 + 批量删除 / 加标签 toolbar
  - YAML front-matter 存储 tags（每个文件独立）
  - TagEditor inline 编辑
- **B3 可解释自动写入** ✅
  - 每条 candidate 生成 rationale 英文解释句
  - Review Inbox 显示 trigger badge + confidence dot（3 色：success/warning/tertiary）
  - Settings → Memory → "自动捕获规则" 分组，可开关 session_digest / provider_switch
  - MemoryRulePrefs 静态 helper 持久化 per-rule 开关

交付证据：
- 17 commits：`6050ee75` → `d43ff0e1`
- 43 个 memory 测试（原 0 个专用）全部通过
- TestFlight `1.68.7 (6442)`
- Subagent-driven development 流程：每个 task impl → spec review → quality review 两阶段 gate
- 在 Task 3 review 阶段捕获到一个数据丢失 bug（write path 没 fallback 到 v1 read）并修复

仍保持产品边界：
- long-term 默认确认后写入
- 不支持 silent auto-write 到 long-term（需用户在 Auto-capture rules 显式启用）

### 1.8 命名收口全部完成（2026-04-14）

三层收口全部落地：

**低风险层**（2026-03-07，已完成）
- README / docs / App 内文案 / l10n / iOS / Android 显示名统一为 `PaperTok Reader`

**中风险层**（Wave U commit `9cfced66`，2026-04-14）
- iOS `CFBundleName` / macOS `PRODUCT_NAME` + TEST_HOST / Linux `BINARY_NAME` + `APPLICATION_ID` / Windows project + Runner.rc 全部统一
- 清掉 `com.anxcye` / `Paper Reader` 等历史残留
- 证据：TestFlight `1.68.7 (6439)`

**高风险层**（Sub-project A2 commit `b0fe7c2b`，2026-04-14）
- `pubspec.yaml` `name: papertok_reader`
- **458 个 Dart 源文件**的 `package:anx_reader/...` → `package:papertok_reader/...`
- 原子 single-commit 落地，43/43 memory test 回归通过

命名层面不再有遗留工作。详见归档的 `docs/engineering/NAMING_CLEANUP_PLAN_zh.md`。

### 1.9 上游吸收：阅读器质量改进（v1.14 Phase A + B）（2026-03-22）

> 原则：不动 fork 已深改的 AI/chat 主干；优先吸收低耦合、稳定性收益明确的改动；中风险项按模块拆分，确保可回滚。

- Phase A（低风险，高收益）
  - 修复 read theme 颜色为空/非法导致的 RangeError
  - TOC 长章节名换行显示（wrap）
  - EPUB 图片溢出修复
  - i18n：系统 locale 不支持时 fallback 英文
  - Android 10+ 保存图片：移除不必要存储权限
- Phase B（中风险，挑点吸收）
  - 阅读背景图：Blur / Opacity + Fit mode（Cover / Stretch）
  - Header/Footer：section 模型（含 margin/fontSize）+ Prefs 向后兼容迁移 + 设置项 UI
  - TTS：修复 SystemTts 首句为空 crash + 阅读页播放快捷 FAB

交付与证据：
- PR：`https://github.com/ViffyGwaanl/papertok-reader/pull/7`
- TestFlight：`1.68.5 (6376)`

## 2. 当前未完成任务（Remaining）

### 2.0 Swift Native 工程轨（P1）

- `swift-native` 当前最值得保留的成果不是“又多了一批代码”，而是：
  - 用户可见中文残留的审计面已经建立
  - catalog / 错误映射 / 硬编码英文审计已经形成闭环
  - 后续新增功能若漏本地化，更容易第一时间被测试打红
- 下一步重点不应只是继续堆功能，而应继续把“已实现但未重新验证”的区域逐步转成有证据的完成状态。
- 独立状态文档见：`docs/engineering/SWIFT_NATIVE_STATUS_zh.md`

### 2.1 Memory 工作流 M2+（P2）

Memory 完整版 B1+B2+B3 已在 2026-04-14 上线。后续候选：

- 更多自动捕获规则：highlight streak / repeat question / 长按聊天消息"保存到记忆"
- AI chat conversation 深链（当前 openInConversation 只落到通用 AI tab，conversationId 级别跳转待 AiChatPage 支持 initial id 参数）
- 向量检索调参 / tag taxonomy 建议
- Cross-device sync 的 conflict 策略预研

### 2.2 命名收口（已完成归档）

三层收口全部落地于 2026-04-14。详见 `docs/engineering/NAMING_CLEANUP_PLAN_zh.md`（已归档为历史记录）。

### 2.3 构建 / 发布回归（P1）

- iOS：继续按 `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md` 执行 TestFlight 出包与回归。
- Android：按 `docs/engineering/RELEASE_ANDROID_zh.md` 做回归与发布准备。
- 平台回归：补齐 Android / 桌面端系统性验证。

### 2.4 上游吸收后续（P1）

- 合并 PR #7 后，补齐一次 iPhone + iPad 的回归记录（按 checklist 留证据）。
- 评估背景图旧语义（alignment/repeat）是否需要保留：
  - 如要保留，建议另起小 PR 增加 `bgimg-alignment` attribute 并在 paginator 背景层应用。
- TTS 增强（fromCfi 选区朗读 / 点击高亮暂停继续 / OnlineTts pitch/rate 修复 / 键盘翻页）保持为独立小 PR，不与 A+B 混做。

### 2.5 文档维护（持续）

- 保持“实现状态变化 = 同步更新 docs”的纪律。
- 继续把状态集中在少数真值文档，避免多处漂移。

## 3. 下一阶段建议计划

### Step 1（发布稳定性）

- 跑 iOS / iPadOS checklist。
- 如需新测试包，继续使用离线 TestFlight 流程：
  - `FLUTTER_NO_PUB=true FORCE_MANUAL_SIGNING=1 ./scripts/tf_from_commit.sh HEAD`

### Step 2（Memory M2 候选）

- 更多触发规则 + 向量检索调参
- AI chat conversation 深链（需要 AiChatPage 接 initial conversationId 参数）

### Step 3（命名收口）

~~已完成~~ 2026-04-14 三层全部落地。

### Step 4（多端回归）

- Android 真机回归
- 桌面端 smoke / packaging 验证

## 4. 风险与注意事项

- Memory 语义检索会将记忆文本发送到 embeddings provider；需要用户知情。
- 第三方 Responses 网关兼容性差异大：优先用 Provider Center 开关降级策略，不做自动重试猜测。
- ~~本轮命名收口只覆盖 outward-facing surfaces；技术标识仍保留历史值，这是刻意分层，不是遗漏。~~
- 2026-04-14 更新：技术标识层（Wave U 桌面 artifact + A2 Dart package rename）全部完成，命名工作全部落地。

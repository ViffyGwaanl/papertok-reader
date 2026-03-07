# 项目状态与完整计划（PaperTok Reader / papertok-reader）

> 口径：以 `product/main` 为准；以可审计（commit + 测试）为标准。
>
> 更新时间：2026-03-07

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

### 1.7 Memory M1 / M1.5 / M2（2026-03-07）

- workflow state 与 memory index cache 分离。
- 聊天显式入口已交付：
  - 保存到今日日记
  - 保存到长期记忆
  - 加入 Review Inbox
- 会话结束入口已交付：
  - 结束当前会话时生成 0-3 条 session digest candidate
  - 默认进入 Review Inbox，可切换为自动写入今日日记
- Memory 设置页已支持：
  - 最小 Review Inbox UI
  - session digest 开关
  - automated daily 路由切换
  - 长期记忆二次确认开关
- Markdown memory 写入已统一经过协调器，减少并发写路径踩踏风险。
- 仍保持产品边界：
  - long-term 默认确认后写入
  - 不支持 silent auto-write 到 long-term

### 1.8 低风险命名收口（2026-03-07）

- 对外产品口径统一为 `PaperTok Reader`。
- 已覆盖：
  - README / docs 入口
  - App 内可见文案 / l10n
  - iOS / Android 显示名
- 明确保留不变：
  - `anx_reader` package / import
  - bundle id / applicationId
  - URL scheme / App Group 等技术标识

## 2. 当前未完成任务（Remaining）

### 2.1 Memory 工作流后续阶段（P1）

M1.5 / M2 的稳定子集已完成；当前剩余增强项主要是：

- Review Inbox 的来源跳转 / 更完整审阅体验
- daily -> long-term 的周期性整理入口
- 更激进但仍可解释的 auto-daily 规则（如仅高置信度 / 更丰富触发器）
- 端到端真机回归与体验微调

详见：`docs/ai/memory_workflow_openclaw_alignment_zh.md`

### 2.2 命名收口后续阶段（P1 / P2）

本轮低风险收口已完成；后续仍可继续：

- 工作区路径 / 构建路径 / 发布产物口径统一
- macOS / 桌面 artifact naming 收口
- 高风险 package rename（`anx_reader -> papertok_reader`）单独立项评估

详见：`docs/engineering/NAMING_CLEANUP_PLAN_zh.md`

### 2.3 构建 / 发布回归（P1）

- iOS：继续按 `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md` 执行 TestFlight 出包与回归。
- Android：按 `docs/engineering/RELEASE_ANDROID_zh.md` 做回归与发布准备。
- 平台回归：补齐 Android / 桌面端系统性验证。

### 2.4 文档维护（持续）

- 保持“实现状态变化 = 同步更新 docs”的纪律。
- 继续把状态集中在少数真值文档，避免多处漂移。

## 3. 下一阶段建议计划

### Step 1（发布稳定性）

- 跑 iOS / iPadOS checklist。
- 如需新测试包，继续使用离线 TestFlight 流程：
  - `FLUTTER_NO_PUB=true FORCE_MANUAL_SIGNING=1 ./scripts/tf_from_commit.sh HEAD`

### Step 2（Memory 后续增强）

- Review Inbox 体验增强（来源跳转 / 更多上下文）
- daily -> long-term 整理入口
- auto-daily 规则细化与真机体验回归

### Step 3（命名第二阶段）

- macOS / 桌面 artifact naming 评估
- repo/path/release artifact 口径统一
- 如有必要，再单独出 package rename blast-radius 报告

### Step 4（多端回归）

- Android 真机回归
- 桌面端 smoke / packaging 验证

## 4. 风险与注意事项

- Memory 语义检索会将记忆文本发送到 embeddings provider；需要用户知情。
- 第三方 Responses 网关兼容性差异大：优先用 Provider Center 开关降级策略，不做自动重试猜测。
- 本轮命名收口只覆盖 outward-facing surfaces；技术标识仍保留历史值，这是刻意分层，不是遗漏。

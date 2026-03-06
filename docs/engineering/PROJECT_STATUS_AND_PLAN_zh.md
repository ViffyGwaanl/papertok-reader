# 项目状态与完整计划（PaperTok Reader / papertok-reader）

> 口径：以 `product/main`（同产品仓库 main）为准；以可审计（commit+测试）为标准。

## 0. 当前结论（2026-03-06）

- RAG + Memory Phase 1–5 已完整交付并合入 `product/main`。
- Memory 的**检索层**已完成对齐 OpenClaw 的 A→B→C→D（Hybrid 主干 + 可选增强 + 非阻塞索引新鲜度 + embedding cache 上限/清理）。
- Share / Shortcuts 主线已完成产品化收口，并在 `1.68.1 (6339)` 上完成真机验证：
  - `.md`
  - `.docx`
  - 网页分享（URL-only 可接受）
- 统一设置页 `Share & Shortcuts Panel` 已支持：
  - share 路由
  - prompt presets
  - cleanup / TTL
  - diagnostics
  - 会话目标（复用当前会话 / 新建会话）
  - 图片 / 文本附件上限配置
- 当前剩余工作重心已从“阻断性 bug 修复”转为：
  - Memory 工作流方案定稿
  - 命名收口计划
  - diagnostics 搜索 / 筛选增强

## 1. 已完成交付（Done）

### 1.1 RAG Phase 1–3（单书 → 全书库）

- 单书 RAG：`semantic_search_current_book` + 引用跳转（`paperreader://reader/open?...`）。
- 全书库 RAG：`semantic_search_library`（Hybrid：FTS/BM25 + vector + 可选 MMR）+ 诊断字段。
- AI 索引（书库）：持久化队列（并发=1、失败自动重试一次、重启恢复 running→queued、UI 可控）。

### 1.2 Memory Phase 4（Markdown source-of-truth + 可检索系统）

- Source-of-truth：`<documents>/memory/`（`MEMORY.md` + `YYYY-MM-DD.md`）。
- 本地检索：派生索引 `memory_index.db`（FTS/BM25/snippet），无 FTS5 时 best-effort 回退。
- 语义检索（Auto-on）：embeddings 可用时自动启用；不可用时自动关闭。
- Hybrid tuning：对齐 OpenClaw（vectorWeight/textWeight/candidateMultiplier）。
- 可选增强：MMR + temporal decay（默认 off）。
- 索引新鲜度：dirty + debounce 后台刷新；搜索不阻塞。
- Embedding cache：开关 + 上限 + LRU 清理（只清 embedding 字段，不删文本 chunk）。

### 1.3 Phase 5（备份/恢复与同步策略）

- WebDAV 同步：AI settings snapshot（排除 `api_key/api_keys`），timestamp newer-wins。
- Files/iCloud 备份：明文不含密钥；加密备份可包含密钥；导入回滚安全。
- 可选包含：`memory/` 与 `databases/ai_index.db(+wal/-shm)`。

### 1.4 OpenAI Responses 兼容性（第三方网关）

- 默认使用 `previous_response_id` 做 tool-call continuation（避免 brittle reasoning replay）。
- Provider Center 显式开关：
  - `responses_use_previous_response_id`
  - `responses_request_reasoning_summary`

## 2. 未完成任务（Remaining）

### 2.1 Memory 工作流（P0）

- 检索层已基本对齐 OpenClaw；未完成的是“写入工作流层”。
- 需要补齐：
  - `daily memory`
  - `long-term memory`
  - `review inbox`
  - 写入触发器
  - 候选审核流程
  - 自动化边界（尤其是 optional silent auto-write）
- 详见：`docs/ai/memory_workflow_openclaw_alignment_zh.md`

### 2.2 命名收口（P0/P1）

- 需要把产品名、仓库名、上游名、技术包名之间的边界正式收口。
- 当前最推荐先做：
  - 文档 / 文案统一成 `PaperTok Reader`
  - 把 `Anx Reader` 收敛为上游来源说明
- 高风险 package rename（`anx_reader -> papertok_reader`）暂不与当前收口混做。
- 详见：`docs/engineering/NAMING_CLEANUP_PLAN_zh.md`

### 2.3 diagnostics 搜索 / 筛选（P1）

- 当前 diagnostics 页已经存在，但仍缺：
  - 搜索
  - 状态筛选
  - destination 筛选
  - 文件类型筛选
- 这属于排障效率增强，而非阻断项。

### 2.4 构建/发布环境（P1）

- 发布：执行 `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md` / `docs/engineering/RELEASE_ANDROID_zh.md`。
- 继续保持 TF build 验证记录与文档同步。

### 2.5 文档维护（持续）

- 保持“实现状态变化 = 同步更新 docs”的纪律；尽量把状态集中在少数文档（避免多处漂移）。

## 3. 执行计划（可落地、可验收）

### Step 1（今天/下一次开发窗口）

- 运行门禁：`flutter test -j 1`（确保 main 绿）。
- 完成 iOS/iPadOS checklist 的 smoke + Phase3 + Memory + Responses 开关验证。

### Step 2（随后 1–2 天）

- Android checklist 回归。
- 若发现问题：按“复现步骤→最小修复→补测试→补文档”闭环。

### Step 3（发布）

- iOS：TestFlight 出包并回归。
- Android：如需要，打包并在目标设备回归。

## 4. 风险与注意事项

- Memory 语义检索会将记忆文本发送到 embeddings provider；需要用户知情。
- 第三方 Responses 网关兼容性差异大：优先用 Provider Center 开关降级策略，不做自动重试猜测。

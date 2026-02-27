# 项目状态与完整计划（PaperTok Reader / papertok-reader）

> 口径：以 `product/main`（同产品仓库 main）为准；以可审计（commit+测试）为标准。

## 0. 当前结论（2026-02-27）

- RAG + Memory Phase 1–5 已完整交付并合入 `product/main`。
- Memory 已完成对齐 OpenClaw 的 A→B→C→D（Hybrid 主干 + 可选增强 + 非阻塞索引新鲜度 + embedding cache 上限/清理）。
- OpenAI Responses 工具调用稳定性与第三方兼容已工程化（显式 Provider 开关）。
- 目前剩余工作重心是 **真机 QA checklist 执行** 与 **发布回归**（不是“合入阻塞”）。

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

### 2.1 真机 QA checklist（P0）

- iOS/iPadOS：执行 `docs/engineering/IOS_IPADOS_QA_CHECKLIST_zh.md`。
- Android：执行 `docs/engineering/ANDROID_QA_CHECKLIST_zh.md`。
- 重点覆盖：
  - Phase 3 队列生命周期（pause/resume/cancel/clear finished / retry-once / restart normalization）
  - deep link 外部拉起与定位（href/cfi）
  - Memory A–D（Auto-on、hybrid、MMR/decay、debounce freshness、cache limit）
  - OpenAI Responses 两个兼容开关的“严格/兼容”模式验证

### 2.2 构建/发布环境（P0/P1）

- iOS：本机 Xcode 缺少 iOS 平台组件（例如 iOS 26.2），需要在 Xcode → Settings → Components 安装后才能 `flutter build ios`。
- 发布：执行 `docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md` / `docs/engineering/RELEASE_ANDROID_zh.md`。

### 2.3 文档维护（P1）

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

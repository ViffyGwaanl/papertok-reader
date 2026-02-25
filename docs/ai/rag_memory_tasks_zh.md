# RAG + Memory（Phase 1–5）任务清单（含当前状态）

> 本文为工程任务清单（可直接用于验收/推进）。
> 
> Phase 3 详细设计与进度说明：`docs/ai/rag_phase3_library_rag_zh.md`

---

## Phase 1（已完成）— RAG 基建

- [x] 建立 `ai_index.db` 的基础打开/迁移/路径约定
- [x] 建立索引写入与读取的基础 DAO/服务层（可供工具调用）
- [x] 工具注册链路与 request scope 能力对齐（避免与聊天 streaming 相互 cancel）

交付状态：✅ 已合入产品仓库 `product/main`

---

## Phase 2（已完成）— 单书 RAG（当前书范围）

- [x] 支持对“当前书”构建语义索引（chunk + embedding 写入 `ai_index.db`）
- [x] 提供工具：`semantic_search_current_book`
- [x] evidence/jumpLink 使用 `paperreader://reader/open?...`（不再建议生成 `anx://...`）

交付状态：✅ 已合入产品仓库 `product/main`

---

## Phase 3（已完成并合入 main）— 全书库 RAG + 批量索引队列

### 已完成（截至 2026-02-25）

- [x] `ai_index.db` v2：新增 `ai_index_jobs`（队列持久化表）+ 扩展 `ai_book_index`（状态/重试/版本字段）
- [x] Headless Reader Bridge：不打开阅读页也能为任意 `bookId` 拉取 TOC/章节文本
- [x] Library index queue：runner（重试/重启归一化/单测）+ Riverpod service（pause/resume/cancel/clear finished + 节流刷新）
- [x] Settings 顶层入口：**AI 索引（书库）**（支持手动多选入队 + 队列控制）
- [x] Reader jump link：统一为 `paperreader://reader/open?...`

### 待完成（Phase 3 剩余成品项）

- [x] 书籍列表筛选与索引状态联动（DB 真值驱动）：
  - [x] 未索引 / 过期 / 已索引 的筛选来自索引库元信息（md5/provider/model/index_version）
  - [x] 列表展示与索引队列状态（queued/running/failed/succeeded）一致且可解释
- [x] `semantic_search_library`：全库检索工具 + 检索管线（Hybrid：FTS/BM25 + vector + MMR 去重）
- [x] 引用/evidence 跨书跳转体验打磨：
  - [x] jumpLink 统一为 `paperreader://reader/open?...`（bookId + cfi/href）
  - [ ] 对缺失定位信息的 fallback 行为可预期（例如章节开头）
- [ ] QA checklist + 回归（建议至少包含）：
  - [ ] 队列暂停/恢复/取消/clear finished 在边界状态下行为正确
  - [ ] 崩溃/重启：running→queued 归一化与续跑正确
  - [ ] 大书/多书索引时的前台卡顿、内存、耗电可接受
  - [ ] 网络失败/限流：重试与错误提示可理解
- [ ] 合入 `product/main`（完成上述验收后）

交付状态：✅ 已合入 `product/main`（建议按 QA checklist 做真机回归后再发 TestFlight）

---

## Phase 4（已完成）— Memory（本地 Markdown）

- [x] 本地 memory store：`<documents>/memory/`（`MEMORY.md` + `YYYY-MM-DD.md`）
- [x] Tools：`memory_read` / `memory_search` / `memory_append` / `memory_replace`
- [x] Memory 设置页/编辑页

交付状态：✅ 已合入产品仓库 `product/main`

---

## Phase 5（已完成）— 备份/恢复增强（可选包含索引/记忆）

- [x] v5 backup manifest flags：`containsMemory` / `containsAiIndexDb`
- [x] 导出：可选包含 `memory/`
- [x] 导出：可选包含 `databases/ai_index.db`（含 `-wal/-shm`），默认关闭
- [x] 导入：可选恢复 memory 与索引；未选择恢复时保留本地对应数据
- [x] 导入具备回滚保护（`.bak.<timestamp>`）

交付状态：✅ 已合入产品仓库 `product/main`

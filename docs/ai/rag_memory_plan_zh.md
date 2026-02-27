# RAG + Memory（Phase 1–5）总体计划与当前状态（工程口径）

> 适用仓库：**Paper Reader（papertok-reader）产品仓库**。
> 
> 本文用于对齐“RAG（检索增强）+ Memory（本地记忆）”这条线的 **分阶段交付边界、依赖关系与验收口径**。
>
> 说明：Phase 3 的设计细节与实现进度在独立文档维护：
> - `docs/ai/rag_phase3_library_rag_zh.md`

---

## 0. 总体目标与边界

### 0.1 目标

- **Phase 1–2：** 先把“当前书范围”的 RAG 跑通（可索引、可检索、可引用跳转）。
- **Phase 3：** 将 RAG 扩展到“全书库”，引入 **可恢复/可并发/可取消** 的批量索引队列，并提供产品级入口（AI 索引（书库））。
- **Phase 4：** 增加本地 **Markdown Memory**（MEMORY.md + 日记）与配套工具/设置页。
- **Phase 5：** 备份/恢复增强：在 v5 手动备份 ZIP 中，支持 **可选包含** `memory/` 与 `ai_index.db`（以及 `-wal/-shm`），并保持“默认不带敏感/大体积内容”的原则。

### 0.2 关键约束（持续有效）

- **隐私优先：** 默认不把向量索引纳入同步；手动备份也默认不包含 `ai_index.db`。
- **移动端资源约束：** 索引任务必须节流（并发/暂停/取消/重试），避免“长时间占用前台/电量”导致体验崩。
- **跳转链接规范：** Reader 跳转 deep link 以 `paperreader://reader/open?...` 为准；`anx://...` 为 legacy（文档中不再建议生成）。

---

## 1. Phase 划分（交付物 + 状态）

> 状态口径：以产品仓库 `main` 是否已合入为准。

| Phase | 主题 | 关键交付物（摘要） | 状态 |
|---|---|---|---|
| 1 | RAG 基建与索引落库（基础形态） | `ai_index.db` 基础 schema / 索引写入路径 / 工具注册与调用链路 | ✅ 已完成（已合入 `product/main`） |
| 2 | 单书 RAG（当前书范围） | `semantic_search_current_book`（或等价能力）；索引构建入口；引用片段与跳转链接（`paperreader://`） | ✅ 已完成（已合入 `product/main`） |
| 3 | 全书库 RAG + 批量索引队列 | `ai_index.db` 扩展（jobs/状态/FTS）；Headless Reader Bridge；“AI 索引（书库）”入口；全库检索工具 `semantic_search_library` | ✅ 已合入 `product/main` |
| 4 | Memory（本地 Markdown 记忆） | `<documents>/memory/`（MEMORY.md + daily notes）；memory_* tools；Memory 设置/编辑页 | ✅ 已完成（已合入 `product/main`） |
| 5 | 备份/恢复增强（可选包含索引/记忆） | v5 backup：manifest flags；可选包含 `memory/` 与 `databases/ai_index.db(+wal/shm)`；导入回滚与“可选恢复” | ✅ 已完成（已合入 `product/main`） |

---

## 2. Phase 3（已合入 main）验收边界（成品口径）

Phase 3 的“成品”定义为：用户能在 **Settings → AI → AI 索引（书库）** 看到队列与索引状态，并在 AI 对话中选择/触发 **全书库检索**，且引用来源可点击跳转到对应书籍位置。

### 2.1 已完成的 Phase 3 子交付（摘要）

以 `docs/ai/rag_phase3_library_rag_zh.md` 的“实现进度”章节为准，当前已具备：

- `ai_index.db` v2 迁移（队列表 `ai_index_jobs` + 索引元信息扩展）。
- Headless Reader Bridge（无需打开阅读页即可抽取任意 `bookId` 的 TOC/章节文本）。
- Library index queue（runner + service）：pause/resume/cancel/clear finished，含重启归一化与单测。
- Settings 顶层入口：**AI 索引（书库）**（支持多选入队与队列控制）。
- Reader jump link：已切换为 `paperreader://reader/open?...`。

### 2.2 Phase 3 收尾项（已合入 main，剩余为 QA/发布回归）

- **QA + checklist：**
  - iOS / Android 外部 deep link：`paperreader://reader/open?...` 拉起与定位（href/cfi）。
  - 索引队列：pause/resume/cancel/clear finished、失败自动重试一次、重启恢复。
  - 大书/多书索引时的前台卡顿、内存、耗电可接受。
- **发布回归：** 完成上述回归后再发布 TestFlight/版本（不再存在合入阻塞）。

---

## 3. 关联文档

- Phase 3 设计/进度：`docs/ai/rag_phase3_library_rag_zh.md`
- 任务清单（Phase 1–5）：`docs/ai/rag_memory_tasks_zh.md`
- 手动备份/恢复（含 memory/ 与 ai_index.db 可选包含）：`docs/ai/backup_restore_icloud.md`

---

## 2026-02-27 状态更新（对齐 OpenClaw 最佳实践）

本项目 Memory 已从“Markdown 文件 + substring 搜索”升级为可检索系统，核心目标对齐 OpenClaw `docs/concepts/memory.md` 的 IR pipeline。

### 已完成

- **M0（正确性）**：修复 daily 文件名/日期解析的正则错误，确保 `YYYY-MM-DD.md` 能被列出与按 date 参数读写。
- **M1（本地全文检索）**：新增派生索引 `memory_index.db`，优先使用 FTS5 + BM25 + snippet；不支持 FTS5 时 best-effort 回退原始逐行搜索。
- **M2（语义检索 Auto-on）**：对齐 OpenClaw 默认策略：当检测到可用 embeddings provider/key 时自动启用语义记忆检索；否则保持禁用。
- **A（Hybrid 参数对齐）**：提供 `vectorWeight/textWeight/candidateMultiplier` tuning，默认值对齐 OpenClaw 推荐（0.7/0.3/4）。
- **B（增强项，默认 off）**：提供可选的 MMR 多样性重排与 temporal decay（daily 生效，MEMORY.md evergreen 不衰减）。
- **C（索引新鲜度）**：引入 dirty + debounce 异步索引刷新（不阻塞搜索），写入口触发后台重建。
- **D（缓存控制）**：embedding 缓存可配置开关与上限，超过上限按 embedded_at LRU 清理。
- **安全**：`memory_*` AI 工具执行日志脱敏（不记录正文），降低隐私泄露风险。

### 关键配置入口

- 设置页：Settings → Memory
  - 语义记忆检索（Auto/手动覆盖）
  - Advanced：Hybrid 权重、候选池倍率、MMR、Temporal decay、Embedding cache

### 风险与边界

- 语义检索依赖 embeddings provider：开启后会将记忆文本发送到所选 provider 进行 embedding（需用户理解风险）。
- `memory_index.db` 为派生缓存：可删除后重建；首次使用可能触发后台构建。


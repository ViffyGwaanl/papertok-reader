# Memory 检索（对齐 OpenClaw）

本文档总结 PaperTok Reader（anx-reader）在 Memory 功能上与 OpenClaw `docs/concepts/memory.md` 对齐的设计与实现状态，并给出后续可选增强。

## 目标与范围

- **目标**：让“记忆”从纯文件存储升级为可检索系统（IR pipeline），提升命中率、排序质量与可维护性。
- **范围**：仅讨论 Memory 的读/写/检索与索引；不讨论聊天历史（History）持久化策略。

## 与 OpenClaw 对齐的关键点

### 1) Source of truth = Markdown

- 记忆的真相来源仍是 Markdown 文件：`memory/` 目录下的 `MEMORY.md` 与 `YYYY-MM-DD.md`。
- 索引是派生缓存（derived cache），允许删除后重建。

### 2) 本地全文检索（FTS/BM25）

- 引入派生索引 DB：`memory_index.db`（位于 app databases 目录）。
- 将 Memory 文件按段落分块写入 `memory_chunks`，并在可用时建立 FTS5 虚表 `memory_chunks_fts`。
- 检索默认返回 snippet + file + line（以及可选 endLine），用于 UI 展示和 AI 工具消费。
- 若平台 SQLite 不支持 FTS5：自动回退到原始文件逐行搜索（best-effort）。

### 3) 语义检索（Embedding）Auto-on（OpenClaw 风格）

- 默认策略：Auto。
  - 若检测到可用 embeddings provider/key，则自动启用语义记忆检索。
  - 若不可用，则自动关闭（保持功能可用，仅走文本检索/回退）。
- 语义检索以“候选召回 + 向量重排”的方式运行，并提供 vector-only fallback（候选为空或 FTS 不可用时）。

### 4) Hybrid（BM25 + vector）参数对齐

- 默认启用 hybrid，并提供 tuning：
  - `hybrid.enabled=true`
  - `vectorWeight=0.7` / `textWeight=0.3`（归一化后使用）
  - `candidateMultiplier=4`（候选池倍率）

### 5) 索引新鲜度：非阻塞刷新（debounce）

- 不依赖移动端 OS watcher；采用事件驱动 dirty + debounce：
  - Memory editor 保存
  - `memory_append`/`memory_replace`
  - 导入/恢复 memory/
  都会触发索引后台刷新。
- Memory 搜索不阻塞等待索引完成：若索引为空则后台重建，本次回退 raw search。

### 6) 缓存控制与安全

- Embedding 缓存：可配置开关与上限（避免 DB 无限膨胀）；超过上限会按 embedded_at LRU 清理（仅清空 embedding 字段，不删文本 chunk）。
- AI 工具日志：对 `memory_*` 工具的正文内容做脱敏，避免把 memory 正文落到日志。

## 可选增强（未来）

- **诊断输出**：在 `memory_search` 结果中补充 `usedFts/usedVectorFallback/candidates/indexedChunks` 等字段，便于排障。
- **结果质量增强**：MMR 多样性重排与 temporal decay（当前为可选增强，默认 off）。
- **更强的权限/作用域**：类似 OpenClaw 的 DM-only scope 与可配置 citations。


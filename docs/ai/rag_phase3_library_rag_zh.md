# Phase 3：全书库 RAG + 批量索引队列（设计方案，贴合 papertok-reader / anx-reader 代码结构）

> 目标：在现有 **Riverpod + services** 架构上，为 Paper Reader（papertok-reader）引入“全书库可检索知识库（RAG）”，并提供**可恢复、可并发、可取消**的批量索引队列。
>
> 本文聚焦“可落地的工程设计”，默认代码库为：`anx-reader`（Flutter），AI 面板与 Agent streaming 已存在（`lib/providers/ai_chat.dart`、`lib/service/ai/index.dart`）。

---

## 0. 范围与原则

### 0.1 Phase 3 解决什么问题

- 让 AI 对话不再局限于“当前章节/当前书”，而可以在用户**整个书库**中做检索增强（RAG）。
- 书库内容需要离线可用：必须先对书籍进行**索引**（抽取文本 → 分块 → embedding → 写入索引库）。
- 索引不是一次性脚本，而是**可持续维护的后台任务系统**：支持批量、重试、暂停、取消、并发、失败可见。

### 0.2 非目标（本阶段不做 / 先不做）

- 不把索引库纳入 WebDAV 同步（体积、隐私、安全、平台差异成本过高）。
- 不做“跨设备一致的向量索引”与云端 ANN 服务。
- 不追求一次性支持超大库（> 5,000 本、千万级 chunk）的极限性能；先落地**可工作**的架构，并预留后续 ANN/HNSW 的升级点。

### 0.3 关键约束

- **移动端资源约束**：CPU/内存/IO/电量；索引需要节流（Wi‑Fi/充电/前后台策略）。
- **隐私**：索引库包含书籍原文片段与 embedding，默认仅本地存储；提供一键清理。
- **现有架构对齐**：
  - 配置：`Prefs()`（`lib/config/shared_preference_provider.dart`）
  - 数据库：`sqflite` + `DBHelper` 风格（`lib/dao/database.dart`）
  - Provider：Riverpod `@Riverpod(keepAlive: true)` 与 service 分层

---

## 1. 总体架构（服务分层 + 数据流）

### 1.1 模块划分（建议的目录结构）

> 仅为 Phase 3 的“最小新增模块”，尽量沿用现有 patterns。

- `lib/service/ai/rag/`
  - `ai_index_db.dart`：`ai_index.db` 打开/迁移/路径（类比 `DBHelper`）
  - `rag_schema.dart`：DDL 常量、schema version
  - `rag_dao.dart`：文档/分块/embedding/队列 job 的读写
  - `rag_indexer.dart`：单书索引流水线（extract → chunk → embed → write）
  - `rag_queue_service.dart`：队列 worker、lease、并发/取消
  - `rag_retriever.dart`：Hybrid 检索（FTS + vector）+ MMR
  - `rag_mmr.dart`：MMR 与去重工具（纯 Dart，可测试）

- `lib/providers/ai_rag/`
  - `rag_queue_provider.dart`：队列状态（running/paused + job 列表/统计）
  - `rag_settings_provider.dart`：将 Prefs 映射到 UI（可选）

- `lib/page/settings_page/`
  - `ai_library_rag.dart`：新的 Settings 子页（入口放在 Settings → AI 下）

- `lib/widgets/ai/`
  - 读页 AI 面板增加“上下文范围：当前书 / 全书库”的 UI 与引用展示

### 1.2 数据流（ASCII）

```
Books (tb_books)  ──►  RagQueueService.enqueueAll()/enqueue(book)
                         │
                         ▼
                  rag_index_jobs (ai_index.db)
                         │  (lease + workers)
                         ▼
      RagIndexer: extract → chunk → embed → write
                         │
                         ▼
        rag_chunks + rag_chunks_fts + rag_embeddings
                         │
                         ▼
   RagRetriever (FTS + vector) → MMR → context snippets
                         │
                         ▼
      AI chat prompt injection (agent/tool 或 system prompt)
```

---

## 2. 数据模型：扩展 `ai_index.db`

### 2.1 为什么使用独立 DB（`ai_index.db`）

- 主库 `app_database.db`（`tb_books`/`tb_notes` 等）是业务核心；索引库会明显增大、写入频繁，独立 DB 能：
  - 减少主库碎片化与锁竞争
  - 方便一键删除/重建（隐私/空间）
  - 允许使用不同 PRAGMA（WAL/同步等级/缓存）

**路径**：复用 `getAnxDataBasesPath()`（`lib/utils/get_path/databases_path.dart`），文件名固定 `ai_index.db`。

### 2.2 schema version 与迁移方式

- `ai_index.db` 独立维护 `currentAiIndexDbVersion`（从 1 开始）。
- 迁移风格沿用 `DBHelper.onUpgradeDatabase(db, old, new)` 的 switch/case。

### 2.3 表设计（核心）

下面给出推荐 schema（DDL 为伪 SQL，便于实现时微调）。

#### 2.3.1 `rag_documents`（按书/文档维度）

用途：记录每本书的索引元信息与“是否需要重建”。

关键点：使用 `book_id` 对齐主库；同时保存 file fingerprint（md5 + mtime + size）以判断增量更新。

```sql
CREATE TABLE rag_documents (
  doc_id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- join key
  book_id INTEGER NOT NULL UNIQUE,

  title TEXT,
  author TEXT,
  file_path TEXT,
  file_md5 TEXT,
  file_size INTEGER,
  file_mtime_ms INTEGER,

  format TEXT,            -- epub/pdf/txt
  language TEXT,          -- optional

  -- indexing
  index_version INTEGER NOT NULL DEFAULT 1,      -- pipeline version
  chunk_policy_version INTEGER NOT NULL DEFAULT 1,
  embed_model_key TEXT NOT NULL,                 -- e.g. "openai:text-embedding-3-small" or custom

  indexed_at_ms INTEGER,
  last_error TEXT,

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER
);

CREATE INDEX idx_rag_documents_book_id ON rag_documents(book_id);
CREATE INDEX idx_rag_documents_updated_at ON rag_documents(updated_at_ms);
```

> `embed_model_key`：为了支持“更换 embedding 模型后重建”，需要把向量模型写入索引元数据。

#### 2.3.2 `rag_chunks`（分块内容表，真实内容存放处）

- 存储 chunk 文本（用于引用、用于 FTS external content）。
- 保存定位信息（EPUB: href/cfi；PDF: page range；TXT: byte offset）。

```sql
CREATE TABLE rag_chunks (
  chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,
  doc_id INTEGER NOT NULL,

  chunk_index INTEGER NOT NULL,     -- 0..n
  text TEXT NOT NULL,
  text_hash TEXT,                  -- optional: sha1/xxhash for dedup

  -- location (best-effort, schema 允许为空)
  chapter_title TEXT,
  href TEXT,
  cfi_start TEXT,
  cfi_end TEXT,
  page_start INTEGER,
  page_end INTEGER,

  char_count INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,

  FOREIGN KEY (doc_id) REFERENCES rag_documents(doc_id) ON DELETE CASCADE
);

CREATE INDEX idx_rag_chunks_doc ON rag_chunks(doc_id, chunk_index);
CREATE INDEX idx_rag_chunks_hash ON rag_chunks(text_hash);
```

#### 2.3.3 `rag_chunks_fts`（FTS5 表）

- 用于关键词检索与 BM25 排序。
- 推荐使用 **external content**（内容存 `rag_chunks.text`），降低重复存储。

```sql
CREATE VIRTUAL TABLE rag_chunks_fts USING fts5(
  text,
  doc_id UNINDEXED,
  chunk_id UNINDEXED,
  tokenize = 'unicode61'
  -- 可选：prefix = '2 3 4'
);

-- 写入策略：插入 chunk 后同步插入 fts 行：
-- INSERT INTO rag_chunks_fts(rowid, text, doc_id, chunk_id) VALUES (chunk_id, text, docId, chunkId);

CREATE INDEX idx_rag_chunks_fts_doc ON rag_chunks_fts(doc_id);
```

> 兼容性提示：如果某平台 SQLite 未编译 FTS5，需要 fallback（Phase 3 可先做“FTS 缺失时禁用关键词检索，仅用向量/或仅用 LIKE”）。

#### 2.3.4 `rag_embeddings`（chunk embedding 向量）

- 向量以 `Float32List` 序列化为 `BLOB`（小端 float32）。
- 存储 `dim` 与 `normalized` 标记（建议索引时就做 L2 normalize，检索时可用 dot≈cos）。

```sql
CREATE TABLE rag_embeddings (
  chunk_id INTEGER PRIMARY KEY,
  doc_id INTEGER NOT NULL,

  model_key TEXT NOT NULL,
  dim INTEGER NOT NULL,
  normalized INTEGER NOT NULL DEFAULT 1,
  vec BLOB NOT NULL,

  created_at_ms INTEGER NOT NULL,

  FOREIGN KEY (chunk_id) REFERENCES rag_chunks(chunk_id) ON DELETE CASCADE
);

CREATE INDEX idx_rag_embeddings_doc ON rag_embeddings(doc_id);
CREATE INDEX idx_rag_embeddings_model ON rag_embeddings(model_key);
```

> 设计选择：单 chunk 一个向量，便于精确引用与 MMR；后续如需 ANN，可引入额外表/文件存 HNSW graph。

#### 2.3.5 `rag_doc_embeddings`（可选但强烈建议：文档级向量）

用途：先在 doc 级别做粗筛，避免对全库 chunk 做线性扫描。

```sql
CREATE TABLE rag_doc_embeddings (
  doc_id INTEGER PRIMARY KEY,
  model_key TEXT NOT NULL,
  dim INTEGER NOT NULL,
  normalized INTEGER NOT NULL DEFAULT 1,
  vec BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,

  FOREIGN KEY (doc_id) REFERENCES rag_documents(doc_id) ON DELETE CASCADE
);

CREATE INDEX idx_rag_doc_embeddings_model ON rag_doc_embeddings(model_key);
```

生成方式：对 doc 内所有 chunk embedding 做平均（或加权平均），再 normalize。

#### 2.3.6 `rag_index_jobs`（索引队列表，持久化状态机）

```sql
CREATE TABLE rag_index_jobs (
  job_id INTEGER PRIMARY KEY AUTOINCREMENT,

  book_id INTEGER NOT NULL,
  doc_id INTEGER,

  -- scheduling
  priority INTEGER NOT NULL DEFAULT 0,
  reason TEXT,                      -- import/repair/rebuild/manual

  -- state
  status TEXT NOT NULL,             -- queued/running/succeeded/failed/canceled/paused
  stage TEXT NOT NULL,              -- discover/extract/chunk/embed/write/finalize
  progress_current INTEGER NOT NULL DEFAULT 0,
  progress_total INTEGER NOT NULL DEFAULT 0,

  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,

  -- lease (for concurrency)
  lease_owner TEXT,
  lease_expires_at_ms INTEGER,

  cancel_requested INTEGER NOT NULL DEFAULT 0,

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  started_at_ms INTEGER,
  finished_at_ms INTEGER
);

CREATE INDEX idx_rag_jobs_status ON rag_index_jobs(status, priority, created_at_ms);
CREATE INDEX idx_rag_jobs_book ON rag_index_jobs(book_id);
CREATE INDEX idx_rag_jobs_lease ON rag_index_jobs(lease_expires_at_ms);
```

> `lease_owner` 建议使用随机 UUID（app run id）+ worker id（例如 `run:<uuid>/w:1`），便于调试。

#### 2.3.7 `rag_index_events`（可选：调试日志/可观测性）

```sql
CREATE TABLE rag_index_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id INTEGER NOT NULL,
  level TEXT NOT NULL,          -- info/warn/error
  message TEXT NOT NULL,
  ts_ms INTEGER NOT NULL
);

CREATE INDEX idx_rag_events_job ON rag_index_events(job_id, ts_ms);
```

---

## 3. 索引队列：状态机 + 并发/取消策略

### 3.1 Job 状态机（status + stage）

> status 表示“宏观生命周期”，stage 表示“流水线阶段”。

**status**：
- `queued`：等待执行
- `running`：某 worker 已 lease 并执行中
- `succeeded`：成功
- `failed`：失败（可重试）
- `canceled`：用户取消
- `paused`：队列全局暂停时，未执行的 job 标记为 paused（或仅内存暂停也可；推荐落库便于恢复）

**stage**（推荐枚举）：
- `discover`：读主库 book 元信息、判断是否需要索引
- `extract`：抽取全文/章节文本（EPUB headless webview / PDF extractor / TXT read）
- `chunk`：分块（chunk size + overlap）
- `embed`：对 chunk 调 embedding API（并发受控）
- `write`：写入 `rag_chunks` + fts + embeddings
- `finalize`：更新 `rag_documents` / doc embedding / 清理临时数据

状态迁移（简图）：

```
queued ──► running ──► succeeded
  │           │
  │           ├──► failed (attempts++) ──► queued (retry) / failed (terminal)
  │           └──► canceled
  └──► paused ──► queued
```

### 3.2 并发模型：多 worker + lease（避免重复执行）

- 使用 `rag_index_jobs` 做 **唯一事实来源**（single source of truth）。
- worker 通过“租约（lease）”认领任务：
  1) `SELECT` 一条满足条件的 job（`status='queued'` 或 `status='paused'` 且允许恢复）
  2) 在同一 transaction 中 `UPDATE` 该 job：写入 `lease_owner`、`lease_expires_at_ms=now+ttl`、`status='running'`、`started_at_ms`。
  3) 若 `UPDATE` 影响行数为 0 → 说明被其他 worker 抢走，重试。

- `ttl` 建议 30~120 秒；worker 在长阶段（extract/embed）需要周期性续租（更新 `lease_expires_at_ms`）。
- app 被杀 / 崩溃：lease 过期后，其他 worker 可重新认领（从 stage 重新开始或从可恢复点继续）。

### 3.3 取消策略（Cancel）

**目标**：用户点“取消”能尽快生效，同时保持 DB 一致性。

- 取消由“写标记”实现：
  - `UPDATE rag_index_jobs SET cancel_requested=1 WHERE job_id=?;`
- worker 在以下时机检查 `cancel_requested`：
  - stage 边界（extract/chunk/embed/write）
  - embed 循环内（每处理 N 个 chunk）
  - 大型 IO 操作前后（例如写入大量 rows）

取消后处理：
- 将 status 置为 `canceled`，写入 `finished_at_ms`。
- 清理“临时写入”（推荐写入阶段采用“先写临时 doc_id，再 finalize 替换/事务提交”的策略；见 4.4）。

### 3.4 暂停策略（Pause）

两种实现均可：

1) **仅内存暂停**（简单）：`RagQueueService` 内部不再启动新 lease；running job 不强停。
2) **落库暂停**（更可靠）：
   - 全局 pause 时，将 `status='queued'` 的 job 批量置为 `paused`。
   - resume 时，将 `paused` 置回 `queued`。

建议 Phase 3 使用 (1)+(2) 混合：UI pause 时落库（便于重启恢复），但不强行中断 running。

### 3.5 并发与节流（移动端）

- worker 并发数：`Prefs().libraryRagIndexConcurrency`（建议 1~4）。
- embed 子并发：每个 job 内部对 embedding API 的并发（建议 2~8，取决于 provider）。
- 触发条件（Settings 可选）：
  - 仅 Wi‑Fi
  - 仅充电
  - 前台优先 / 允许后台（iOS/Android 行为不同，先做“前台 + 屏幕亮”安全版本）

---

## 4. 索引流水线（RagIndexer）

### 4.1 判定是否需要重建（增量策略）

对每本书建立 fingerprint：

- `file_md5`（已有：`tb_books.file_md5`）
- `file_mtime_ms`（文件最后修改）
- `file_size`
- `index_version`（pipeline 版本）
- `chunk_policy_version`（chunk 策略变更时强制重建）
- `embed_model_key`（embedding 模型变更时强制重建）

需要重建的条件：
- 书籍 fingerprint 变化
- 用户点击“Rebuild all”
- embed model key 变化
- schema 迁移且不兼容

### 4.2 内容抽取（extract）——复用现有 webview 能力

**EPUB**：推荐沿用现有阅读器 JS 能力：
- 现有 `EpubPlayer` 已实现 `getBookContent(...)` 并通过 `chapterContentBridgeProvider` 暴露给 AI tools。
- Phase 3 索引需要“离线、非当前阅读 session”的抽取：
  - 新增 `HeadlessEpubContentExtractor`：类似 `getBookMetadata()` 的 headless webview 模式，加载该 epub，然后调用同一套 JS `getBookContent`。
  - 产出：`{ content, sectionCount, includedSections, truncated, ... }`

**PDF**：复用/扩展 `docs/ai/pdf_ai_chaptering_and_ocr.md` 中的文本层 + OCR 缓存策略（Phase 3 先做文本层可用的 PDF；扫描版 OCR 可作为 Phase 3.5+）。

**TXT**：直接读取文件，按规则分段。

### 4.3 分块（chunk）策略

目标：兼顾引用质量（可读的片段）与 embedding 成本。

推荐默认：
- `chunkSizeChars = 800~1200`
- `overlapChars = 120~200`
- 以段落/标题边界优先切割（EPUB 可用 headings/section 信息；Settings 可提供 `includeHeadings`）。

chunk metadata 建议包含：
- `chapter_title` / `href`
- `cfi_start/cfi_end`（若可得）
- `page_start/page_end`（PDF）

### 4.4 写入策略（write）：保证可恢复与一致性

推荐两种方式：

**方式 A：每本书索引写入在一个 transaction 中完成**
- 优点：一致性强
- 缺点：大书 transaction 太大（可能卡顿/内存），失败重试成本高

**方式 B：分阶段写入 + finalize 切换（推荐）**
- `rag_documents` 中引入 `index_generation`（或用 `doc_id` 新建临时 doc 记录）：
  1) 先创建/更新一个临时 doc 记录（`doc_id_temp`）
  2) chunk/embedding 写入到该 doc 下
  3) finalize 时：将旧 doc 标记删除并级联清理，或将新 doc 替换为主 doc

Phase 3 推荐 B（更强健），但实现可从 A 起步，后续再升级。

---

## 5. Hybrid 检索：FTS + Vector（并引入 MMR 去重）

### 5.1 检索输入与范围（Scope）

检索需要明确范围：
- `current_book`：仅当前 book_id
- `library`：全书库（可附带 filters：分组、最近阅读、语言）

读页 UI 建议让用户选择：
- “仅当前书” / “全书库”

### 5.2 候选集生成（Candidate Generation）

**A) FTS 候选（关键词）**

```sql
SELECT
  chunk_id,
  doc_id,
  bm25(rag_chunks_fts) AS score
FROM rag_chunks_fts
WHERE rag_chunks_fts MATCH ?
  AND (? IS NULL OR doc_id = ?)
ORDER BY score
LIMIT ?;
```

- 将用户 query 做轻量规范化（去多余空格、对引号/特殊符号转义）。
- `LIMIT` 建议 50~100。

**B) Vector 候选（语义）**

1) 先计算 query embedding：`q`。
2) doc 粗筛：对 `rag_doc_embeddings` 做线性相似度，取 topD（例如 20）。
3) 只在 topD docs 内对 chunk embeddings 做相似度，取 topV（例如 120）。

> Phase 3 初版可接受线性扫描（库规模可控）；后续可加 ANN。

### 5.3 分数融合（Fusion）

将 FTS 与 vector 的分数归一化到同一尺度后融合：

- `ftsScoreNormalized = normalize( -bm25 )`（bm25 越小越相关）
- `vecScoreNormalized = normalize( cosine(q, v) )`

融合：
- `hybridScore = wVec * vec + wFts * fts`
- 默认 `wVec=0.7, wFts=0.3`（可在 Settings 暴露为高级选项）

### 5.4 去重（Dedup）

候选 chunk 可能重复（同一段落重叠 chunk / 相同文本在不同版本）：

- 以 `text_hash` 去重（优先）
- 或以 `spanKey = bookId + href + cfi_start + cfi_end` 去重
- 冲突时保留 `hybridScore` 更高的

### 5.5 MMR（Maximal Marginal Relevance）多样性选择

目标：选出 K 个上下文片段，既相关又不重复。

MMR 公式（cosine 相似度）：

```
selected = []
while selected.size < K:
  pick d in candidates maximizing:
    lambda * sim(query, d)
    - (1-lambda) * max_{s in selected} sim(d, s)
```

建议：
- `K=6~10`（注入 prompt 的上下文条数）
- `lambda=0.6~0.8`（越大越偏相关，越小越偏多样）

实现细节：
- `sim(query, d)` 用 `vecScoreNormalized`（若候选无向量则用 `hybridScore`）
- `sim(d, s)` 用 chunk 向量余弦

---

## 6. Prompt 注入与引用展示（Reading AI 面板）

### 6.1 注入格式（推荐）

在发送到模型前，将检索到的 snippets 作为 system 或 tool result 注入：

```
[LIBRARY_CONTEXT]
(1) Book: xxx | Chapter: yyy | Location: href#cfi
<snippet>
...
</snippet>
...
[/LIBRARY_CONTEXT]

User question: ...
```

并要求模型：
- 优先使用上下文回答
- 若引用某 snippet，输出 `[[source:1]]` 这样的标记（UI 可解析成可点击引用）

### 6.2 UI 引用展示

- AI 输出中解析 `[[source:n]]` 并在消息下方展示“引用列表”：
  - 书名 / 章节 / 摘要
  - 点击跳转到阅读位置（EPUB：href+cfi；PDF：页码；TXT：offset）

---

## 7. Settings / Reading 页面草图（wireframe）

### 7.1 Settings → AI → Library RAG（新增）

```
AI
 ├─ Provider Center
 ├─ Tools
 ├─ Image Analysis
 ├─ Library RAG  ▶

Library RAG
 ├─ [开关] 启用全书库知识库（RAG）
 ├─ 索引状态
 │    - 已索引：  128 本
 │    - 待处理：   12 本
 │    - 失败：      3 本（点击查看）
 │    - 占用空间：  820 MB
 │
 ├─ 索引策略
 │    - [开关] 导入书籍后自动加入索引队列
 │    - [开关] 仅在 Wi‑Fi 下索引
 │    - [开关] 仅在充电时索引（可选）
 │    - 并发数： [1..4] Slider
 │
 ├─ Embedding 配置
 │    - Provider： (跟随聊天 / 选择某 provider)
 │    - Model：    (下拉)
 │
 ├─ 操作
 │    - [按钮] 立即开始（enqueue all）
 │    - [按钮] 暂停队列
 │    - [按钮] 取消全部任务
 │    - [危险按钮] 清空索引库（删除 ai_index.db）
 │
 └─ 失败任务（列表）
      - Book A：network error（重试）
      - Book B：extract failed（查看日志）
```

### 7.2 Reading Page → AI 面板（新增 scope + 索引提示）

```
AI Chat Header
 ├─ Scope: [当前书 ▼]  (当前书 / 全书库)
 ├─ Index status chip: "书库索引未完成 12"（点击进入 Library RAG）

Message list
 ├─ assistant message
 │    ... [[source:1]] [[source:3]]
 │    引用：
 │      1) 《Book A》 Chapter 2  (打开)
 │      3) 《Book C》 ...

Input
 ├─ prompt chips
 ├─ send
```

---

## 8. 可拆分的实现步骤（按 commit / PR 粒度）

> 目标：每个 PR 都可 review、可回滚、可独立验收。

### PR1（docs + skeleton）：Phase 3 设计落地骨架

- 新增文档：`docs/ai/rag_phase3_library_rag_zh.md`
- 建立目录骨架（空实现）：`lib/service/ai/rag/*`
- 新增 `AiIndexDbHelper`（可打开/创建空库）

验收：app 编译通过，打开 DB 不崩。

### PR2（ai_index.db schema + DAO）：数据模型实现

- `ai_index.db` v1：`rag_documents / rag_chunks / rag_chunks_fts / rag_embeddings / rag_index_jobs`
- `RagDao`：基础 CRUD（upsert doc、insert chunks、insert embeddings、enqueue job）

验收：单元测试或 debug page 能创建 doc + chunks + fts 搜索。

### PR3（单书索引流水线 RagIndexer）：extract/chunk/write（无 embedding 或 mock）

- `HeadlessEpubContentExtractor`：参考 `getBookMetadata()` 的 headless webview
- `Chunker`：可测试（输入文本 → chunks）
- 写入 `rag_chunks` + `rag_chunks_fts`

验收：对 1 本 epub 运行索引，能用关键词检索到 chunk。

### PR4（Embedding 集成）：向量生成 + 存储 + doc embedding

- 增加 embedding 请求路径（可复用现有 provider 配置体系）：
  - 建议新增 `AiRequestScope.ragEmbedding`（runner 隔离，避免 cancel chat）
- `rag_embeddings` 写入
- `rag_doc_embeddings` 聚合生成

验收：对 1 本书生成 embeddings；查询 embedding 能返回相似 chunk。

### PR5（队列系统 RagQueueService）：并发/lease/取消/重试

- worker loop（Timer/async）
- lease + ttl + 续租
- cancel_requested 检查
- 失败重试策略（attempts + backoff）

验收：批量 enqueue 20 本书；能暂停/恢复/取消；崩溃重启后能恢复未完成任务。

### PR6（Hybrid Retriever + MMR）：FTS+vector 融合与去重

- `RagRetriever.search(query, scope)` 返回 `List<RagSnippet>`
- MMR + dedup（纯 Dart 可单测）

验收：同一 query 结果更少重复、引用更分散。

### PR7（UI 集成）：Settings + Reading

- Settings 新页：Library RAG
- 读页 AI 面板 scope 选择 + 引用展示 + 索引状态提示
- enqueue 入口：导入后自动入队（受设置开关控制）

验收：用户可感知索引进度；对话能引用全书库来源并可跳转。

### PR8（可观测性 & 维护工具，可选）

- `rag_index_events` 日志页
- vacuum/空间统计
- 清空索引库/重建确认

---

## 9. 风险与应对

- **FTS5 平台差异**：iOS/macOS/Windows 的 SQLite 编译选项不一致。
  - 应对：启动时检测 FTS5 是否可用；不可用则仅启用 vector 或降级。

- **索引耗时/耗电**：
  - 应对：默认并发=1；提供“仅 Wi‑Fi / 仅充电”；大书可 stopAtCharacters 上限。

- **embedding 成本**（API 费用 + 速率限制）：
  - 应对：chunk 策略可调；失败退避；允许只索引“最近/收藏/指定分组”。

- **引用定位不可靠**（EPUB CFI 可能缺失）：
  - 应对：至少保存 chapter title + href；无法精确跳转时跳到章节开头。

---

## 10. 附：关键 Settings（Prefs）建议清单

> 具体 key 名可在实现时统一加 `libraryRag*V1` 前缀。

- `libraryRagEnabledV1: bool`
- `libraryRagAutoIndexOnImportV1: bool`
- `libraryRagWifiOnlyV1: bool`
- `libraryRagChargingOnlyV1: bool`（可选）
- `libraryRagIndexConcurrencyV1: int (1..4)`
- `libraryRagEmbedProviderIdV1: String`（空=follow chat）
- `libraryRagEmbedModelV1: String`（空=follow provider config）
- `libraryRagChunkSizeCharsV1: int`
- `libraryRagChunkOverlapCharsV1: int`
- `libraryRagHybridWeightVecV1: double`（高级）
- `libraryRagMmrLambdaV1: double`（高级）

---

## 11. 结论

Phase 3 的核心是：把“全书库 RAG”拆成 **可维护的索引队列系统** + **可组合的检索器（FTS+vector+MMR）**。

本文给出的 `ai_index.db` 扩展、队列状态机、并发/取消策略、Hybrid+MMR 与 UI 草图，均可直接拆成小 PR 在现有 Riverpod + services 架构中落地。
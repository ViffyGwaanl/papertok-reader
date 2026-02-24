# Paper Reader — RAG（强上下文）+ Markdown 记忆系统（Phase 1–5 全量计划）

> 目标：在 Paper Reader（papertok-reader）里实现类似 OpenClaw 的“上下文很强”的 AI 阅读问答体验。
> 核心方法：**检索少量证据 → 压缩证据 → 强制引用绑定 → 点击引用回到书内原文位置（CFI）**。
>
> 本文是工程计划总览（PRD + 技术方案 + 里程碑）。对应任务拆解见 `rag_memory_tasks_zh.md`。

---

## 1. 背景与目标

### 1.1 背景
- 单纯把整本书塞进 LLM prompt 既昂贵又不稳定，且难以引用追溯。
- 强上下文来自：RAG 检索 + 证据压缩 + 引用闭环，而不是更长 prompt。

### 1.2 产品目标（DoD）
1) 支持两种问答范围：
- 单本书（book scope）
- 全书库（library scope）

2) 支持短书“全文上下文模式”：
- 对于内容较短的书，可选择直接使用全书全文作为上下文。

3) 引用必须可追溯：
- 每条关键结论都能点回书内原文（goToCfi + 高亮）。

4) Embedding API 复用 Provider Center：
- Embedding 模型可单独选择（类似翻译/图片解析 override）。
- 默认模型：`text-embedding-3-large`。

5) 记忆系统（Markdown）：
- 本地文件 `memory/MEMORY.md`（长期） + `memory/YYYY-MM-DD.md`（每日）。
- 新增“记忆”Tab 管理与搜索。

6) 索引存储：
- Embedding/FTS 索引独立 DB：`ai_index.db`（本地、可重建、默认不 WebDAV 同步）。
- 备份导出：提供“可选包含 ai_index.db”与“可选包含 memory/”。

---

## 2. 约束与默认参数

- 仅 EPUB。
- 不跑本地模型（Embedding/Rerank/LLM 全云端）。

默认参数（可在设置中调优）：
- 检索 topK：10
- 证据喂给 LLM：10 条（经过压缩）
- 短书全文上下文阈值：默认 20,000 chars（可调）
- ai_index chunk 目标大小：约 250–450 tokens（字符近似）

---

## 3. 系统架构（分三条链路）

### 3.1 全文上下文链路（短书）
- 书籍字数/字符数统计。
- 若小于阈值：直接喂全文（仍输出章节/段落引用）。

### 3.2 RAG 链路（强上下文核心）
- 本地索引 DB `ai_index.db`：chunks + FTS + embeddings。
- 检索：Hybrid（FTS/BM25 + 向量 cos） + MMR 去重。
- 引用：chunk → (href + cfi 或 anchor+resolve_cfi 兜底)。

### 3.3 Markdown 记忆链路
- `memory/` 目录存 md 文件。
- 记忆 Tab：浏览/编辑/搜索/插入到对话。
- AI tools：memory_read/search/append（写入走 Tool Safety 审批）。

---

## 4. 数据存储设计

### 4.1 ai_index.db（独立 SQLite）
- `books(bookId, title, totalChars, totalWords, indexStatus, indexVersion, updatedAt)`
- `chapters(bookId, href, chapterTitle, chapterOrder, charCount)`
- `chunks(chunkId, bookId, href, chapterTitle, orderInChapter, text, anchor, cfiStart, cfiEnd)`
- `emb_chunks(chunkId, modelKey, dim, vectorBlob, createdAt)`
- `emb_chapters(bookId, href, modelKey, dim, vectorBlob)`
- `fts_chunks`（FTS5）：(chunkId, bookId, href, text)

> vectorBlob 推荐 float16 存储，降低体积。

### 4.2 memory/（Markdown）
- `memory/MEMORY.md`
- `memory/YYYY-MM-DD.md`

---

## 5. UX 设计

### 5.1 书籍设置页（手动索引）
- AI 语义索引：状态、进度、开始/暂停/继续/重建/清除。
- 显示：当前书 totalChars/words。
- 可选：短书全文上下文模式开关（或放 AI 对话设置）。

### 5.2 书库页（批量索引）
- 多选书籍 → 批量加入索引队列。
- 队列进度：当前正在索引哪本、总进度、失败原因。

### 5.3 AI 对话设置
- 问答范围：当前书 / 全书库。
- 上下文模式：RAG / 短书全文（自动）/ 强制全文（不推荐默认）。

### 5.4 引用跳转
- Markdown 内链 scheme：`anx://open?bookId=...&cfi=...`。
- `StyledMarkdown` 拦截内链并在 app 内导航，外链才 external。

### 5.5 记忆 Tab
- 列表：MEMORY + daily。
- 编辑、搜索、插入当前对话。

---

## 6. 检索与压缩策略

### 6.1 分层检索（章 → chunk）
- 先用 chapter embedding 找 topChapters（10）。
- 仅在 topChapters 的 chunks 做 cos，形成候选池。
- 合并 FTS 候选池。
- MMR 去重后输出 top10。

### 6.2 证据压缩
- 每条 chunk 输出 2–4 句 quote + locator。
- 总证据包预算（例如 12k–20k chars），超了减少条数/quote。

---

## 7. 里程碑（Phase 1–5）

### Phase 1：短书全文 + 字数统计 + 引用跳转基础
- 字数统计与显示
- AI 设置：短书全文阈值与模式
- Markdown 内链跳转到 CFI
- resolve_cfi 兜底工具

### Phase 2：单书索引（ai_index.db）+ semantic_search(book)
- ai_index.db schema
- chunking + embeddings 入库
- semantic_search(scope=book)

### Phase 3：全书库 + Hybrid + 批量索引
- 分层检索 + FTS + MMR
- 批量索引队列
- semantic_search(scope=library)

### Phase 4：Markdown 记忆系统 + 记忆 Tab
- memory/ 文件系统
- 记忆 Tab + memory tools

### Phase 5：备份导出可选包含 ai_index.db 与 memory/
- export/import 扩展（rollback-safe）

---

## 8. 测试策略
- 单元测试：chunking、检索融合/排序、MMR、内链解析
- Widget 测试：引用点击跳转
- 运行时日志：索引/检索耗时与失败原因

---

## 9. 风险与对策
- 索引体积大：float16 + 分层检索 + 可清理
- 引用漂移：Phase1 resolve_cfi 兜底；Phase2 起逐步写入 cfi
- 成本控制：显示估算、仅 Wi‑Fi、可暂停
- 隐私提示：明确告知 embedding 会上传文本片段

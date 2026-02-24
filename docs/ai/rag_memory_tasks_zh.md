# Paper Reader — RAG + Markdown 记忆系统（Phase 1–5 任务拆解）

> 本清单按可提交的工程任务拆解（建议每个小任务独立 commit）。
> 总览见 `rag_memory_plan_zh.md`。

---

## Phase 1：短书全文 + 字数统计 + 引用跳转基础

### P1-1 字数统计（Book stats）
- [ ] 建立 `BookStatsService`：从 foliate-js 逐章拉纯文本并累计 `totalChars/totalWords`（可缓存）
- [ ] 在书籍设置页展示：章节数、totalChars/words、统计时间
- [ ] 若未统计，提供按钮“计算字数”

### P1-2 短书全文上下文模式
- [ ] Prefs：`shortBookFulltextEnabledV1`、`shortBookFulltextMaxCharsV1`（syncable，不含密钥）
- [ ] AI 对话设置 UI：RAG/短书全文（自动）/强制全文
- [ ] 生成 prompt 时根据阈值决定：全文上下文 or RAG

### P1-3 引用跳转内链
- [ ] 约定内部链接：`anx://open?bookId=...&cfi=...`
- [ ] 修改 `StyledMarkdown`：onLinkTap 拦截 anx:// 内链并跳转阅读页 goToCfi
- [ ] 跳转后高亮/定位（复用已有高亮能力或临时 toast）

### P1-4 resolve_cfi 工具（兜底）
- [ ] 新工具：`resolve_cfi`：输入 bookId + href + anchorText → 调用 `book_content_search` → 返回 cfi
- [ ] 在引用生成里：若 chunk 没有 cfi，调用 resolve_cfi 补全

---

## Phase 2：单书索引（ai_index.db）+ semantic_search(book)

### P2-1 ai_index.db 基础设施
- [ ] 新 DB 文件 `ai_index.db`（独立于 app db）
- [ ] DAO：创建表 books/chapters/chunks/emb_chunks/emb_chapters/fts_chunks
- [ ] 迁移与 indexVersion

### P2-2 Chunking
- [ ] 从 foliate-js 按章节 href 获取纯文本
- [ ] chunking（段落/标题优先）+ overlap
- [ ] chunks 入库（text+anchor+href+chapterTitle+order）

### P2-3 Embeddings client（复用 Provider Center + override 模型）
- [ ] Prefs：`embeddingSettingsV1.providerId/model`（默认 text-embedding-3-large）
- [ ] Provider capabilities: supportsEmbeddings
- [ ] Embedding API 适配（OpenAI-compatible / OpenAI）
- [ ] 批量请求 + 失败重试 + 速率限制

### P2-4 索引 UI（单书）
- [ ] 书籍设置页：开始索引/暂停/继续/清除/重建
- [ ] 索引进度 HUD

### P2-5 semantic_search(scope=book)
- [ ] 新工具：`semantic_search`（book scope）
- [ ] 取 topK chunk（向量 + 可选 FTS）
- [ ] 输出 results[]（带 locator：href + cfi 或 anchor）
- [ ] 证据压缩（quote 2–4 句）

---

## Phase 3：全书库 + Hybrid + 批量索引

### P3-1 分层检索（chapter → chunk）
- [ ] emb_chapters：每章向量
- [ ] 检索：先 top chapters，再章内 chunks

### P3-2 Hybrid（FTS + Vector）+ MMR 去重
- [ ] FTS5 BM25 候选池
- [ ] 融合打分（归一化）
- [ ] MMR 去重与覆盖面控制

### P3-3 批量索引队列
- [ ] 书库多选 → 加入队列
- [ ] QueueCoordinator：并发=1、可暂停/继续、失败原因
- [ ] 队列状态页或弹窗

### P3-4 semantic_search(scope=library)
- [ ] 支持 library scope（跨 bookId）
- [ ] 输出结果包含 bookId/href/chapterTitle

---

## Phase 4：Markdown 记忆系统 + 记忆 Tab

### P4-1 文件系统与服务
- [ ] App documents 下创建 `memory/`
- [ ] 若缺失创建 `MEMORY.md`
- [ ] daily 文件读写 API

### P4-2 记忆 Tab
- [ ] 新 tab：记忆
- [ ] 列表：MEMORY + daily
- [ ] 编辑器：预览/编辑/保存
- [ ] 搜索：全文/FTS（可先简单）

### P4-3 memory tools（可选但推荐）
- [ ] `memory_read`、`memory_search`（read-only）
- [ ] `memory_append`/`memory_replace`（write，走 Tool Safety 审批）

---

## Phase 5：备份导出可选包含 ai_index.db 与 memory/

### P5-1 备份 UI
- [ ] 备份页增加勾选：包含 ai_index.db（默认 OFF）
- [ ] 备份页增加勾选：包含 memory/（默认 ON 或 OFF，建议 ON）

### P5-2 Export/Import 实现
- [ ] export：可选打包 ai_index.db 与 memory/
- [ ] import：rollback-safe（.bak + 全量替换）
- [ ] 文档更新

---

## 回归与验收
- [ ] flutter test -j 1 全绿
- [ ] iOS 真机：引用点击跳转、索引建立、全库检索、批量索引、记忆 Tab
- [ ] 成本/隐私提示完整

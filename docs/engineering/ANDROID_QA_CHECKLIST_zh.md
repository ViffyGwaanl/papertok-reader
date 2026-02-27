# Android QA Checklist (Paper Reader)

本清单用于 **Paper Reader（papertok-reader）Android 真机回归**。

目标：确保核心链路（AI/翻译/PaperTok/MCP/RAG+Memory/备份/深链）在 Android 上可用、稳定、可解释。

---

## 0. 基线

- 构建来源：`product/main`
- 建议先跑：`flutter test -j 1`（已在 CI/本地验证通过为佳）

---

## 1. 安装与启动

1) 冷启动（首次安装）
- 预期：无闪退；引导/权限提示正常。

2) 热启动（后台切回）
- 预期：页面状态合理恢复；AI 生成/索引任务不应异常卡死。

---

## 2. Deep Links（paperreader://）

### 2.1 Reader 导航 deep link
在 Android 任意可点击链接的地方（例如备忘录/浏览器地址栏/聊天软件）粘贴并点击：

- `paperreader://reader/open?bookId=<id>&href=<href>`
- `paperreader://reader/open?bookId=<id>&cfi=<epubcfi(...)>`

预期：拉起 App → 打开对应书 → best-effort 定位到 href/cfi。

### 2.2 Shortcuts deep link（容错）
Android 不一定会使用 iOS Shortcuts，但协议路由应保持隔离：

- `paperreader://shortcuts/result?runId=test&data=ok`

预期：不应触发 reader open；不会导致 crash。

---

## 3. Phase 3：AI 索引（书库）+ semantic_search_library

入口：Settings（设置）顶层 → **AI 索引（书库）**

1) 书籍筛选真值联动
- 切换：未索引 / 过期 / 已索引
- 预期：列表由 `ai_index.db` 真值驱动（md5/provider/model/index_version）。

2) 手动多选入队
- 进入选择模式 → 勾选多本 → 加入队列
- 预期：队列开始运行；UI 有 active job 进度与 queued badge。

3) 队列控制
- Pause → Resume
- Cancel（running/queued）
- Clear finished
- 失败自动重试一次：第一次失败应回到 queued 并标记 retryCount=1；第二次失败应进入 failed 并显示错误摘要。

4) `semantic_search_library` 工具
入口：Home → AI（Agent）
- 让模型调用：`semantic_search_library`（query/maxResults/onlyIndexed）
- 预期：返回 evidence[]，包含 `jumpLink` 且 scheme 为 `paperreader://reader/open?...`

5) 点 evidence 的 jumpLink
- 同书：当前阅读器内跳转。
- 跨书：打开对应书并定位（href/cfi）。

---

## 4. Memory（本地记忆 / 对齐 OpenClaw A–D）

入口：Settings → Memory

1) 基础文件与编辑
- 打开/创建 `MEMORY.md`，写入一段内容并保存。
- 创建/编辑一个 daily（任意日期），写入另一段包含相同关键词的内容。

2) Memory 搜索（FTS/BM25 + fallback）
- 在 Memory 页搜索关键词：预期命中 `MEMORY.md` 与 daily，返回 snippet/文件名/行号。
- 删除/清空派生索引后再搜索：预期不 crash；本次可走 fallback；随后自动后台重建索引。

3) 语义检索 Auto-on（M2）
- 配置 embeddings provider/key 后：预期 Effective=ON；能召回相关但非字面匹配内容。
- 移除 key 后：预期 Effective=OFF；仍能走文本检索。

4) Hybrid tuning（A）
- 调节 vector/text 权重与 candidateMultiplier：预期无 crash；排序变化可解释。

5) 可选增强（B，默认 off）
- 打开 MMR：结果应更分散。
- 打开 temporal decay：新 daily 应优先于旧 daily。

6) Embedding cache（D）
- 开启缓存并把上限设小（如 5k）：多次搜索后不应出现明显卡顿/异常膨胀。
- 关闭缓存：仍能搜索（但 embeddings 调用次数会增加）。

---

## 5. MCP Servers（外部工具）

入口：Settings → MCP Servers

1) 添加 server（Auto）→ Test Connection
- 预期：initialize + tools/list 成功（或错误信息可读）。

2) 工具缓存
- Refresh all / Clear cache
- 预期：工具列表可见；schema sheet 可打开。

3) Agent 调用 MCP tool
- 预期：输出被裁剪（如超出上限）；超时触发取消；写操作需要审批。

4) WebDAV 同步验证（可选）
- 预期：另一台设备同步到 server meta，但 secrets 不同步。

参考：`docs/ai/mcp_servers_zh.md`

---

## 6. 备份/恢复（Files）

入口：Settings → Sync → Export/Import

1) Export
- 验证勾选：包含 Memory（默认 ON）、包含 AI 索引（默认 OFF）
- 导出 zip 解压检查：
  - 未勾选索引：不应出现 `databases/ai_index.db*`
  - 取消 Memory：不应出现 `memory/`

2) Import
- 验证方向性覆盖选项（恢复 Memory / 恢复 AI 索引）
- 未勾选恢复 AI 索引时：本地 `ai_index.db` 不应被清除

---

## 7. AI 对话 / Provider Center

入口：Settings → Provider Center

1) Provider 切换
- 预期：禁用 provider 不应出现在 chat selector。

2) OpenAI Responses
- 默认路径：工具调用链路不应再出现 reasoning item 400（优先使用 `previous_response_id` continuation）。
- 兼容开关验证（Provider Detail）：
  - 关闭 `responses_use_previous_response_id`：请求不应包含 `previous_response_id`（用于兼容第三方网关 400）。
  - 关闭 `responses_request_reasoning_summary`：请求不应包含 `reasoning` block（用于兼容第三方网关）。

---

## 8. EPUB Inline 全文翻译（阅读页）

1) 开启翻译并翻页
- 预期：不取消上一页翻译；HUD 进度可见；失败段可重试。

---

## 9. PaperTok（如果启用）

1) Papers feed 加载、导入 PDF/EPUB
- 预期：导入后可打开阅读；无明显卡死。

---

## 10. 记录与回归输出

建议每次回归记录：
- 测试设备/Android 版本
- commit hash（`git rev-parse --short HEAD`）
- 失败项截图/日志关键行

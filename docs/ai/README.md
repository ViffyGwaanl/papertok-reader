# AI Panel UX / Config / Sync — Design & Implementation Notes

> Maintainer note: 本目录记录 **Paper Reader（papertok-reader）** 中 AI/翻译相关的 UX、配置、同步与实现细节。
> 
> 上游贡献（Anx Reader）目前不是产品交付的必需项；如未来需要上游化，会单独整理成“干净的 contrib track”（不混入 PaperTok/产品专属 UX）。

## Scope

### Implemented (product repo, `main`)

#### Reading-page AI panel UX (iPad/iPhone)

- iPad dock split panel: **touch-friendly resize** + **persist** width/height
- iPad: panel mode setting (dock vs bottom sheet)
- iPad: dock side switch (left/right) + TOC drawer gesture mitigation
- iPhone/iPad bottom-sheet mode:
  - `DraggableScrollableSheet` with snap points
  - can **minimize** to a small bar (keep reading)
  - open defaults to expanded on reading page
- Streaming UX:
  - **minimize instead of dismiss** (supports “keep generating while reading”)
  - open does **not** auto-scroll to bottom
  - streaming auto-scroll only when user is pinned near bottom

#### Chat UX (Cherry-inspired, Flutter-native)

- Provider Center (top-level settings entry)
  - built-in providers + custom providers
  - in-chat provider/model switching
- “Thinking level” (档位) selector (Cherry-style lightbulb UI)
- Gemini thinking support: `includeThoughts` toggle (default ON)
- Thinking/Answer/Tools sections: collapsible display
- Editable chat history + regenerate from any user turn
- Per-turn assistant variants (left/right switch)
- Conversation tree v2 (`conversationV2`) with rollback via per-message variant switcher

#### Multimodal / Image Analysis (new)

- Multimodal chat attachments (v1):
  - images + plain text files
  - max **4** images per send
  - attachments are **not synced** and **not included in backup**
- EPUB image analysis:
  - tap an image in EPUB → open viewer → analyze with a multimodal model
  - dedicated provider/model settings (Settings → AI → Image Analysis)
  - independent request scope so it does **not cancel** ongoing chat streaming
- Compatibility hardening:
  - normalize image MIME types for OpenAI-compatible providers
  - rasterize SVG images to bitmap before sending (many backends do not accept SVG)
  - Volcengine Ark (`volces.com/api/v3`) image_url base64 format compatibility

#### Config / Sync / Backup

- Configurable input quick prompts chips
- User prompt editor maxLength raised to **20,000**
- WebDAV sync of AI settings snapshot (**excluding api_key**) with timestamp newer-wins
- Files/iCloud manual backup/restore:
  - directional overwrite options
  - optional **encrypted API key** inclusion (password-based)
  - rollback-safe import

#### OpenAI-compatible “thinking content” compatibility

- If an OpenAI-compatible backend returns `reasoning_content` (or `reasoning`) in responses/stream deltas, the app maps it to the `<think>...</think>` channel so it shows inside the Thinking section.

#### OpenAI Responses — tool calling stability notes

- Tool-call continuation (recommended): use `previous_response_id` (server-provided `response.id`) + `input: [function_call_output...]`.
  - Rationale: manually replaying `type: "reasoning"` items is brittle and can trigger 400 errors like:
    - `reasoning was provided without its required following item`
- 3rd-party “Responses-compatible” gateways may reject `previous_response_id` with 400 (e.g. `Unsupported parameter: previous_response_id`).
  - Provider Center provides explicit compatibility toggles on the OpenAI Responses provider:
    - `responses_use_previous_response_id`: when OFF, requests omit `previous_response_id`.
    - `responses_request_reasoning_summary`: when OFF, requests omit the `reasoning` block.
  - In compat mode (`responses_use_previous_response_id = OFF`), the client also avoids capturing/replaying `reasoning` transcript items to reduce gateway validation failures.
- The implementation lives in:
  - `lib/service/ai/openai_responses_chat_model.dart`

#### Deep links (Paper Reader)

- Reader navigation deep links use the **Paper Reader** URL scheme (system-level):
  - `paperreader://reader/open?bookId=<id>&cfi=<epubcfi(...)>`
  - `paperreader://reader/open?bookId=<id>&href=<chapterHrefOrAnchor>`
- Shortcuts callback deep links keep using:
  - `paperreader://shortcuts/...`
- Note: legacy `anx://...` jump links are **removed** in the product repo. New links must use `paperreader://reader/open?...`.

---

## Implemented (main)

#### Phase 3 — Library RAG / **AI 索引（书库）**

已合入 `main`（产品仓库 `product/main` 同步）。核心能力包含：

- `ai_index.db` v2+ 迁移（jobs queue + index metadata）
- Headless reader bridge：可为任意 `bookId` 抽取 TOC/章节文本用于索引
- Library indexing queue：pause/resume/cancel/clear finished、失败自动重试一次、重启归一化（running→queued）
- Settings 顶层入口：**AI 索引（书库）**（手动多选入队 + 队列控制）
- 全库检索工具：`semantic_search_library`（Hybrid：FTS/BM25 + vector + 可选 MMR/去重）
- 跳转链接：统一 `paperreader://reader/open?...`（不再生成 `anx://...`）

剩余工作以“真机 QA checklist + 发布回归”为主（不再存在合入阻塞）。

Docs:
- [RAG + Memory（Phase 1–5）总体计划与状态（中文）](./rag_memory_plan_zh.md)
- [RAG + Memory（Phase 1–5）任务清单（中文）](./rag_memory_tasks_zh.md)
- [Phase 3：全书库 RAG + 批量索引队列（中文）](./rag_phase3_library_rag_zh.md)
- [MCP Servers（外部工具）说明（中文）](./mcp_servers_zh.md)

---

## Other modules (product)

- [PaperTok (papers feed) — UX + import behavior](../papertok/README.md)

## Architecture Notes (important)

### Provider-managed streaming (root-cause fix)

**Problem:** when streaming is owned by a Widget (`StreamSubscription` in the UI), any UI lifecycle change (bottom sheet minimize/rebuild, scrollController swap, route changes) can interrupt generation.

**Fix:** streaming is moved into `aiChatProvider` (keepAlive) and the UI becomes a pure renderer:

- `aiChatProvider.notifier.startStreaming(...)`
- `aiChatProvider.notifier.cancelStreaming()`
- `aiChatStreamingProvider` exposes streaming state for UI (send/stop button, disabling edits, etc.)

This is the “root-cause” solution for “minimize/close should not interrupt generation”.

### Tooling / agent mode dependency on Riverpod `Ref`

To allow provider-owned agent streaming (reading tools), tool code paths now accept **Riverpod core `Ref`** (not Flutter-only `WidgetRef`).

---

## Branch / Release notes

The product repository uses `main` as the integration branch for iPhone/iPad testing and TestFlight.

All AI/translation/multimodal/image-analysis changes are integrated into `main`.

---

## Documents

- [AI 改造：已完成 & 路线图（中文）](./ai_status_roadmap_zh.md)
- [RAG + Memory（Phase 1–5）总体计划与状态（中文）](./rag_memory_plan_zh.md)
- [RAG + Memory（Phase 1–5）任务清单（中文）](./rag_memory_tasks_zh.md)
- [Phase 3：全书库 RAG + 批量索引队列（中文）](./rag_phase3_library_rag_zh.md)
- [P1：OpenAI-compatible Thinking（仅展示供应商数据，无兜底）（中文）](./ai_thinking_openai_provider_only_zh.md)
- [AI panel UX tech design](./ai_panel_ux_tech_design.md)
- [AI provider config UX (Provider Center)](./ai_provider_config_ux.md)
- [AI settings sync (WebDAV) tech design](./ai_settings_sync_webdav.md)
- [Backup/restore (Files/iCloud) tech design](./backup_restore_icloud.md)
- [iOS EventKit 系统工具（Reminders/Calendar）说明（中文）](./eventkit_tools_zh.md)
- [iOS Shortcuts 工具：回到 App + 回传结果（中文）](./shortcuts_callback_zh.md)
- [PDF AI chaptering & OCR (MinerU) design](./pdf_ai_chaptering_and_ocr.md)
- [AI translation design notes](./ai_translation_design.md)
- [iOS TestFlight build notes](./ios_testflight_build.md)
- [Test plan](./test_plan.md)
- [Implementation plan](./implementation_plan.md)
- [Release/Migration notes](./release_notes_migration_ai_sync_backup.md)

---

## Developer Notes

### Codegen requirements

This repo ignores generated files (e.g. `*.g.dart`, `*.freezed.dart`, `lib/gen/`). After pulling branches/PRs, regenerate:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

---

## Memory（长期记忆）

- Memory 的设计与实现对齐 OpenClaw：Markdown 为 source-of-truth，索引为派生缓存，可重建。
- 现已支持：本地 FTS/BM25 snippet 检索 + 语义检索（Auto-on）+ Hybrid tuning + 可选 MMR/Temporal decay + 后台索引刷新 + embedding cache 控制。
- 详见：`docs/ai/memory_search_openclaw_alignment_zh.md`


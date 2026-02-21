# Implementation Plan (AI stack, product repo)

This file tracks what is implemented in the product repo and what remains, written as an engineering checklist.

> Primary integration branch: `main` (`ViffyGwaanl/papertok-reader`)

---

## Completed (high level)

### UX

- [x] iPad dock AI panel: resize + persist width/height
- [x] iPad: dock side switch (left/right) + gesture conflict mitigation with TOC drawer
- [x] iPad: panel mode setting (dock vs bottom sheet)
- [x] Bottom sheet: resizable/minimizable with snap points; reading page opens expanded
- [x] AI chat font scale
- [x] Configurable input quick prompts
- [x] Prompt editor maxLength → 20,000

### Config / Sync / Backup

- [x] WebDAV sync of AI settings snapshot (`paper_reader/config/ai_settings.json` (legacy: `anx/config/ai_settings.json`))
  - whole-file timestamp newer-wins
  - **exclude api_key**
- [x] Manual backup/restore via Files/iCloud
  - v4 zip + manifest
  - optional encrypted API key inclusion (password-based)
  - rollback-safe import

### Provider Center + Cherry-inspired chat UX (Flutter-native)

- [x] Provider Center top-level entry + CRUD
- [x] In-chat provider + model switch
- [x] Thinking level selector + Gemini includeThoughts support
- [x] Thinking/Answer/Tools collapsible sections
- [x] Editable history + regenerate from any user turn
- [x] Per-turn variants switcher
- [x] Conversation tree v2 persistence (`conversationV2`) + rollback

### OpenAI-compatible reasoning display

- [x] Map `reasoning_content` / `reasoning` to Thinking section when provided by backend.

### Multimodal / Image Analysis

- [x] Chat multimodal attachments (images + plain text files; max 4 images)
- [x] EPUB image analysis (tap image → analyze with multimodal model)
- [x] SVG rasterize + MIME normalization + Ark base64 image_url compatibility

---

## Root-cause fix: provider-managed streaming (DONE)

### Problem statement

- UI-owned `StreamSubscription` is fragile: minimizing a sheet, swapping scroll controllers, or route rebuilds can interrupt streaming.

### Implementation

- [x] Move chat streaming ownership into `aiChatProvider` (keepAlive)
  - `startStreaming(...)` runs generation and updates provider `state` per chunk
  - `cancelStreaming()` cancels generation
  - `aiChatStreamingProvider` exposes streaming status for UI
- [x] Update `AiChatStream` to be “render-only”
  - no widget-owned streaming controller/subscription
  - send/regen/edit call provider methods
- [x] Refactor agent/tool code paths to accept Riverpod core `Ref` (provider-friendly)

### Acceptance criteria

- [x] Reading page: minimize bottom sheet → generation continues (no interruption)
- [x] Close the sheet (not exit reading page) → generation continues
- [x] Stop button cancels immediately
- [x] No crashes/assertions during rapid minimize/expand

---

## Next work (planned)

### A) iPhone TabBar UX 收敛（产品向）

- [ ] 调整浮动 TabBar 参数（高度/底部偏移/模糊/背景），确保不遮挡底部交互区。
- [ ] 统一 iOS native bar 与非 iOS fallback 的视觉规范（如需要）。

### B) 多模态与图片解析 QA

- [ ] 增加 1 个 widget/unit test：覆盖 image_url 编码策略（data URL vs raw base64）。
- [ ] 真机验证 SVG 解析、Ark/自建网关兼容性与错误提示。

### C) 发布链路与文档

- [ ] 完善 iOS 构建常见错误的排查（例如 Xcode Components 缺失导致 `iOS XX.X is not installed`）。
- [ ] 维护 docs 与当前实现一致（尤其是 Settings 入口与同步/备份策略）。

---

## Engineering constraints (important)

- License: Cherry Studio App is AGPL-3.0, Anx Reader is MIT → UX inspiration only, no code reuse.
- Generated files are gitignored → always run build_runner + l10n generation when switching branches.

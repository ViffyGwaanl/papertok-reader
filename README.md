**English** | [简体中文](README_zh.md)

<br>

# Paper Reader (papertok-reader)

**Paper Reader** is an iOS/iPadOS-first *product distribution* built on top of **[Anx Reader](https://github.com/Anxcye/anx-reader)** (MIT).

This repo focuses on **PaperTok integration + AI/translation UX improvements + product defaults + iOS QA/release workflow**.

## Platform status (important)

- ✅ **Tested in this repo:** iOS (iPhone) + iPadOS (iPad)
- ⚠️ **Not yet validated in this repo:** Android / Desktop (macOS/Windows/Linux)

If you need stable multi-platform usage right now, use upstream **Anx Reader**.

## Feature highlights

### PaperTok (Papers tab)
- Academic paper feed (PaperTok) integrated as a first-class tab.
- Product navigation defaults tuned for “paper reading” workflow.

### AI chat (Provider Center)
- Provider Center UX (Flutter-native; Cherry-inspired, no code reuse).
- Built-in providers + custom providers (OpenAI-compatible / Anthropic / Gemini / OpenAI Responses).
- In-chat provider + model switching.
- “Thinking level” (档位) selection and collapsible thinking content display.
- Editable chat history + regenerate from any user turn.
- Conversation tree v2 with variants (rollback/branching without losing subsequent turns).
- Multimodal attachments (currently: **images + plain text**; max **4** images per send).
- EPUB image analysis: tap image → analyze with a multimodal model.

### In-reader translation (EPUB)
- Inline full-text translation (immersive: **translation below original**).
- Progress HUD (top-right), closable + re-openable.
- Per-book cache + clear, retry for failed segments.
- Translation-dedicated provider/model override (separate from chat).

### Sync & backup (safety-first)
- WebDAV sync for **non-secret** AI settings (provider/model/prompts/UI prefs), with whole-file “newer-wins” strategy (Phase 1).
- Manual backup/restore via Files/iCloud Drive, with directional overwrite.
- **Plain backups never include API keys** (including `api_key` and `api_keys`).
- API keys can be included **only via encrypted backup** (password-based).

## Documentation (start here)

- Docs index: **[`docs/README.md`](./docs/README.md)**

### Engineering / iOS (recommended to read)
- iOS install / signing / TestFlight walkthrough: **[`docs/engineering/IOS_DEPLOY_zh.md`](./docs/engineering/IOS_DEPLOY_zh.md)**
- Identifiers source of truth (Bundle ID / App Group / Android applicationId): **[`docs/engineering/IDENTIFIERS_zh.md`](./docs/engineering/IDENTIFIERS_zh.md)**
- iOS TestFlight release checklist: **[`docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md`](./docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md)**
- Platform test status: **[`docs/engineering/PLATFORM_TEST_STATUS_zh.md`](./docs/engineering/PLATFORM_TEST_STATUS_zh.md)**
- Troubleshooting: **[`docs/troubleshooting.md`](./docs/troubleshooting.md)**

### AI / Translate
- AI/Translate overview: **[`docs/ai/README.md`](./docs/ai/README.md)**
- WebDAV AI settings sync design: **[`docs/ai/ai_settings_sync_webdav.md`](./docs/ai/ai_settings_sync_webdav.md)**
- Backup/restore (Files/iCloud): **[`docs/ai/backup_restore_icloud.md`](./docs/ai/backup_restore_icloud.md)**

## Quick start (development)

```bash
flutter pub get
flutter gen-l10n
# repo ignores some generated outputs; run build_runner when needed
# dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

> Tip: if you run into SDK mismatch errors with build_runner, try:
> `flutter pub run build_runner build --delete-conflicting-outputs`

## Repo workflow / relationship to upstream

This repository is optimized for **product delivery**.

- Product development happens here (PaperTok + product-only UX changes).
- If we decide to upstream generic AI/translation improvements later, we will do it via a **clean contrib track** (without PaperTok/product-only UX changes).

See: **[`docs/engineering/WORKFLOW_zh.md`](./docs/engineering/WORKFLOW_zh.md)** and **[`docs/engineering/UPSTREAM_CONTRIB_zh.md`](./docs/engineering/UPSTREAM_CONTRIB_zh.md)**.

## License

MIT (same as upstream Anx Reader for the parts we build upon).
See [LICENSE](./LICENSE).

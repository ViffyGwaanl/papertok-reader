**English** | [简体中文](README_zh.md)

<br>

# PaperTok Reader (papertok-reader)

**PaperTok Reader** is an iOS/iPadOS-first AI reading product built on top of
**[Anx Reader](https://github.com/Anxcye/anx-reader)** (MIT).

This repo focuses on a source-grounded reading workflow:

- discover and import papers through PaperTok,
- read EPUB/PDF content in a mobile-first reader,
- ask AI with current-book and library evidence,
- turn useful answers into reviewable knowledge cards, concept links, memory,
  and spaced-review items,
- keep privacy-sensitive configuration local by default.

## Platform Status

- Tested in this repo: **iOS (iPhone)** and **iPadOS (iPad)**.
- Not yet systematically validated in this repo: **Android** and desktop
  platforms.
- If you need a stable, broad multi-platform reader right now, use upstream
  **Anx Reader**.

## What Is Different From Upstream

PaperTok Reader is not only an upstream reader rebrand. The current product
branch adds a PaperTok papers tab, AI provider management, in-reader AI
workflows, local RAG indexing, memory, review queues, and agentic knowledge
features. Generic improvements may later be upstreamed through a clean contrib
track, but product-only PaperTok and AI workflow changes live here.

## Feature Highlights

### PaperTok Papers Feed

- First-class **Papers** tab for the PaperTok academic-paper feed.
- TikTok-style vertical feed and a detail page with explanation, images, and
  original-source actions.
- EPUB/PDF import from paper detail pages, including edition selection when
  English / Chinese / bilingual editions are available.
- Imported papers can be auto-opened in the reader for immediate reading.

### Reader, Translation, and Deep Links

- iPhone/iPad reading-page UX tuned for paper reading.
- Inline EPUB full-text translation with translated text below the original.
- Per-book translation cache, failed-segment retry, progress HUD, and a
  translation-specific provider/model override.
- Reader deep links use `paperreader://reader/open?...` so AI evidence,
  review items, graph nodes, and memory sources can jump back to the original
  book location when a valid `bookId` / `href` / `cfi` is available.

### AI Chat and Provider Center

- Flutter-native Provider Center with built-in providers and custom providers:
  OpenAI-compatible, OpenAI Responses, Anthropic, and Gemini.
- In-chat provider/model switching.
- Thinking level selector and collapsible Thinking / Answer / Tools sections.
- OpenAI Responses compatibility toggles for `previous_response_id`
  continuation and reasoning summaries.
- Editable chat history, regenerate-from-here, and conversation tree variants
  for branching / rollback without losing later turns.
- Multimodal attachments for images and text-like files with configurable
  limits.
- EPUB image analysis: tap an image, analyze it with a multimodal model, and
  optionally send the result into the knowledge review flow.

### RAG and AI Indexing

- Library AI index (`ai_index.db`) with queue controls, pause/resume/cancel,
  retry, rebuild, and restart recovery.
- Current-book and library semantic-search tools:
  `semantic_search_current_book` and `semantic_search_library`.
- Hybrid retrieval with FTS/BM25 candidates, vector scoring, provenance, and
  reader jump links.
- Current-book search has mobile resource guardrails such as bounded fallback
  vector scans, FTS prefiltering, cancellation, and lower UI churn during AI
  requests.
- Embedding/rerank provider smoke tests can be run against a local OpenAI-like
  endpoint when needed.

### Memory and Review Inbox

- Local Markdown memory store: long-term `MEMORY.md` plus daily notes.
- AI chat can create memory candidates instead of silently writing permanent
  memory.
- Memory search supports local text search and semantic retrieval when the
  embedding setup is available.
- Review Inbox is the safety gate for AI-generated or imported knowledge
  assets: approve, dismiss, apply, and inspect sources before assets become
  durable user knowledge.
- Review items preserve source references and show source details when a reader
  deep link is not available.

### Knowledge Cards, Concept Graph, and Spaced Review

- **Knowledge Cards** are inspired by MarginNote-style excerpt cards: selected
  text, AI chat answers, Seminar conclusions, image analysis, and RAG evidence
  can become reviewable cards.
- Cards are draft/pending by default. They require source evidence and user
  approval before they become durable knowledge assets.
- Review Inbox renders card bodies as Markdown and keeps provenance visible.
- Approved cards can create spaced-review items.
- **Concept Graph** explores local concept nodes and evidence-backed
  relationships, taking inspiration from WikiLinks-style concept exploration
  and Understand-Anything-style graph thinking.
- Graph nodes/edges are derived from reviewed cards, Seminar handoffs, and
  RAG/GraphRAG candidates; formal relationships remain review-gated.

### AI Seminar

- OpenMAIC-inspired multi-role discussion mode for reading questions.
- Default roles: critical, supportive, synthesizer; optional verifier role.
- Seminar uses role agents orchestrated by generated prompts, not a single
  static prompt. Each role receives the evidence bundle, prior turns, and
  output rules.
- Runtime page shows role cards, evidence chips, Markdown-rendered turns,
  shared whiteboard entries, synthesis, usage/cost estimates, retry/cancel, and
  send-to-review handoff.
- Dedicated Seminar settings page configures the verifier default and local
  budget guardrails.

### Share Sheet, Shortcuts, and Tools

- Unified Share & Shortcuts settings for default routing, prompt presets,
  callback behavior, cleanup, diagnostics, and attachment limits.
- iOS Shortcuts tools can return results through `paperreader://shortcuts/...`
  without being confused with reader-open deep links.
- AI tools include memory read/search/append/replace, current-book and library
  search, and governed tool execution.
- Custom skills have schema validation, parser/runtime injection gates, scene
  narrowing, and tool whitelists.

### Sync, Backup, and Export

- WebDAV sync for non-secret AI settings such as provider/model/prompt/UI
  preferences.
- Plain backups never include API keys. API keys can be included only through
  encrypted backup.
- Manual backup/restore supports Memory and AI index options.
- Knowledge asset export and remote sync flows route conflicts, incoming
  remote assets, and review-history imports through Review Inbox instead of
  blindly overwriting local data.
- Remote writes use safety guards, rollback paths, and conflict staging for
  knowledge cards.

## User-Facing Entry Points

- Paper feed: `Home -> Papers`
- AI provider management: `Settings -> AI -> AI Provider Center`
- Library AI index: `Settings -> AI Index (Library)` / AI index settings entry
- AI knowledge review: `Settings -> AI -> Review Inbox`
- Knowledge graph: `Settings -> AI -> Concept graph`
- Spaced review: `Settings -> AI -> Spaced review`
- AI Seminar: `Settings -> AI -> Seminar Mode`
- Seminar defaults: `Settings -> AI -> Seminar settings`
- Selected text in reader: context menu actions for Knowledge Card, Seminar,
  and Concept Graph
- Memory: Memory settings/page, with optional Home tab exposure
- Share/Shortcuts: `Settings -> Share & Shortcuts Panel`

## Privacy and Safety Defaults

- API keys are local-only by default and excluded from plain sync/backup.
- AI-generated content starts as draft or pending review.
- Formal knowledge cards, concept edges, review items, and spaced-review
  entries keep source references whenever possible.
- A chat-only AI answer without a reader anchor can be reviewed, but it cannot
  be silently promoted as a reader-grounded knowledge asset.
- Derived indexes such as `ai_index.db` are treated as rebuildable caches, not
  the source of truth.

## Documentation

- Docs index: **[`docs/README.md`](./docs/README.md)**
- AI / RAG / Memory overview: **[`docs/ai/README.md`](./docs/ai/README.md)**
- Future agentic upgrade spec:
  **[`docs/ai/future_agentic_upgrade/README_zh.md`](./docs/ai/future_agentic_upgrade/README_zh.md)**
- Implementation status:
  **[`docs/ai/future_agentic_upgrade/implementation_status_zh.md`](./docs/ai/future_agentic_upgrade/implementation_status_zh.md)**
- PaperTok feed integration:
  **[`docs/papertok/README.md`](./docs/papertok/README.md)**

### Engineering / Release

- iOS install / signing / TestFlight walkthrough:
  **[`docs/engineering/IOS_DEPLOY_zh.md`](./docs/engineering/IOS_DEPLOY_zh.md)**
- Identifiers source of truth:
  **[`docs/engineering/IDENTIFIERS_zh.md`](./docs/engineering/IDENTIFIERS_zh.md)**
- iOS TestFlight release checklist:
  **[`docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md`](./docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md)**
- Platform test status:
  **[`docs/engineering/PLATFORM_TEST_STATUS_zh.md`](./docs/engineering/PLATFORM_TEST_STATUS_zh.md)**
- Troubleshooting: **[`docs/troubleshooting.md`](./docs/troubleshooting.md)**

## Quick Start (Development)

```bash
flutter pub get
flutter gen-l10n
# Generated outputs are ignored in this repo; run build_runner when needed.
# dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

If `build_runner` hits a Flutter/Dart SDK mismatch, try:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Repo Workflow / Relationship to Upstream

This repository is optimized for product delivery:

- PaperTok and product-only AI/knowledge UX evolves here.
- Generic AI/translation improvements can later be upstreamed through a clean
  contrib track without PaperTok-specific changes.

See:
**[`docs/engineering/WORKFLOW_zh.md`](./docs/engineering/WORKFLOW_zh.md)**
and
**[`docs/engineering/UPSTREAM_CONTRIB_zh.md`](./docs/engineering/UPSTREAM_CONTRIB_zh.md)**.

## License

MIT (same as upstream Anx Reader for the parts we build upon).
See [LICENSE](./LICENSE).

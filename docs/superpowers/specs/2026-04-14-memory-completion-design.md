# Memory Completion — Design Spec

**Date:** 2026-04-14
**Status:** Draft, awaiting user review
**Scope:** Sub-project B (B1 + B2 + B3) — closes the three remaining gaps in the Memory feature so it ships at v1.

## Motivation

The Memory feature currently captures candidates from chat sessions and offers a Review Inbox in `Settings → Memory`. Three gaps block it from feeling complete:

1. **Source jump-back is impossible.** A reviewed memory has no link back to the book/cfi or chat message that produced it.
2. **There is no organize entry point.** Memory is buried under Settings; there is no top-level destination, no browse view of `MEMORY.md` / daily notes, no tags, no bulk operations.
3. **Auto-write rules are opaque.** The user has no idea why a candidate was captured and no way to enable/disable individual rules.

This spec covers all three in one cohesive feature ship. They share data model and surfaces, so splitting them creates rework.

## Out of scope

- Embedding model changes / RAG retrieval ranking
- Memory sync to a remote server
- Cross-device collaboration

## Architecture

```
                     ┌───────────────────────┐
                     │  MemoryCandidate v2   │
                     │  (+ source ref,       │
                     │   + rationale,        │
                     │   + tags)             │
                     └──────────┬────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌─────────────┐         ┌────────────┐         ┌────────────────┐
│ Capture     │         │  Inbox     │         │  Browse / Org  │
│ Rules       │ ───────►│  + Apply   │ ───────►│  (top-level    │
│ (B3)        │         │  (B1 jump) │         │   Memory page) │
└─────────────┘         └────────────┘         └────────────────┘
```

## B1 — Source jump-back

### Data model

`MemoryCandidate` schema bump v1 → v2. New optional fields:

```dart
class MemoryCandidate {
  // ... existing fields
  final int? bookId;        // foreign key to books table
  final String? cfi;        // EPUB navigation pointer
  final String? chapter;    // human-readable chapter name
  final MemorySourceKind sourceKind; // chat | reading | manual
}

enum MemorySourceKind { chat, reading, manual }
```

`review_inbox_v2.json` migration: read v1, add `sourceKind: 'chat'` for every existing candidate, write v2. Backward read of v1 also continues to work for ~one release.

### Capture rule

When `MemoryWorkflowService.captureSessionDigest()` runs, it inspects `currentReadingProvider`. If a book is currently being read, the candidate gets `bookId / cfi / chapter` from the current reading state and `sourceKind: reading`. Otherwise `sourceKind: chat`.

### Navigation

Two new methods on `MemoryWorkflowService`:

- `Future<void> openInReader(MemoryCandidate)` — calls `pushToReadingPageWithContainer(container, context, book, cfi: c.cfi)` if `bookId` resolves to a real book.
- `Future<void> openInConversation(MemoryCandidate)` — opens AI chat at `conversationId` and scrolls to `messageNodeId` if both present (uses existing AI chat history navigation).

### UI

In every memory row that already shows `sourcePointer`/`rawContextRef`, add an icon-button row at the bottom:

- Book icon → "Open in reader" (only if `sourceKind == reading`)
- Chat bubble icon → "Open conversation" (only if `conversationId != null`)
- Both buttons hidden if data is missing — never broken navigation

## B2 — Better organize entry point

### New top-level destination

Add a "Memory" tab to the bottom navigation host (`lib/page/home_page/home_page.dart`). It sits between Statistics and Settings, with the brain icon (`Icons.psychology_outlined`).

### MemoryHomePage layout

```
┌────────────────────────────┐
│  Memory                    │  AppBar: title + search icon + filter
├────────────────────────────┤
│  ▷ Inbox  (3 pending)      │  collapsed section, badge
├────────────────────────────┤
│  TODAY                     │  section header
│  • Daily note 2026-04-14   │
├────────────────────────────┤
│  LONG-TERM                 │
│  • Memory entry 1          │
│  • Memory entry 2          │
└────────────────────────────┘
```

- Browse `MEMORY.md` long-term entries + the last 14 daily notes
- Each row uses the existing Claude card style (warm card bg, fg/secondary text, monochrome icons)
- Tap → opens a detail view with the markdown rendered, a tag editor at the top, and the new B1 navigation buttons
- Top app bar has a search icon (full-text search across memory files — already implemented in `MemorySearchService`) and a filter (by tag, by source kind, by date)
- Pending Inbox section count is shown as a badge on the bottom-nav Memory tab when > 0

### Tags

New `MemoryCandidate.tags: List<String>` field (also v2 migration). Tags are user-editable in the detail view. No predefined taxonomy. Free-form. Persisted alongside the entry in the markdown file as a YAML front-matter block.

### Bulk operations

Long-press on any memory row → enter selection mode. Multi-select toolbar at top with: Delete, Move to Long-term, Move to Daily, Add tag, Export. Standard selection patterns.

## B3 — Smarter explainable auto-write

### Surface what already exists

`MemoryCandidate` already stores `triggerKind`, `confidence`. Both are unused in UI today. Add to the inbox row:

- A small badge near the row title showing the trigger source: `Session digest` / `Provider switch` / `Highlight streak` / `Manual`
- A confidence dot (3 colors keyed to value buckets — green ≥ 0.8, amber 0.5–0.8, gray < 0.5)
- A new `rationale: String?` field (v2 schema) that the digest service writes when creating the candidate. Brief 1-sentence English text, e.g. *"Captured because this point was raised three times in the same session."*

### New rules (post-spec, optional)

- **Highlight streak**: after the user creates 3 highlights in the same chapter, prompt to capture a memory about that chapter
- **Repeat question**: if the same question is asked twice in different sessions, capture the answer
- **Manual quote**: long-press on a chat message → "Save to memory"

These three are nice-to-have. Ship the explainability bits first; rules can be added incrementally.

### Settings

Under `Settings → Memory → Workflow`, add a section **Auto-capture rules**. Each rule is a row with:
- Title + 1-sentence description
- Switch (enabled/disabled)
- A small "?" icon → tap reveals the explanation paragraph

Persist each rule as a `bool` pref keyed `memoryRule.<ruleId>` with default `true`.

## Data flow

```
chat message stream
        │
        ▼
MemoryWorkflowService.captureSessionDigest()
        │
        ├── inspect currentReadingProvider → bookId/cfi/chapter
        ├── inspect prior chat → repeat question check
        ├── compute rationale string
        ├── for each enabled rule, generate up to N candidates
        ▼
MemoryCandidateStore (v2 JSON)
        │
        ├── persisted to .workflow/review_inbox_v2.json
        ▼
MemoryHomePage / Inbox UI ◄────── user reviews, applies, jumps to source
```

## Migration

- New file `review_inbox_v2.json` written on first save under v2 schema
- On read: try v2 first, else read v1 and synthesize defaults (`sourceKind: chat`, `tags: []`, `rationale: null`)
- Schema version is part of the JSON top-level for forward-compat

## Testing strategy

- Unit: schema migration v1→v2 round-trip; capture-rule decisions when reading/chat context present/absent; rationale generation
- Widget: `MemoryHomePage` empty + populated; `MemoryDetail` tag editor; bulk select toolbar
- Integration: open a book, chat about it, end session, verify candidate has `bookId/cfi`, tap "Open in reader" → opens at correct cfi

## Implementation order

The three features are executed as parallel sub-waves after the spec is approved:

- **B1** — schema + capture + nav (touches `memory_candidate.dart`, `memory_workflow_service.dart`, `memory_candidate_store.dart`, `memory.dart` settings page)
- **B2** — `MemoryHomePage` + bottom-nav entry + browse view + tag editor + search/filter (touches `lib/page/home_page/`, new `lib/page/memory/`, `markdown_memory_store.dart`)
- **B3** — rationale generation + UI surfacing + per-rule prefs + new rules toggles (touches `memory_workflow_service.dart`, `memory_session_digest_service.dart`, `lib/page/settings_page/memory.dart`)

B1 and B3 share `MemoryWorkflowService` so will be sequenced rather than parallel. B2 is independent — runs alongside B1.

## Risks

- **Schema migration data loss**: mitigated by reading v1 + synthesizing defaults rather than rewriting in place
- **Bottom nav slot pressure**: 5-item bar — adding Memory makes 6. Mitigation: collapse Statistics + Memory into a "Insights" tab? Defer decision until after testing the 6-tab variant
- **Tag explosion**: free-form tags with no taxonomy can grow unbounded. Mitigation: tag autocomplete from existing tags in the editor; no other constraint
- **Confidence threshold tuning**: green/amber/gray buckets are guesses. Mitigation: configurable in advanced settings, default conservative

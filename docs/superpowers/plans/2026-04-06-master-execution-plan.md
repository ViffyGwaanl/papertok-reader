# Master Execution Plan — Phases 5-12 Completion

> Superseded on 2026-04-07 by [`2026-04-07-swift-native-closure-master-plan.md`](./2026-04-07-swift-native-closure-master-plan.md). This 2026-04-06 document reflects the pre-integration view of the branch and should no longer be used as the active execution source.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete all remaining phases (5-12) of the PaperTok Reader Swift native migration, producing a fully functional iOS/macOS app with EPUB/PDF reading, AI chat, 46 tools, academic papers feed, and platform integration.

**Architecture:** Phased execution with maximum parallelism. Independent phases run concurrently via isolated worktrees. Each phase produces a buildable, testable commit on `swift-native`.

**Tech Stack:** Swift 5.9+, SwiftUI, GRDB.swift, Readium 3.x, PDFKit, EventKit, AppIntents, Swift Testing

---

## Dependency Graph

```
Phase 7 (UI Views)      ─┐
Phase 5b (Anthropic)     ├──→ Phase 9 (AI Chat UI) ──→ Phase 12 (Platform)
Phase 11 (Papers)        ─┘
Phase 8 (EPUB Reader)    ───→ Phase 10 (46 Tools)  ──→ Phase 12 (Platform)
```

## Execution Waves

### Wave 1 — Independent (run in parallel)

| Task | Plan Document | Scope | Dependencies |
| --- | --- | --- | --- |
| Phase 7: Settings/Notes/Stats UI | `phase7-settings-notes-statistics-ui.md` | 3 SwiftUI screens + routing | Phase 6 ✅ |
| Phase 5b: AnthropicProvider | `phase5-ai-ptaiservices.md` (Task 8+) | Messages API + SSE + tools | Phase 2 ✅ |
| Phase 11: Papers Feed | `phase11-papers-page.md` | 6 files, ViewModel + 5 views | Phase 2 ✅ |

### Wave 2 — Depends on Wave 1

| Task | Plan Document | Scope | Dependencies |
| --- | --- | --- | --- |
| Phase 8: EPUB Reader | `phase8-epub-reader.md` | 6 files, Readium SDK | Phase 3 ✅ |
| Phase 9: AI Chat UI | `phase9-ai-chat-ui.md` | 11 SwiftUI views | Phase 5b |

### Wave 3 — Depends on Wave 2

| Task | Plan Document | Scope | Dependencies |
| --- | --- | --- | --- |
| Phase 10: 46 AI Tools | `phase10-ai-tools.md` | 46 tool structs + registry | Phase 8, Phase 5 |
| Phase 12: Platform Integration | `phase12-platform-integration.md` | EventKit, Intents, L10n | All phases |

---

## Detailed Task List

### Wave 1, Task A: Phase 7 — Settings / Notes / Statistics UI

Since the worktree branch is no longer available, implement fresh:

- [ ] **Step 1:** Create `SettingsScreen` in `App/ContentView.swift` — Form/Section layout with theme picker, OLED toggle, accent color grid, font size slider, page turn mode picker, About section
- [ ] **Step 2:** Create `NotesScreen` in `App/ContentView.swift` — grouped notes by book, search, swipe-to-delete, empty state
- [ ] **Step 3:** Create `StatisticsScreen` in `App/ContentView.swift` — 3 stat cards + 91-day reading heatmap
- [ ] **Step 4:** Add `dailyReadingData` to `StatisticsViewModel` (fetch from ReadingTimeDAO)
- [ ] **Step 5:** Update `ContentView.swift` routing — replace 3 placeholders with real screens
- [ ] **Step 6:** Build and verify all 3 screens render correctly
- [ ] **Step 7:** Commit

### Wave 1, Task B: Phase 5b — AnthropicProvider

- [ ] **Step 1:** Create `AnthropicProvider.swift` with Messages API request/response types
- [ ] **Step 2:** Implement `complete()` — POST to `/v1/messages`, map response to ChatResponse
- [ ] **Step 3:** Implement `stream()` — SSE parsing for `content_block_delta`, `message_delta`
- [ ] **Step 4:** Add extended thinking support (`thinking` content blocks)
- [ ] **Step 5:** Add tool use support (tool_use content blocks → ToolCall mapping)
- [ ] **Step 6:** Write unit tests (request serialization, SSE parsing, error mapping)
- [ ] **Step 7:** Commit

### Wave 1, Task C: Phase 11 — Papers Feed

- [ ] **Step 1:** Create `PapersViewModel` — load cards from PaperTokAPI, filter, search, like/unlike
- [ ] **Step 2:** Create `PaperCardView` — image carousel, gradient overlay, title, like button
- [ ] **Step 3:** Create `PapersFilterBar` — date picker, search, liked-only toggle
- [ ] **Step 4:** Create `PaperDetailView` — bottom sheet with abstract, authors, download
- [ ] **Step 5:** Create `PaperDownloadButton` — URLSession download progress
- [ ] **Step 6:** Create `PapersView` — vertical TabView paging feed
- [ ] **Step 7:** Wire into ContentView routing (replace PapersPlaceholderView)
- [ ] **Step 8:** Write tests + commit

### Wave 2, Task D: Phase 8 — EPUB Reader

- [ ] **Step 1:** Update PTReader Package.swift with Readium 3.x dependency
- [ ] **Step 2:** Create `EPUBTOCMapper` — ReadiumLink tree → ChapterEntry
- [ ] **Step 3:** Create `EPUBPublicationOpener` — open .epub → Publication
- [ ] **Step 4:** Create `EPUBContentBridge` — implement BookContentBridge for EPUB
- [ ] **Step 5:** Create `EPUBAnnotationBridge` — CFI ↔ Decorator mapping
- [ ] **Step 6:** Create `EPUBNavigatorCoordinator` — @Observable navigation state
- [ ] **Step 7:** Create `EPUBReaderView` — UIViewControllerRepresentable wrapper
- [ ] **Step 8:** Write tests + commit

### Wave 2, Task E: Phase 9 — AI Chat UI

- [ ] **Step 1:** Extend AIChatViewModel — provider switching, attachments, streaming state
- [ ] **Step 2:** Create `ChatInputView` — text field + send + attachment picker
- [ ] **Step 3:** Create `MessageBubbleView` — user/assistant/system message rendering
- [ ] **Step 4:** Create `ToolStepView` — tool call display with status indicators
- [ ] **Step 5:** Create `ThinkingBlockView` — collapsible thinking content
- [ ] **Step 6:** Create `MessageListView` — ScrollView with auto-scroll
- [ ] **Step 7:** Create `ProviderPickerSheet` — provider/model selection
- [ ] **Step 8:** Create `BranchNavigatorView` — variant switching UI
- [ ] **Step 9:** Create `AIChatView` — main container assembling all components
- [ ] **Step 10:** Create `ToolApprovalSheet` + `AttachmentRowView`
- [ ] **Step 11:** Wire into ContentView routing + write tests + commit

### Wave 3, Task F: Phase 10 — 46 AI Tools

- [ ] **Step 1:** Create `ToolRegistry` — register all tools, generate JSON Schema for LLM
- [ ] **Step 2:** Implement utility tools (5): current_time, calculator, fetch_url, web_search, mindmap_draw
- [ ] **Step 3:** Implement book library tools (5): bookshelf_lookup, organize, tags
- [ ] **Step 4:** Implement book content tools (7): metadata, TOC, chapter, fulltext, search, CFI
- [ ] **Step 5:** Implement annotation tools (3): create_highlight, create_note, notes_search
- [ ] **Step 6:** Implement reading history + semantic search tools (3)
- [ ] **Step 7:** Implement calendar tools (6): list, get, create, update, delete events
- [ ] **Step 8:** Implement reminders tools (11): list, get, create, update, delete, complete
- [ ] **Step 9:** Implement memory tools (3): read, write, search daily memory
- [ ] **Step 10:** Implement agent tools (2): shortcuts_run, spawn_sub_agent
- [ ] **Step 11:** Wire ToolRegistry into app + write tests + commit

### Wave 3, Task G: Phase 12 — Platform Integration

- [ ] **Step 1:** CalendarService + RemindersService (EventKit wrappers)
- [ ] **Step 2:** App Intents (OpenBookIntent, AskAIIntent, IntentsDonationService)
- [ ] **Step 3:** Deep Links (DeepLinkRouter, DeepLinkHandler)
- [ ] **Step 4:** macOS MenuBarCommands
- [ ] **Step 5:** FlutterMigrationService (detect + migrate Flutter SQLite DB)
- [ ] **Step 6:** Share Extension (ShareViewController, ShareHandler)
- [ ] **Step 7:** Localization — 14 languages in Localizable.xcstrings
- [ ] **Step 8:** Final integration wiring in PaperTokReaderApp.swift
- [ ] **Step 9:** Full test suite + TestFlight build + commit

---

## Success Criteria

- [ ] All 6 packages build with zero errors
- [ ] All tests pass (target: 200+ tests)
- [ ] PDF and EPUB reading works end-to-end
- [ ] AI chat streams responses from OpenAI and Anthropic
- [ ] All 46 AI tools registered and functional
- [ ] Papers feed loads and displays academic papers
- [ ] Settings/Notes/Statistics screens fully functional
- [ ] 14 languages localized
- [ ] TestFlight build uploaded successfully

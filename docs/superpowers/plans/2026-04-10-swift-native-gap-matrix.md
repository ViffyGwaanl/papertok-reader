# Swift-Native Spec-to-Main-to-Swift Gap Matrix

**Date:** 2026-04-10  
**Branch:** `swift-native`  
**Purpose:** Single truth table for closure work across the approved Swift-native contract, the current `swift-native` branch state, and the `main` Flutter product behavior.

## Status Legend

- `complete`: implemented and freshly verified on the current branch state
- `partial`: meaningful implementation exists, but parity-critical behavior remains open
- `unverified`: implementation exists, but current evidence is not sufficient
- `missing`: not meaningfully implemented for closure purposes

## Matrix

| FR | Scope | `main` parity reference | `swift-native` current state | Status | Target wave | Verification focus |
|---|---|---|---|---|---|---|
| FR-01 | Navigation and layout on iPhone, iPad, macOS, tab customization | `lib/page/home_page.dart`, `lib/widgets/home/**`, settings navigation surfaces in `lib/widgets/settings/**` | Six-tab shell exists, but iPad/macOS native layout and tab customization parity are incomplete; no standalone macOS target yet | partial | Wave B | iPhone/iPad/macOS navigation walkthroughs, app-shell tests, platform build matrix |
| FR-02 | Papers feed, filters, detail, download, import | `lib/service/papertok/**`, `lib/page/home_page.dart`, related feed/detail widgets in Flutter app | Feed/detail/download/import flow exists and has targeted branch-local verification, but full parity and richer detail behavior remain open | partial | Wave B | PTFeatures papers regressions, download/import end-to-end walkthrough, main behavior checklist |
| FR-03 | Bookshelf, tags, groups, context menu, import modes, AI organize | `lib/service/book.dart`, `lib/providers/book_list.dart`, `lib/providers/book_filters.dart`, `lib/providers/tags.dart`, `lib/providers/tb_groups.dart`, `lib/widgets/bookshelf/**` | Core bookshelf UX exists with tags/groups/edit/undo/import, but custom order, drag/drop hierarchy behavior, AI organize, and directory scanning parity remain open | partial | Wave B | Bookshelf regressions, directory lifecycle tests, three-platform organization walkthrough |
| FR-04 | EPUB reader parity | `lib/page/reading_page.dart`, `lib/widgets/reading_page/**`, `lib/widgets/context_menu/**`, `lib/providers/book_toc.dart`, `lib/providers/toc_search.dart` | Readium-based EPUB reader, TOC/search, annotations, per-book settings, image workflow, and AI host exist, but full parity across settings/product polish remains open | partial | Wave C | PTReader + PTFeatures reader tests, EPUB walkthroughs on iPhone/iPad/macOS |
| FR-05 | PDF reader parity | `lib/page/reading_page.dart`, `lib/widgets/reading_page/**`, PDF extraction/OCR and note flows in Flutter reader stack | PDF rendering/search/OCR/annotations exist, but deeper settings parity, full product polish, and platform walkthrough coverage remain open | partial | Wave C | PDF bridge tests, reader feature tests, PDF walkthroughs on all three platforms |
| FR-06 | AI chat system | `lib/providers/ai_chat.dart`, `lib/widgets/ai/**`, `lib/models/ai_conversation_tree.dart` | AI chat shell, streaming, tool approvals, branching, and provider integration exist, but user-facing parity is incomplete | partial | Wave D | AIChat regressions, provider/attachment/history walkthroughs |
| FR-07 | AI tools product surface | `lib/service/bookshelf/bookshelf_organize_service.dart`, `lib/service/rag/**`, tool-oriented AI chat UI in `lib/widgets/ai/**` | Tool registry/runtime honesty is good and freshly re-verified, but end-user tool-product parity is incomplete | partial | Wave D | PTAIServices runtime tests, AI tool walkthroughs, main parity checklist |
| FR-08 | In-reader AI panel | `lib/widgets/ai/ai_chat_bottom_sheet.dart`, reader context menu and reading page AI entry points | Reader AI host exists, but full in-reader AI panel parity across platforms remains open | partial | Wave C | Reader AI regressions, panel layout walkthroughs, cross-platform reader hosting |
| FR-09 | Translation engine | `lib/service/translate/**`, translation-related reader context menus | Branch has some AI translation foundations, but full translation product parity is not yet closed | partial | Wave D | Translation workflow walkthroughs, provider/tool verification |
| FR-10 | RAG | `lib/service/rag/**`, AI book index providers | Foundation exists, but end-user operational parity for indexing/search flows remains open | partial | Wave D | RAG indexing/search tests, feature walkthroughs |
| FR-11 | Memory system | `lib/service/memory/**`, AI chat related settings/providers | Memory foundations exist, but user-visible parity and workflow closure remain open | partial | Wave D | Memory write/read/search workflows, AI product walkthroughs |
| FR-12 | Notes and highlights product parity | `lib/page/book_notes_page.dart`, `lib/widgets/book_notes/**`, reader note widgets, export flows | Notes tab and annotation paths exist and are significantly improved, but broader end-to-end parity verification is still needed | partial | Wave C | Notes/reader annotation regressions, export walkthroughs |
| FR-13 | Statistics and analytics | `lib/service/statistic.dart`, `lib/widgets/statistic/**`, providers under `lib/providers/*reading*` and `lib/providers/*statistic*` | Statistics productization is strong and branch-local tests exist, but screen-level parity verification and three-platform walkthroughs are still needed | partial | Wave F | Notes/statistics regressions, dashboard walkthroughs, timezone/data integrity checks |
| FR-14 | Sync and backup | `lib/providers/sync.dart`, `lib/service/sync/**`, `lib/service/backup/**`, WebDAV settings widgets | Only lower-level pieces exist in Swift; full sync/backup UX and recovery parity remain open | partial | Wave F | Sync client tests, backup/restore walkthroughs, data integrity verification |
| FR-15 | TTS | `lib/providers/tts_providers.dart`, `lib/widgets/reading_page/tts_widget.dart`, `lib/widgets/reading_page/tts_fab.dart` | Core TTS service exists in Swift, but full product-surface parity including controls and background/lock-screen behavior remains open | partial | Wave C and Wave F | Reader TTS walkthroughs, audio-session/platform verification |
| FR-16 | Settings depth and configuration | `lib/widgets/settings/**`, settings sections in Flutter pages, AI/sync/theme/service config forms | Settings tab exists in Swift, but depth is still much shallower than `main` and the approved contract | partial | Wave B and Wave F | Settings walkthrough matrix, localization coverage, config persistence tests |
| FR-17 | Platform integration | `lib/service/deeplink/**`, `lib/service/shortcuts/**`, share/import paths, platform channels | Deep links, share, EventKit, intents, and migration shells exist, but full end-to-end parity is still open | partial | Wave E | App-platform tests, share/deep-link/intents walkthroughs, app-group validation |
| FR-18 | Localization | Flutter l10n surfaces throughout `lib/**` and generated strings | `.xcstrings` exists and is growing, but complete coverage verification is still open | partial | Wave E | Localized walkthroughs on touched flows, string catalog audits |
| FR-19 | Flutter-to-Swift data migration | `lib/page/migration_page.dart`, legacy DB/settings/file behavior in Flutter app | Migration service exists and has targeted tests, but full data/file/settings migration completeness is still open | partial | Wave E | Migration fixtures, app migration walkthroughs, data integrity checks |
| FR-20 | MCP | `lib/service/mcp/**`, related models under `lib/models/mcp_*` | Product surface is clearly incomplete in Swift; foundations may exist but parity is not closed | partial | Wave D | MCP config/workflow verification, AI product walkthroughs |
| FR-21 | KAIROS proactive assistant | `lib/providers/kairos_provider.dart`, related settings/AI feature surfacing in Flutter | Effectively absent as a finished Swift product surface | missing | Wave F | KAIROS settings and behavior walkthroughs, parity against Flutter product behavior |
| FR-22 | Sub-agent system | AI orchestration and shortcuts handoff services under `lib/service/shortcuts/**`, AI chat/tool flows | Swift runtime support is partially present and recently improved, but product surface parity is incomplete | partial | Wave D | Sub-agent runtime tests, AI chat product walkthroughs |
| FR-23 | Skills system | Skills and AI feature surfacing in Flutter settings/chat UI | Product surface is incomplete in Swift | partial | Wave D and Wave F | Settings + AI workflow verification for skills discovery/use |

## Non-Functional Cross-Cuts

| NFR | Focus | Current state | Target wave |
|---|---|---|---|
| NFR-01 | Performance | Some targeted verification exists, but no closure-grade three-platform evidence yet | Wave G |
| NFR-02 | Security | Keychain/app-group foundations exist; sync, migration, extension, and macOS target security still need closure verification | Waves A, E, F, G |
| NFR-03 | Accessibility | Not yet defended with closure-grade evidence | Wave G |
| NFR-04 | Offline support | Reader/local data foundations exist; sync and AI fallback expectations still need explicit verification | Waves C, F, G |
| NFR-05 | Data integrity | Reading time, imports, and migration have partial evidence; full closure still open | Waves B, C, E, F, G |

## Immediate Notes

- This matrix is intentionally conservative. Existing implementation only counts as `complete` when fresh evidence exists on the current branch state.
- The `main` parity references above identify the primary Flutter code families for comparison during closure work. Wave A should refine these into more granular per-feature references where needed.
- The branch currently has no standalone macOS target in `project.yml`, so any row that depends on native macOS delivery cannot reach `complete` before Wave A.

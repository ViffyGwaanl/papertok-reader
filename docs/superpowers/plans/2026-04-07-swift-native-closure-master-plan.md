# Swift-Native Specs Completion Master Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete `swift-native` against the 2026-04-03 requirements and migration-design specs, with release/TestFlight treated as a final delivery gate rather than a substitute for feature parity.

**Architecture:** Execute in subsystem waves mapped to FR groups. Each wave must distinguish three things explicitly: what already exists in the branch, what the spec still requires, and what fresh verification proves. Build/test success is necessary but never sufficient; every wave must close behavior gaps, not just compile surfaces.

**Tech Stack:** Swift 5.9+, SwiftUI, Observation, GRDB.swift, Readium 3.x, PDFKit, Vision, AppIntents, EventKit, XcodeGen, Swift Testing, XCTest, Fastlane

---

## Source of Truth

This plan is anchored to:

- `docs/superpowers/specs/2026-04-03-swift-migration-requirements.md`
- `docs/superpowers/specs/2026-04-03-swift-native-migration-design.md`

This file replaces the earlier "closure" framing while keeping the same path for continuity.

---

## Fresh Baseline on 2026-04-07

- [x] `xcodegen generate`
- [x] `xcodebuild -list -project PaperTokReader.xcodeproj`
- [x] `swift test --package-path Packages/PTCore`
- [x] `swift test --package-path Packages/PTNetworking`
- [x] `swift test --package-path Packages/PTUI`
- [x] `swift test --package-path Packages/PTAIServices`
- [x] `xcodebuild ... -scheme PaperTokReaderAppTests ... -only-testing:PaperTokReaderTests/FlutterMigrationServiceTests test`
- [x] `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/PapersViewModelTests -only-testing:PTFeaturesTests/BookshelfViewModelTests -only-testing:PTFeaturesTests/BookImportServiceEPUBTests test`
- [x] `xcodebuild ... -scheme PTReaderPackageTests ... test`
- [x] `xcodebuild ... -scheme PaperTokReader ... build`

Verified repo-local fixes completed in this cycle:

- [x] restored a real `PaperTokReader` app scheme in `project.yml`
- [x] re-generated `PaperTokReader.xcodeproj`
- [x] corrected `AIChatViewModelExtTests` so tool-call tests match the current multi-round protocol
- [x] relaxed Flutter legacy DB preflight to accept older supported schemas and added a fresh targeted migration regression test
- [x] extracted and persisted real EPUB cover art during import and added a fresh real-fixture regression test
- [x] re-ran the branch verification matrix on current dirty state

---

## Already-Landed High-Value Work in This Branch

These are implemented branch-local improvements that the next waves should build on rather than redo:

- **Papers / import integrity**
  - PaperTok detail decoding now matches the live API payload actually returned today
  - language-aware explanation/dialogue selection is wired through feed + detail
  - API timestamps with fractional seconds and no timezone now decode correctly
  - paper download now reports real byte progress plus import-phase status
  - original-source and raw-markdown links are surfaced from detail
  - deterministic MD5-based import filenames
  - real EPUB metadata + cover extraction now persists into `Covers/`
  - duplicate EPUB import coverage
  - actual task cancellation for paper downloads

- **Bookshelf interaction baseline**
  - soft delete now retains undo state
  - `BookDAO.restore(id:)` supports undoing a soft delete
  - bookshelf rows now expose `Open` / `Edit` / `Delete` / `Move to Group` / `Tags`
  - tag filters now have a dedicated management/filter sheet
  - group hierarchy now has a dedicated management sheet for create/rename/delete/dissolve
  - book metadata now has a persisted edit path for title/author

- **AI runtime honesty**
  - tool exposure filtered by runtime prerequisites
  - `spawn_sub_agent` accepts normalized type aliases
  - `AIChatViewModel` advertises only runnable tools

- **Project verification surface**
  - iOS package-test schemes for `PTFeatures` and `PTReader`
  - restored main app scheme for simulator builds

- **Platform shell wiring**
  - app-level work has already touched DeepLink, Share, Migration, App Intents, EventKit, and ContentView integration

---

## Non-Claimable Areas

The branch is **not** currently claimable as complete for these broad areas:

- FR-02 Papers parity
- FR-03 Bookshelf parity
- FR-04/05 EPUB/PDF reader parity
- FR-06/07 AI chat, tools, and provider UX parity
- FR-08 AI panel parity
- FR-09/10/11 translation, RAG, and memory parity
- FR-12/13 Notes and Statistics parity
- FR-14 sync/backup parity
- FR-15 TTS product parity
- FR-16 Settings depth/parity
- FR-17 platform integration parity
- FR-19 Flutter-to-Swift migration completeness
- FR-20/21/22/23 MCP, KAIROS, sub-agent, and skills product surfaces

---

## Wave Plan

### Wave 0: Truth Baseline and Verification

**Status:** completed in this cycle

**Purpose:** stop the branch from drifting on stale release-closure assumptions.

**Files already touched:**

- `project.yml`
- `PaperTokReader.xcodeproj/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/AIChatViewModelExtTests.swift`
- `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`
- `docs/superpowers/plans/2026-04-06-progress-tracker.md`

**Exit criteria:**

- app scheme exists again;
- current dirty branch builds/tests on the verified surfaces;
- verification docs stop overstating completion.

### Wave 1: Papers + Bookshelf Core Parity

**Status:** in progress

**FR coverage:** FR-02, FR-03, part of FR-17

**Primary files:**

- `Packages/PTFeatures/Sources/PTFeatures/Papers/**`
- `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/**`
- `App/ContentView.swift`
- `App/Platform/Share/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/Papers/**`

**What already exists:**

- vertical paged papers feed shell with card imagery, overlays, and near-end pagination
- liked/search/date/language filter state in `PapersViewModel`
- paper detail now follows the selected language and surfaces current API metadata, explanation/dialogue, original link, and raw-markdown link
- paper download worker coverage now includes byte progress, import-phase status, and duplicate-import mapping
- deterministic import into bookshelf with duplicate detection and real EPUB cover extraction
- Bookshelf view-model coverage for undo delete, tags, nested groups, and combined filters
- bookshelf open/import shell, grid/list UX, tag filter/management sheet, group management sheet, and persisted book edit flow
- shared inbox import processing now consumes fully successful events, retains only failed book items for retry, and discards missing files instead of retrying them forever

**What is still missing or not yet verified:**

- authors / venue are still unavailable from the current PaperTok API payload, so that part of the richness gap is upstream rather than only a Swift UI omission
- custom-order sorting and richer bookshelf organization UX are still missing
- visible drag/drop group reordering is still missing
- AI-assisted bookshelf organization
- share/import flows still need settings/diagnostics/preset surfaces; the quick-ask route contract and requested-route persistence already exist and are app-tested
- directory-scanning parity is explicitly split to Wave 1A below instead of being left as ambiguous Wave 1 debt

**Exit criteria:**

- paper download/import is a clean end-to-end path with accurate UI states;
- bookshelf organization features reach minimum parity for tags/groups/context actions;
- directory-scanning mode is no longer ambiguous because its remaining FR-03.5 work is tracked in a dedicated follow-up wave.

- [ ] Surface zh/en selection through papers feed + detail fetches and close paper detail metadata/progress gaps.
- [x] Surface existing Bookshelf tag/group/context operations in UI and close partial-failure import hardening gaps.
- [x] Add/expand PTFeatures and app-level tests for import/share hardening and organization flows.
- [x] Re-run the targeted `PTFeaturesPackageTests` regression matrix for Papers/Bookshelf import work.

### Wave 1A: External Library Directory Scanning

**Status:** pending

**FR coverage:** remaining FR-03.5 dual-mode import parity

**Primary files:**

- `App/ContentView.swift`
- `Packages/PTCore/Sources/PTCore/**`
- `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/**`
- new bookmark / monitoring persistence surfaces as needed

**What already exists:**

- one-shot security-scoped file import for single selected PDFs
- deterministic copy-import into app-local storage
- no user-facing ambiguity anymore that this equals full directory-scanning parity

**What is still missing or not yet verified:**

- folder picker flow for choosing external directories instead of only one-shot file import
- persistent security-scoped bookmarks, stale-bookmark repair, and relaunch reattachment
- monitored-directory persistence model and management UI
- initial scan / re-scan / in-place indexing for `.pdf` and `.epub`
- file monitoring and library reconciliation for add/remove/rename events
- unavailable-directory recovery and reauthorization flow
- regression coverage for bookmark lifecycle, scan dedupe, and monitoring events

**Exit criteria:**

- FR-03.5 no longer depends solely on copy-import mode;
- external-library mode is persisted, recoverable, and monitored;
- tests cover bookmark restoration and reconciliation-critical behavior.

- [ ] Add monitored-directory persistence, bookmark handling, and management UI.
- [ ] Add initial scan / re-scan / file-monitor reconciliation behavior.
- [ ] Add regression coverage for directory lifecycle and unavailable-folder handling.

### Wave 2: Reader Parity (EPUB + PDF)

**Status:** in progress

**FR coverage:** FR-04, FR-05, FR-08, FR-12, FR-15

**Primary files:**

- `Packages/PTReader/Sources/PTReader/**`
- `Packages/PTFeatures/Sources/PTFeatures/Reader/**`
- `App/ContentView.swift`
- `Packages/PTReader/Tests/PTReaderTests/**`

**What already exists:**

- EPUB/PDF routing from bookshelf
- core PDF/EPUB bridges
- reading preferences model surface
- annotation/TOC bridge tests
- TTS service basics
- shared reader-session publication for both EPUB and PDF flows
- runtime-honest AI tool exposure keyed off live reader-session context
- PDF OCR fallback is wired into `PDFContentBridge` and freshly regression-tested
- visible EPUB TOC + full-text search sheets are now surfaced over `EPUBContentBridge`
- visible PDF full-text search is now surfaced over `PDFContentBridge` via a shared reader-controls view-model seam
- EPUB in-reader image viewing is now wired through a Readium JS bridge:
  - tap image in the EPUB flow to open a full-screen viewer
  - pinch to zoom, drag to pan, and double-tap to fit
  - share/export the tapped image
  - hand the tapped image to the existing reader AI panel with a contextual analysis prompt
- initial in-reader AI panel host exists for both reader flows:
  - regular-width docked panel with drag-resize on regular layouts
  - per-book width + left/right persistence
  - compact-sheet presentation on compact layouts
  - minimized AI status bar while hidden but still active
- fresh full `PTReaderPackageTests` verification on the current dirty branch state
- fresh targeted `PTFeatures` reader/AI regression verification on the current dirty branch state
- fresh targeted `PTFeatures` reader-controls regression verification and fresh app build verification on 2026-04-08

**What is still missing or not yet verified:**

- EPUB annotation create/edit/bookmark baseline is already on the user surface, but still lacks broader screen-level walkthrough coverage
- EPUB per-book settings surface and exact-locator search-result navigation are already implemented; remaining settings parity work is primarily PDF-side and deeper font/theme behavior
- PDF annotation create/bookmark/persist/render plus tap-to-reopen edit/delete are now implemented and freshly verified, but broader screen-level walkthrough coverage is still light
- per-book reading settings parity on the user surface remains incomplete mainly on PDF and richer EPUB font/theme behavior
- reader-side TTS product UX and lock-screen/background behavior remain unverified on both EPUB and PDF
- full FR-08 end-user parity beyond the current AI panel shell

**Exit criteria:**

- EPUB/PDF reading flows reach parity on search, annotations, settings, and content extraction;
- PDF OCR fallback and unified content access are demonstrably wired;
- reader-specific tests cover the parity-critical bridges and the in-reader AI host state model.

- [ ] Close EPUB navigation/search/annotation/settings gaps.
- [x] Close PDF extraction/OCR/content-bridge gaps.
- [x] Surface visible EPUB TOC/search plus PDF in-reader search over the live content bridges.
- [x] Close PDF annotation UX gaps.
- [x] Close EPUB in-reader image viewer + AI analysis hooks.
- [ ] Close in-reader AI panel parity.
- [x] Re-run `PTReaderPackageTests`.
- [x] Re-run targeted `PTFeaturesPackageTests` for reader/AI regression coverage.

### Wave 3: AI Chat, Provider, Tools, RAG, Memory

**Status:** in progress

**FR coverage:** FR-06, FR-07, FR-08, FR-09, FR-10, FR-11, FR-20, FR-22, FR-23

**Primary files:**

- `Packages/PTAIServices/Sources/PTAIServices/**`
- `Packages/PTFeatures/Sources/PTFeatures/AIChat/**`
- `App/Platform/AI/**`
- `Packages/PTAIServices/Tests/PTAIServicesTests/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/**`

**What already exists:**

- provider abstractions and tests
- tool registry and runtime-gated exposure
- approval queue and tool execution loop
- app AI tab shell
- partial sub-agent runtime wiring

**What is still missing or not yet verified:**

- provider center UX and settings parity
- real attachment flows
- conversation history / branching UX parity
- surfaced thinking/usage state in the UI
- end-user parity for the full tool/product set
- full RAG/memory UX integration
- productized MCP / skills / sub-agent surfaces

**Exit criteria:**

- AI runtime is honest and product-complete, not just internally testable;
- chat UI reaches parity for provider/model/history/attachment/thinking states;
- tool/RAG/memory flows are verifiably operational in end-user paths.

- [ ] Finish AI chat/product parity work.
- [ ] Finish tool/runtime/RAG/memory/MCP integration work.
- [ ] Re-run `swift test --package-path Packages/PTAIServices`.
- [ ] Re-run `PTFeaturesPackageTests` for AIChat regression coverage.

### Wave 4: Platform Integration + Migration

**Status:** in progress

**FR coverage:** FR-17, FR-18, FR-19

**Primary files:**

- `App/Platform/DeepLink/**`
- `App/Platform/Intents/**`
- `App/Platform/Migration/**`
- `App/Extensions/ShareExtension/**`
- `App/Resources/Localizable.xcstrings`
- `App/PaperTokReaderApp.swift`
- `App/ContentView.swift`

**What already exists:**

- deep-link routing shell
- App Intents shell and donation hooks
- migration service and progress view work
- share extension target, inbox plumbing, localized strings expansion
- share-route contract now distinguishes `aiChat`, `bookshelfImport`, and `ask`, with persisted requested-route metadata plus fallback-to-bookshelf handling for book payloads
- fresh app-level platform verification for `AppAIToolContextFactory`, `DeepLinkRouter`, `FlutterMigrationPlanner`, `FlutterMigrationService`, `MigrationLocalizationCatalog`, `PendingAIRequestStore`, `ShareExtensionInfoPlist`, and `SharedInbox`
- dedicated migration preflight verification for older supported Flutter schemas

**What is still missing or not yet verified:**

- full deep-link/share/import behavior parity
- prompt presets, diagnostics surfaces, and TTL configuration for share routing
- headless App Intents behavior parity
- Flutter DB/settings/files migration completeness
- localization coverage verification
- extension/app-group/release-signing validation after behavior parity

**Exit criteria:**

- shared imports, intents, deep links, and migration all work end-to-end against live app state;
- localization is not treated as an afterthought;
- release-signing work begins only after product behavior is verified.

- [ ] Finish share/deep-link/intents end-to-end behavior.
- [ ] Finish Flutter migration completeness and verification.
- [ ] Verify localization on the touched flows.
- [x] Re-run `xcodebuild ... -scheme PaperTokReader ... build`.

### Wave 5A: Notes + Statistics Productization

**Status:** substantially complete, with screen-level verification hardening still open

**FR coverage:** FR-12, FR-13

**Primary files:**

- `Packages/PTFeatures/Sources/PTFeatures/Notes/**`
- `Packages/PTFeatures/Sources/PTFeatures/Statistics/**`
- `App/ContentView.swift`
- `Packages/PTFeatures/Tests/PTFeaturesTests/**`
- supporting `PTCore` DAO/model files as needed

**What already exists:**

- Notes and Statistics tabs exist in the main app shell
- notes now resolve real book titles, surface note-type labels/icons, render markdown reader notes, and export/share/copy Markdown/CSV/TXT output
- note color rendering now normalizes both named colors and persisted hex values
- Wave 5A regression coverage now exists for Notes grouping/export/color normalization and Statistics streak/trend/completion/highlight/tile persistence behavior
- statistics now expose current/longest streaks, week/month/year trends, nearly-finished books, random daily highlight with refresh, customizable persisted tiles, and full-history loading so longest-streak/year-view math does not silently truncate to the heatmap window
- statistics now render per-book trend breakdowns for the selected range, including the FR-13.3 "By Book" surface in the Statistics tab
- native PDF and EPUB reader sessions now share a core reading-session recorder that persists reading time back into `tb_reading_time`, so post-migration statistics are no longer fed only by imported Flutter history
- low-level DAOs already expose enough raw data to productize several Wave 5A surfaces without inventing new persistence first

**What is still missing or not yet verified:**

- Wave 5A verification is currently concentrated in view-model/package tests rather than direct screen-level interaction coverage
- FR-12.2 create-path parity is now backed by the freshly re-verified EPUB/PDF reader annotation paths, but still lacks broader end-to-end screen walkthrough coverage

**Exit criteria:**

- Notes and Statistics are no longer placeholder-grade tabs;
- notes resolve real book context, display note types honestly, and export in spec-defined formats;
- statistics expose streak/trend/completion/highlight behavior with fresh verification, including the per-book breakdown required by FR-13.3.

- [x] Finish Notes UX parity for book context, note types, and export.
- [x] Finish Statistics parity for streaks, trends, completion, daily highlight, and per-book breakdown.
- [x] Add and run Wave 5A regression coverage.

### Wave 5B: Settings + Sync + KAIROS / Proactive Systems

**Status:** pending

**FR coverage:** FR-14, FR-15, FR-16, FR-21

**Primary files:**

- `Packages/PTFeatures/Sources/PTFeatures/Settings/**`
- sync-related networking/core files
- TTS-related reader files
- proactive-assistant files if present
- app/platform settings surfaces

**What already exists:**

- Settings tab shell and several persisted preferences exist
- TTS service foundation exists
- low-level WebDAV and migration plumbing exist in parts of the branch

**What is still missing or not yet verified:**

- sync/backup behavior remains largely unproductized beyond lower-level plumbing
- settings depth is still far shallower than the source-of-truth spec
- KAIROS / proactive assistant surface is effectively absent
- TTS still needs product-surface verification rather than only service-level confidence

**Exit criteria:**

- settings depth is no longer shell-only;
- sync/backup flows are user-operable and recoverable;
- proactive assistant work is either implemented or explicitly carved out as still open.

- [ ] Finish Settings parity.
- [ ] Finish Sync/Backup/TTS parity.
- [ ] Finish KAIROS / proactive-assistant parity.
- [ ] Add and run the relevant verification passes.

### Wave 6: Release, Archive, TestFlight

**Status:** blocked until Waves 1-5 are honest

**Purpose:** verify delivery readiness only after feature/spec readiness is real.

**Primary files:**

- `fastlane/Fastfile`
- signing/provisioning configuration
- `project.yml`
- entitlements / extension settings

**Rules for this wave:**

- do not treat archive/upload as evidence of spec completion;
- rerun the lane fresh only after the product waves above are in a defensible state;
- record any Apple-side provisioning blockers as release blockers, not product-completion blockers.

- [ ] Re-run archive/TestFlight only after the feature waves are ready.
- [ ] Record fresh ASC/build/provisioning evidence.
- [ ] Keep release blockers separate from spec-completion blockers.

---

## Immediate Next Execution Order

1. Keep Wave 2 marked in progress, but treat the current reader work honestly as a bridge-shell plus initial AI-panel baseline rather than completed reader parity.
2. Pull Wave 5A forward as an independent productization slice because it can close a real end-user surface without waiting on the larger reader/provider integration backlog.
3. Use the reader-session seam to continue Wave 3 productization for provider/history/thinking/usage/tool/RAG/memory surfaces without advertising reader-aware tools that still lack live context.
4. Keep Wave 4 aligned with the user-facing flows above so share, intents, deep links, and migration validate against the real product path instead of drifting as shell-only work.
5. Execute Wave 1A as an explicit bookshelf follow-up instead of pretending directory scanning was already inside the closed portion of Wave 1.
6. Defer Wave 6 release/TestFlight until the product waves are honestly ready.

---

## Completion Standard

The branch is only ready to be called "Swift-native complete" when all of the following are true:

- the subsystem waves above have no unresolved parity-critical gaps against the 2026-04-03 specs;
- fresh verification exists for the implemented surfaces;
- release/TestFlight passes or is blocked only by clearly documented external Apple-side issues;
- the docs no longer rely on stale or optimistic claims.

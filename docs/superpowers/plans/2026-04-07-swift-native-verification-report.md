# Swift-Native Verification Report

**Date:** 2026-04-10  
**Branch:** `swift-native`  
**Workspace:** `/Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native`

---

## Summary

This report records only **fresh verification run on 2026-04-07, 2026-04-08, 2026-04-09, and 2026-04-10**.

What is now freshly verified:

- the generated Xcode project is current and again exposes an app scheme named `PaperTokReader`;
- host-side SwiftPM tests pass for `PTCore`, `PTNetworking`, `PTUI`, and `PTAIServices`;
- the targeted `PTCore` reading-time subset now proves same-day merge persistence plus native pause/resume/flush session accumulation for Swift-side readers;
- the targeted Papers/Bookshelf regression matrix passes after the PaperTok detail/download improvements and the Bookshelf management/edit work;
- the targeted app-side share/deep-link/import matrix passes after the shared inbox partial-failure hardening and quick-ask route-contract work;
- the full iOS Simulator `PTReaderPackageTests` suite passes on the current dirty branch state;
- the targeted `PTReaderTests/PDFContentBridgeTests` OCR regression subset passes on the current dirty branch state;
- the targeted `PTReaderTests/PDFContentBridgeTests` subset now also proves Unicode-aware case-insensitive PDF search and correct final-page progression metadata for search results;
- the targeted `PTReaderTests/PDFAnnotationBridgeTests` subset passes after the PDF annotation bridge work;
- the targeted `PTReaderTests/EPUBImageScriptBridgeTests` and `PTReaderTests/EPUBNavigatorCoordinatorImageTests` subsets pass after wiring the EPUB image-tap bridge and coordinator callback path;
- the targeted `PTAIServices` tool-runtime honesty subset passes on the current dirty branch state;
- the same targeted `PTCore` reading-time subset and `PTAIServices` runtime-honesty subset also pass again on 2026-04-10 after the closure-design reset, so the new full-spec closure baseline does not rely only on 2026-04-09 evidence for those two critical seams;
- the targeted `PTFeatures` reader/AI regression subset passes after the shared reader-session and in-reader AI panel work;
- the targeted `PTFeatures` reader-controls subset passes after the shared `ReaderControlsViewModel` extraction and the new PDF in-reader search wiring;
- the targeted `PTFeatures` reader annotations + controls subset passes after hardening EPUB annotation draft validation against empty-selection highlight/note saves;
- the targeted `PTFeaturesTests/PDFReaderAnnotationsViewModelTests` subset passes after adding editable drafts for existing PDF annotations and wiring annotation-tap edit entry;
- the targeted `PTFeatures` reader-image subset passes after adding the contextual AI-analysis prompt builder, the image experience controller, and the temporary-file export helper used by the new viewer;
- the targeted `PTFeatures` Notes/Statistics regression subset now passes again on 2026-04-09, so the FR-13.3/native-reading-time Wave 5A delta is no longer only verified at the `PTCore` layer;
- the targeted Flutter migration preflight regression test passes on the current dirty branch state;
- targeted app-level platform tests pass for the current Wave 4 surfaces;
- the `PaperTokReader` iOS Simulator app build passes again on 2026-04-09 after the PDF annotation edit-entry and EPUB image-viewer deltas, using a concrete iPhone 17 Pro (iOS 26.2) simulator destination.

What this report does **not** claim:

- full parity with the 2026-04-03 Swift-native requirements/design specs;
- fresh TestFlight/archive/upload success in this verification cycle;
- closure of the remaining Papers, Bookshelf, Reader, AI, Platform, Migration, MCP, or proactive-assistant spec gaps.

What changed on 2026-04-10:

- the branch now has a dedicated full-spec closure design:
  - `docs/superpowers/specs/2026-04-10-swift-native-full-spec-closure-design.md`
- the branch now has a spec-to-main-to-swift gap matrix:
  - `docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md`
- the branch now has a dirty-delta ledger for current uncommitted work:
  - `docs/superpowers/plans/2026-04-10-swift-native-dirty-delta-ledger.md`
- the branch now has a full-spec closure implementation plan:
  - `docs/superpowers/plans/2026-04-10-swift-native-full-spec-closure-master-plan.md`

---

## 2026-04-10 Addendum

### Fresh Verification

```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'

swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices --filter 'ToolRegistryTests|ToolRuntimeContextTests'
```

Result:

- `PTCore` targeted reading-time subset: passed
  - 7 tests in 2 suites
- `PTAIServices` targeted runtime-honesty subset: passed
  - 28 tests in 2 suites

Interpretation:

- the closure reset on 2026-04-10 does not regress the two seams most critical to honest productization:
  - native reading-time persistence for downstream statistics correctness;
  - tool-runtime honesty for AI product closure.

---

## Issues Found During Verification

Nineteen repo-local problems were found and fixed as part of this cycle:

1. `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/AIChatViewModelExtTests.swift`
   - initial `PTFeaturesPackageTests` failed to compile because a JSON string interpolation used an invalid Swift string literal form;
   - after fixing that compile error, `safeToolCallsExecute()` still failed because the mock provider returned the same tool call every round, which no longer matched the real multi-round tool protocol;
   - fix: use a raw string for JSON output, then make the mock provider support a follow-up assistant round after the tool result.

2. `project.yml`
   - initial app verification failed because the generated project no longer contained a `PaperTokReader` scheme;
   - root cause: explicit scheme declarations existed only for package test schemes, so the app scheme was not being generated;
   - fix: add an explicit `PaperTokReader` scheme back to `project.yml`, then regenerate with `xcodegen generate`.

3. `Tests/AppTests/Platform/AppAIToolContextFactoryTests.swift`
   - initial Wave 4 app-platform verification was noisy because the test instantiated the real `CalendarService()` / `RemindersService()` implementations instead of testing the factory in isolation;
   - fix: replace the EventKit-backed services with lightweight protocol mocks so the test only verifies memory-directory provisioning and dependency injection.

4. `Tests/AppTests/Platform/MigrationLocalizationCatalogTests.swift` and `Tests/AppTests/Platform/ShareExtensionInfoPlistTests.swift`
   - initial targeted app-platform run failed because both tests resolved fixture paths relative to `Tests/` instead of the repo root, so they looked for `Tests/App/...` paths that do not exist;
   - fix: correct the `#filePath` directory walk-up by one level in both tests.

5. `App/Platform/Migration/FlutterMigrationService.swift`
   - the legacy DB preflight still rejected any database whose `PRAGMA user_version` was not exactly the expected schema version, which was stricter than the migration requirement for older supported Flutter databases;
   - fix: accept legacy databases whose schema version is less than or equal to the expected supported version, while still rejecting newer unsupported schemas, then verify it with a targeted `FlutterMigrationServiceTests` run.

6. `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookImportService.swift` and `Packages/PTReader/Sources/PTReader/EPUB/EPUBPublicationOpener.swift`
   - EPUB import still persisted books without extracted cover art, so the Bookshelf pipeline missed a documented parity behavior;
   - fix: add a red/green regression test using a real EPUB fixture, extract metadata + cover art through Readium, persist the cover into `Covers/`, and re-run the targeted Papers/Bookshelf regression matrix.

7. `Packages/PTNetworking/Sources/PTNetworking/HTTP/NetworkClient.swift`, `Packages/PTNetworking/Sources/PTNetworking/PaperTok/PaperTokModels.swift`, `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadWorker.swift`, `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadButton.swift`, and `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift`
   - the live `papertok.ai` detail payload shape had drifted beyond the older local model assumptions, and API timestamps with fractional seconds but no timezone were not reliably decoded;
   - fix: expand `PaperTokDetail` to the live payload actually returned now, add language-aware explanation/dialogue helpers, add resilient timestamp decoding, and switch paper download/import to a worker that reports real byte progress plus an importing phase and duplicate-import mapping.

8. `App/ContentView.swift`, `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookshelfViewModel.swift`, and `Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/BookshelfViewModelTests.swift`
   - Bookshelf still left tag/group CRUD and explicit book editing mostly buried below the view-model layer, which did not meet the FR-03 user-surface requirement even though the backend primitives existed;
   - fix: add a persisted book metadata edit flow, a tag filter/management sheet, a group management sheet for create/rename/delete/dissolve, and a new regression test that proves metadata edits persist.

9. `App/Platform/Share/SharedInboxImportProcessor.swift`, `App/ContentView.swift`, and `Tests/AppTests/Platform/SharedInboxImportProcessorTests.swift`
   - shared inbox book import still retried already-imported files after a partial failure because event manifests were only consumed on full success;
   - fix: add a dedicated shared inbox import processor that consumes fully successful events, retains only failed book items for retry, discards missing files, and verify it with fresh app-level regression tests.

10. `Packages/PTCore/Sources/PTCore/Config/AppConfig.swift`, `App/Platform/Share/SharedInbox.swift`, `App/Platform/Share/ShareHandler.swift`, `App/Extensions/ShareExtension/ShareViewController.swift`, `App/Platform/DeepLink/DeepLinkRouter.swift`, `App/Platform/DeepLink/DeepLinkHandler.swift`, `App/ContentView.swift`, `Tests/AppTests/Platform/ShareHandlerTests.swift`, and `Tests/AppTests/Platform/DeepLinkRouterTests.swift`
   - the share contract still collapsed `shortcuts/ask` into the AI chat route and did not persist the user's requested share mode, which blocked honest progress toward FR-16.5 / FR-17.3;
   - fix: add a persisted `ShareDefaultRoute` contract, extend share events with requested-route/fallback metadata, make `ask` a first-class `SharedInboxRoute`, emit `paperreader://shortcuts/ask?share_token=...` from the extension, and verify it with fresh share/deep-link regression tests.

11. `Packages/PTAIServices/Sources/PTAIServices/Tools/**`, `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`, `App/Platform/AI/AppAIToolContextFactory.swift`, and the reader/tool runtime tests
   - reader-aware AI tools still had several honesty gaps: annotation tools could target stale book IDs, some book-content tools did not require a live reader session, and `current_chapter_content` could still be advertised outside a valid live-chapter context;
   - fix: make tool context use atomic reader-session snapshots, route annotation tools through `activeBookId`, switch reader-content tools to `activeReaderSession()`, fetch current-reading metadata directly from the active book ID, and tighten runtime-gated tool exposure so the model only sees runnable tools.

12. `Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift` and `Packages/PTReader/Tests/PTReaderTests/PDF/PDFContentBridgeTests.swift`
   - scanned PDFs still lacked a fully verified OCR fallback path for full-text extraction, chapter extraction, and search;
   - fix: wire OCR fallback through the bridge's extraction and search paths, then add fresh targeted regression coverage for OCR-backed full text, chapter text, and search matches.

13. `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderAIPanelHost.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift`, `App/ContentView.swift`, and `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/ReaderAIPanelPreferencesStoreTests.swift`
   - the branch still lacked a real in-reader AI panel surface even though FR-08 requires a docked/sheet reader experience, and a fresh app build also surfaced a Swift 6 async warning in `ContentView.swift`;
   - fix: add a reusable reader AI panel host with per-book width/side persistence, compact-sheet handling, and minimized background-generation bar, wire the shared AI chat view model into both EPUB and PDF reader flows, add regression tests for panel preference persistence/clamping, and fix the async warning by awaiting the imported error read.

14. `Packages/PTCore/Sources/PTCore/Database/ReadingTimeDAO.swift`, `Packages/PTFeatures/Sources/PTFeatures/Statistics/StatisticsViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Statistics/StatisticsSupport.swift`, and `Packages/PTFeatures/Tests/PTFeaturesTests/Statistics/StatisticsViewModelTests.swift`
   - the new Wave 5A Statistics regression work exposed two correctness issues: date keys still mixed injected calendars with a default-timezone formatter, and statistics loaded only the last 91 days of data, which silently under-reported longest streaks and year-view trends outside the heatmap window;
   - fix: bind Statistics date-key formatting to the injected calendar/timezone, load full-history daily reading aggregates for analytics math while keeping the heatmap as a recent-window presentation concern, and add fresh regression coverage for timezone-stable streak/trend math plus full-history longest-streak/year-view behavior.

15. `Packages/PTCore/Sources/PTCore/Database/ReadingTimeDAO.swift`, `Packages/PTCore/Sources/PTCore/Database/ReadingSessionRecorder.swift`, `Packages/PTCore/Tests/PTCoreTests/Database/ReadingTimeDAOTests.swift`, `Packages/PTCore/Tests/PTCoreTests/Database/ReadingSessionRecorderTests.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift`, `App/ContentView.swift`, and `Packages/PTFeatures/Sources/PTFeatures/Statistics/StatisticsViewModel.swift`
   - the latest Wave 5A audit showed that the new per-book breakdown still was not fed by native Swift reading sessions because PDF/EPUB readers never wrote reading-time deltas back into `tb_reading_time`, and the visible trend labels still ignored the injected statistics timezone even after the earlier date-key fix;
   - fix: add a core `ReadingSessionRecorder` plus a same-day merging `ReadingTimeDAO.addReadingTime(...)` path, wire PDF and EPUB readers to resume/pause/flush reading sessions across load/disappear/scene-phase boundaries, and bind the visible statistics trend label formatters to the injected calendar timezone;
   - fresh verification: `swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'` passes; the matching iOS `PTFeatures` / app reruns are not yet included in this report.

16. `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderControlsViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderControlsViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderControlsViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift`, and the reader-controls tests
   - the branch still exposed visible TOC/search only for EPUB, while PDF full-text search remained backend-only even though `PDFContentBridge` already provided real extraction and search APIs;
   - fix: extract a shared `ReaderControlsViewModel`, keep EPUB on the same seam, add a PDF alias plus UI search sheet/toolbar entry/result jump path, and expose the live PDF content bridge from `ReaderViewModel` so the controls layer can consume the existing bridge instead of reparsing documents;
   - fresh verification: `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test` passes, and `xcodebuild ... -scheme PaperTokReader ... -destination 'id=725F8480-FA37-431F-B369-84059728E299' build` passes on 2026-04-08.

17. `Packages/PTReader/Sources/PTReader/PDF/PDFContentBridge.swift`, `Packages/PTReader/Tests/PTReaderTests/PDF/PDFContentBridgeTests.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderAnnotationsViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/EPUBReaderAnnotationEditorView.swift`, and `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/EPUBReaderAnnotationsViewModelTests.swift`
   - the Wave 2 audit found two still-open reader correctness gaps: `PDFContentBridge.searchContent(...)` lowercased whole pages and reused those indices against the original string, which missed Unicode case-folding cases and under-reported end-of-book progression, and EPUB annotation creation still allowed empty-selection bookmark drafts to be switched to highlight/note and persisted as empty-content notes;
   - fix: search the original PDF page text with Unicode-aware case/diacritic-insensitive matching, derive snippets from original-string indices, report the final page as `progression = 1.0`, reject empty-selection highlight/note creates in `EPUBReaderAnnotationsViewModel`, and disable the annotation editor save button for that invalid draft state;
   - fresh verification: `xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/PDFContentBridgeTests test` passes with 9 tests / 1 suite, and `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/EPUBReaderAnnotationsViewModelTests -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test` passes with 21 tests / 4 suites.

18. `Packages/PTReader/Sources/PTReader/PDF/PDFAnnotationBridge.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderAnnotationsViewModel.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/PDFReaderView.swift`, `Packages/PTReader/Tests/PTReaderTests/PDF/PDFAnnotationBridgeTests.swift`, and `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/PDFReaderAnnotationsViewModelTests.swift`
   - the Wave 2 reader audit still found one major product gap after annotation create/bookmark/render landed: users could not tap an existing rendered PDF annotation to reopen the existing note in the editor for update or delete, so PDF annotation parity was still short of the FR-05.4 user surface even though the lower-level persistence existed;
   - fix: add editable-draft lookup for persisted PDF notes, tag rendered PDF annotations with their note IDs, detect annotation taps in both iOS and macOS wrappers, suppress the stale selection callback on edit-entry taps, and route the tapped note back into the existing annotation editor;
   - fresh verification: `xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/PDFAnnotationBridgeTests test` passes with 2 tests / 1 suite, `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/PDFReaderAnnotationsViewModelTests test` passes with 4 tests / 1 suite, and `xcodebuild ... -scheme PaperTokReader ... -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' build` passes on 2026-04-09.

19. `Packages/PTReader/Sources/PTReader/Common/ReaderImageAsset.swift`, `Packages/PTReader/Sources/PTReader/EPUB/EPUBImageScriptBridge.swift`, `Packages/PTReader/Sources/PTReader/EPUB/EPUBNavigatorCoordinator.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageAnalysisPrompt.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageExperienceController.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageFileStore.swift`, `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderImageViewer.swift`, and `App/ContentView.swift`
   - the Wave 2 audit still found FR-04.6 completely absent on the EPUB side: tapping inline images did nothing, there was no full-screen viewer, and the reader AI panel had no direct image-analysis handoff from in-book images;
   - fix: inject a small Readium user script that captures tapped `<img>` elements and posts a data URL back to native code, decode that into a reusable `ReaderImageAsset`, route it through the navigator coordinator into a reader image-experience controller, present a full-screen viewer with zoom/pan/double-tap fit plus share/export support, and hand the tapped image into the existing reader AI panel using a contextual analysis prompt;
   - fresh verification: `xcodebuild ... -scheme PTReaderPackageTests ... -only-testing:PTReaderTests/EPUBImageScriptBridgeTests -only-testing:PTReaderTests/EPUBNavigatorCoordinatorImageTests test` passes with 3 tests / 2 suites, `xcodebuild ... -scheme PTFeaturesPackageTests ... -only-testing:PTFeaturesTests/ReaderImageAnalysisPromptTests -only-testing:PTFeaturesTests/ReaderImageExperienceControllerTests -only-testing:PTFeaturesTests/ReaderImageFileStoreTests test` passes with 5 tests / 3 suites, and `xcodebuild ... -scheme PaperTokReader ... -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' build` passes on 2026-04-09.

---

## Commands and Results

### Project Generation

```bash
xcodegen generate
```

Result: success.

### Scheme Inventory

```bash
xcodebuild -list -project PaperTokReader.xcodeproj
```

Result: success.  
Relevant schemes now include:

- `PaperTokReader`
- `PTFeaturesPackageTests`
- `PTReaderPackageTests`

### Host-Side SwiftPM Tests

```bash
swift test --package-path Packages/PTCore
swift test --package-path Packages/PTNetworking
swift test --package-path Packages/PTUI
swift test --package-path Packages/PTAIServices
swift test --package-path Packages/PTAIServices --filter 'ToolRegistryTests|ToolRuntimeContextTests'
```

Result:

- `PTCore`: passed
  - Swift Testing: 49 tests in 17 suites
- `PTCore` targeted reading-time subset: passed
  - `ReadingTimeDAOTests` + `ReadingSessionRecorderTests`: 7 tests in 2 suites
- `PTNetworking`: passed
  - Swift Testing: 29 tests in 6 suites
- `PTUI`: passed
  - Swift Testing: 5 tests in 2 suites
- `PTAIServices`: passed
  - XCTest target: 24 tests
  - Swift Testing: 46 tests in 10 suites
  - includes fresh `ToolRegistryTests` and `SpawnSubAgentToolTests`
- `PTAIServices` targeted runtime-honesty subset: passed
  - `ToolRegistryTests` + `ToolRuntimeContextTests`: 28 tests

### 2026-04-08 Wave 5A Delta Verification

```bash
swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'

swift test --package-path Packages/PTFeatures --filter StatisticsViewModelTests

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -sdk iphonesimulator26.4 -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/papertok-reader-wave5a-generic CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build-for-testing

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReader -sdk iphoneos26.4 -destination 'generic/platform=iOS' -derivedDataPath /tmp/papertok-reader-app-generic-ios CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build

xcodebuild -downloadPlatform iOS
```

Result:

- `swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'`: passed
  - 7 tests in 2 suites
- `swift test --package-path Packages/PTFeatures --filter StatisticsViewModelTests`: failed before executing tests
  - existing Readium / SwiftSoup / ReadiumZIPFoundation macOS deployment-target incompatibilities in the package graph
- `xcodebuild ... -scheme PTFeaturesPackageTests ... build-for-testing`: failed
  - no eligible `generic/platform=iOS Simulator` destination because the local Xcode 26.4 installation reports `iOS 26.4 is not installed`
- `xcodebuild ... -scheme PaperTokReader ... build`: failed
  - no eligible `generic/platform=iOS` destination for the same `iOS 26.4 is not installed` platform mismatch
- `xcodebuild -downloadPlatform iOS`: did not self-heal the blocker
  - returned `No matching downloadable found for platform: iOS`

Historical note:

- the generic 26.4 destination failure above should not be treated as the current blocker state forever; later local destination checks no longer support claiming that iOS 26.4 availability is the active reason Wave 5A iOS reruns remain incomplete

### iOS Simulator Package Tests

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'id=03282D78-A8C3-4996-81F8-A5DA44B6784E' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-ptfeatures-tests-wave1b CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/PapersViewModelTests -only-testing:PTFeaturesTests/PaperDetailDataLoaderTests -only-testing:PTFeaturesTests/PaperDownloadPlanTests -only-testing:PTFeaturesTests/PaperDownloadWorkerTests -only-testing:PTFeaturesTests/BookImportServiceEPUBTests -only-testing:PTFeaturesTests/BookshelfViewModelTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTReaderPackageTests -destination 'id=03282D78-A8C3-4996-81F8-A5DA44B6784E' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-ptreader-tests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTReaderPackageTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-ptreader-pdf-ocr CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTReaderTests/PDFContentBridgeTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-ptfeatures-reader-ai-regression CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/AIChatViewModelExtTests -only-testing:PTFeaturesTests/ReaderViewModelTests -only-testing:PTFeaturesTests/ReaderAIPanelPreferencesStoreTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-wave5a-green2 CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/NotesViewModelTests -only-testing:PTFeaturesTests/StatisticsViewModelTests test
```

Result:

- `PTFeaturesPackageTests`: passed
  - targeted Papers/Bookshelf regression matrix: 29 tests in 6 suites
  - xcresult: `Test-PTFeaturesPackageTests-2026.04.07_17-13-42--0400.xcresult`
- `PTReaderPackageTests`: passed
  - 37 tests in 9 suites
  - xcresult: `Test-PTReaderPackageTests-2026.04.07_16-17-55--0400.xcresult`
- targeted `PTReaderTests/PDFContentBridgeTests`: passed
  - 9 tests in 1 suite
- targeted reader/AI regression matrix: passed
  - `AIChatViewModelExtTests` + `ReaderViewModelTests` + `ReaderAIPanelPreferencesStoreTests`
  - 25 tests in 3 suites
- targeted `PTReaderTests/PDFAnnotationBridgeTests`: passed
  - 2 tests in 1 suite
- targeted Notes/Statistics regression matrix: passed
  - `NotesViewModelTests` + `StatisticsViewModelTests`
  - 7 tests in 2 suites

### 2026-04-09 Wave 5A / PDF Annotation Delta Verification

```bash
swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTReaderPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTReaderTests/PDFAnnotationBridgeTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/PDFReaderAnnotationsViewModelTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/NotesViewModelTests -only-testing:PTFeaturesTests/StatisticsViewModelTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReader -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
```

Result:

- `swift test --package-path Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'`: passed
  - 7 tests in 2 suites
- targeted `PTReaderTests/PDFAnnotationBridgeTests`: passed
  - 2 tests in 1 suite
- targeted `PTFeaturesTests/PDFReaderAnnotationsViewModelTests`: passed
  - 4 tests in 1 suite
- targeted `NotesViewModelTests` + `StatisticsViewModelTests`: passed
  - 8 tests in 2 suites
- app target simulator build on `iPhone 17 Pro (iOS 26.2)`: passed
  - only unrelated `IntentsDonationService.swift` `var`→`let` warnings remained

### 2026-04-09 Wave 2 EPUB Image Viewer Delta Verification

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTReaderPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTReaderTests/EPUBImageScriptBridgeTests -only-testing:PTReaderTests/EPUBNavigatorCoordinatorImageTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/ReaderImageAnalysisPromptTests -only-testing:PTFeaturesTests/ReaderImageExperienceControllerTests -only-testing:PTFeaturesTests/ReaderImageFileStoreTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReader -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
```

Result:

- targeted `PTReaderTests/EPUBImageScriptBridgeTests` + `PTReaderTests/EPUBNavigatorCoordinatorImageTests`: passed
  - 3 tests in 2 suites
- targeted `PTFeaturesTests/ReaderImageAnalysisPromptTests` + `PTFeaturesTests/ReaderImageExperienceControllerTests` + `PTFeaturesTests/ReaderImageFileStoreTests`: passed
  - 5 tests in 3 suites
- app target simulator build on `iPhone 17 Pro (iOS 26.2)`: passed
  - the EPUB image-viewer delta compiles cleanly into the main app target

### iOS Simulator Targeted Migration Tests

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'id=03282D78-A8C3-4996-81F8-A5DA44B6784E' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-app-tests-red CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PaperTokReaderTests/FlutterMigrationServiceTests test
```

Result:

- `FlutterMigrationServiceTests`: passed
  - 3 tests in 1 suite
  - xcresult: `Test-PaperTokReaderAppTests-2026.04.07_16-02-55--0400.xcresult`

### iOS Simulator App Build

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReader -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/papertok-reader-app-build CODE_SIGNING_ALLOWED=NO build
```

Result: `** BUILD SUCCEEDED **`

Notable note:

- App Intents metadata extraction now runs for the app target and completes successfully.
- a fresh rerun after the reader AI panel work also succeeded after fixing a Swift 6 async warning in `ContentView.swift`.

### 2026-04-08 Wave 2 Reader Controls Delta Verification

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'id=725F8480-FA37-431F-B369-84059728E299' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-reader-controls-green-20260408 CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReader -destination 'id=725F8480-FA37-431F-B369-84059728E299' -derivedDataPath /tmp/papertok-reader-app-reader-controls-20260408 CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
```

Result:

- targeted reader-controls regression matrix: passed
  - `EPUBReaderControlsViewModelTests`
  - `PDFReaderControlsViewModelTests`
  - `ReaderViewModelTests`
- app target simulator build on `iPhone 17 Pro (iOS 26.2)`: passed

### 2026-04-08 Wave 2 Reader Correctness Delta Verification

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTReaderPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-epub-search-progression-full CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTReaderTests/PDFContentBridgeTests test

xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-reader-controls-green-20260408 CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PTFeaturesTests/EPUBReaderAnnotationsViewModelTests -only-testing:PTFeaturesTests/EPUBReaderControlsViewModelTests -only-testing:PTFeaturesTests/PDFReaderControlsViewModelTests -only-testing:PTFeaturesTests/ReaderViewModelTests test
```

Result:

- targeted `PTReaderTests/PDFContentBridgeTests`: passed
  - 9 tests in 1 suite
  - newly covers Unicode-aware case-insensitive matching and final-page `progression`
  - xcresult: `Test-PTReaderPackageTests-2026.04.08_23-54-00--0400.xcresult`
- targeted `PTFeatures` reader annotations + controls regression matrix: passed
  - `EPUBReaderAnnotationsViewModelTests`
  - `EPUBReaderControlsViewModelTests`
  - `PDFReaderControlsViewModelTests`
  - `ReaderViewModelTests`
  - 21 tests in 4 suites
  - xcresult: `Test-PTFeaturesPackageTests-2026.04.08_23-59-12--0400.xcresult`
  - only unrelated `IntentsDonationService.swift` `var`→`let` warnings remained

### iOS Simulator App Platform Tests

```bash
xcodebuild -disableAutomaticPackageResolution -project PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'id=03282D78-A8C3-4996-81F8-A5DA44B6784E' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -derivedDataPath /tmp/papertok-reader-app-tests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -only-testing:PaperTokReaderTests/AppAIToolContextFactoryTests -only-testing:PaperTokReaderTests/DeepLinkRouterTests -only-testing:PaperTokReaderTests/FlutterMigrationPlannerTests -only-testing:PaperTokReaderTests/FlutterMigrationServiceTests -only-testing:PaperTokReaderTests/MigrationLocalizationCatalogTests -only-testing:PaperTokReaderTests/PendingAIRequestStoreTests -only-testing:PaperTokReaderTests/ShareExtensionInfoPlistTests -only-testing:PaperTokReaderTests/SharedInboxTests test
```

Result:

- passed
  - Swift Testing: 12 tests in 8 suites
  - xcresult: `Test-PaperTokReaderAppTests-2026.04.07_15-39-57--0400.xcresult`

### iOS Simulator Share / Import Routing Tests

```bash
xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:PaperTokReaderTests/DeepLinkRouterTests -only-testing:PaperTokReaderTests/SharedInboxTests -only-testing:PaperTokReaderTests/ShareHandlerTests -only-testing:PaperTokReaderTests/SharedInboxImportProcessorTests -only-testing:PaperTokReaderTests/PendingAIRequestStoreTests test
```

Result:

- passed
  - targeted deep-link/share/import regression suites all succeeded, including the new `ask` route contract coverage
  - xcresult: `Test-PaperTokReaderAppTests-2026.04.07_21-04-02--0400.xcresult`

---

## Currently Verified Surface

As of 2026-04-07 and 2026-04-08, the following statements are backed by fresh command output:

- the repo can regenerate its Xcode project;
- the repo has a usable app scheme for the main target again;
- the core host-side packages (`PTCore`, `PTNetworking`, `PTUI`, `PTAIServices`) test cleanly;
- the targeted Papers/Bookshelf regression surface now covers `PapersViewModel`, `PaperDetailDataLoader`, `PaperDownloadPlan`, `PaperDownloadWorker`, `BookImportServiceEPUB`, and `BookshelfViewModel` including persisted metadata editing, and passes;
- app-level deep-link/share/import coverage now includes `DeepLinkRouter`, `SharedInbox`, `ShareHandler`, `SharedInboxImportProcessor`, and `PendingAIRequestStore`, and passes;
- the full `PTReaderPackageTests` suite is exercised through Xcode and passes;
- targeted `PDFContentBridgeTests` prove OCR-backed full text, chapter text, and search behavior;
- targeted `ToolRegistryTests` / `ToolRuntimeContextTests` prove the reader/tool runtime honesty fixes on the current branch state;
- targeted `AIChatViewModelExtTests` / `ReaderViewModelTests` / `ReaderAIPanelPreferencesStoreTests` prove the shared reader-session and in-reader AI panel baseline on the current branch state;
- targeted `EPUBReaderControlsViewModelTests` / `PDFReaderControlsViewModelTests` / `ReaderViewModelTests` prove the shared reader-controls seam plus visible EPUB/PDF search wiring on the current branch state;
- targeted `NotesViewModelTests` / `StatisticsViewModelTests` now prove the Wave 5A Notes export/grouping/color work plus the Statistics streak/trend/completion/highlight/tile/history-accuracy behavior on a fresh 2026-04-09 iOS run;
- targeted `ReadingTimeDAOTests` / `ReadingSessionRecorderTests` prove the new core-layer same-day merge persistence and native Swift reading-session accumulation behavior and were rerun again on 2026-04-09;
- targeted `PDFAnnotationBridgeTests` / `PDFReaderAnnotationsViewModelTests` prove the PDF annotation bridge plus tapped-annotation edit/delete entry path on the current branch state;
- targeted `EPUBImageScriptBridgeTests` / `EPUBNavigatorCoordinatorImageTests` / `ReaderImageAnalysisPromptTests` / `ReaderImageExperienceControllerTests` / `ReaderImageFileStoreTests` prove the new EPUB image-viewer bridge plus AI/export handoff behavior on the current branch state;
- legacy Flutter schema preflight compatibility is covered by a targeted app-test and passes;
- app-level platform tests now pass for `AppAIToolContextFactory`, `DeepLinkRouter`, `FlutterMigrationPlanner`, `FlutterMigrationService`, `MigrationLocalizationCatalog`, `PendingAIRequestStore`, `ShareExtensionInfoPlist`, and `SharedInbox`;
- the `PaperTokReader` app target now has a fresh 2026-04-09 simulator build rerun on a concrete iPhone 17 Pro (iOS 26.2) destination.

---

## Residual Gaps and Unverified Surfaces

These areas remain outside the scope of the fresh verification above:

- **Spec completeness**
  - passing builds/tests do not prove FR-02/03/04/05/06/07/08/09/10/11/12/13/14/15/16/17/19/20/21/22/23 are complete;
  - see the rewritten master plan for the remaining subsystem gaps.

- **Release/TestFlight**
  - no archive or TestFlight upload was rerun in this verification cycle;
  - the previous report's provisioning blocker for `ShareExtension` App Groups is only a **last-known** blocker until re-verified fresh.

- **Manual feature validation**
  - no manual simulator walkthrough was performed in this cycle for Papers feed UX, the new Bookshelf management sheets, reader annotations/search/settings, share extension flows, or migration flows.

- **Latest Wave 5A / Wave 2 deltas**
  - the newest PTFeatures/app-side evidence for Wave 5A, PDF annotation parity, and the EPUB image-viewer path is now present, but this report still does not claim broader manual screen-level walkthrough coverage for Notes/Statistics, PDF annotation editing, or the new image-viewer UX;
  - the remaining reader-side parity gaps are now concentrated in deeper PDF settings parity, TTS product surfaces, and broader FR-08 AI panel product completeness rather than the previously open PDF annotation edit-entry or EPUB image-viewer gaps.

---

## Bottom Line

`swift-native` is now freshly verified as **buildable and testable on its currently implemented surfaces**.

`swift-native` is **not** yet claimable as spec-complete. The branch still needs subsystem-wave completion against the 2026-04-03 requirements/design docs before release/TestFlight can honestly be treated as the final gate.

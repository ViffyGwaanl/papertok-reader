# Swift-Native Closure Master Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every remaining non-MVP gap on `swift-native` so the branch satisfies the docs-defined completion standard: integrated AI chat, working tool runtime, EPUB and Papers end-to-end flows, real Flutter migration, platform integration, passing verification, and a fresh TestFlight upload.

**Architecture:** Execute four isolated workstreams in waves. Wave 1 fixes runtime wiring and end-to-end blockers that invalidate the product contract. Wave 2 closes platform and migration gaps that depend on runtime wiring. Wave 3 resolves verification/release issues and updates docs from fresh evidence. File ownership is split to keep subagent work disjoint and merge-safe.

**Tech Stack:** Swift 5.9+, SwiftUI, GRDB.swift, Readium 3.x, PDFKit, EventKit, AppIntents, XcodeGen, Fastlane, Swift Testing, XCTest

---

## Why This Plan Replaces 2026-04-06

The prior master execution plan assumed Phases 5b/7/8/9/10/11/12 were still mostly unimplemented. That is no longer true. Current reality is mixed:

- code exists for most of those phases;
- several critical flows are only scaffolded or partially wired;
- docs overstate missing work in some areas and understate risk in others;
- successful completion now depends on integration and verification, not only file creation.

This plan is therefore a closure plan, not a greenfield implementation plan.

## File Ownership Map

### Workstream A: AI Runtime + Tool Runtime

**Primary files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ProviderPickerSheet.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolContext.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolRegistry.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Calendar/CalendarTools.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Reminders/RemindersTools.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Agent/SpawnSubAgentTool.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Agent/ShortcutsRunTool.swift`
- Add or modify tests under: `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/`
- Add or modify tests under: `Packages/PTAIServices/Tests/PTAIServicesTests/Tools/`

### Workstream B: Reader + Papers End-to-End

**Primary files:**
- Modify: `App/ContentView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookImportService.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadButton.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/PapersView.swift`
- Modify: `Packages/PTReader/Package.swift`
- Modify: `Packages/PTFeatures/Package.swift`
- Add or modify tests under: `Packages/PTFeatures/Tests/PTFeaturesTests/Papers/`
- Add or modify tests under: `Packages/PTReader/Tests/PTReaderTests/EPUB/`

### Workstream C: Platform Integration + Migration

**Primary files:**
- Modify: `App/PaperTokReaderApp.swift`
- Modify: `App/Platform/DeepLink/DeepLinkHandler.swift`
- Modify: `App/Platform/DeepLink/DeepLinkRouter.swift`
- Modify: `App/Platform/Intents/AskAIIntent.swift`
- Modify: `App/Platform/Intents/OpenBookIntent.swift`
- Modify: `App/Platform/Intents/IntentsDonationService.swift`
- Modify: `App/Platform/Migration/FlutterMigrationService.swift`
- Modify: `App/Platform/Migration/MigrationProgressView.swift`
- Modify: `App/Extensions/ShareExtension/ShareViewController.swift`
- Modify: `App/Extensions/ShareExtension/ShareHandler.swift`
- Modify: `project.yml`
- Modify: `App/Resources/Localizable.xcstrings`
- Add tests where feasible under package targets; validate app flows via build/runtime checks

### Workstream D: Verification + Release + Docs

**Primary files:**
- Modify: `fastlane/Fastfile`
- Modify: `project.yml`
- Modify: `docs/superpowers/plans/2026-04-06-progress-tracker.md`
- Modify: `docs/superpowers/plans/2026-04-06-master-execution-plan.md`
- Add: `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

---

## Dependency Order

1. Workstream A must land before the AI chat/product contract can be considered real.
2. Workstream B can start immediately, but final reader navigation checks depend on app-level routing in Workstream C.
3. Workstream C depends on the routing/runtime decisions from Workstream A and import behavior from Workstream B.
4. Workstream D runs throughout for evidence gathering, then performs the final verification and release pass after A/B/C are green.

---

### Task 1: Re-baseline docs and freeze the execution contract

**Files:**
- Create: `docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`
- Modify: `docs/superpowers/plans/2026-04-06-master-execution-plan.md`

- [ ] **Step 1: Mark the old plan as superseded**

Run: `rg -n "Goal:|Success Criteria" docs/superpowers/plans/2026-04-06-master-execution-plan.md`
Expected: existing stale plan sections are present and can be annotated.

- [ ] **Step 2: Save the new closure plan**

Run: `test -f docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`
Expected: exit 0 after writing this file.

- [ ] **Step 3: Verify the new plan is the only current execution source**

Run: `sed -n '1,80p' docs/superpowers/plans/2026-04-06-master-execution-plan.md && echo '---' && sed -n '1,80p' docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`
Expected: old plan points to the new plan; new plan contains the active execution header.

### Task 2: Finish AI chat runtime, provider wiring, and tool execution context

**Files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ProviderPickerSheet.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolContext.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/ToolRegistry.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Calendar/CalendarTools.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Reminders/RemindersTools.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Agent/SpawnSubAgentTool.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Tools/Agent/ShortcutsRunTool.swift`
- Test: `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/`
- Test: `Packages/PTAIServices/Tests/PTAIServicesTests/Tools/`

- [ ] **Step 1: Write failing AI chat integration tests**

Run: `swift test --package-path Packages/PTFeatures --filter AIChat`
Expected: red tests or package-resolution failure that isolates what must be fixed before runtime integration is complete.

- [ ] **Step 2: Add runtime dependencies to AIChatViewModel**

Implement:
- provider registry / provider options source;
- selected provider/model defaults;
- send pipeline that builds `ChatRequest`;
- streaming consumption for text/thinking/tool-call chunks;
- tool approval handoff for dangerous tools;
- tool orchestrator execution using a real `ToolContext`.

- [ ] **Step 3: Fix tool definitions and context injection**

Implement:
- `ToolRegistry.allDefinitions()` emitting parameter schema from each tool type;
- calendar/reminders tools reading services from `context` instead of unused stored properties;
- agent tool behavior returning real dispatch results or explicit unsupported errors only when runtime prerequisites are absent.

- [ ] **Step 4: Wire provider picker and send flow in SwiftUI**

Run: `rg -n "providers: \\[\\]|deferred to Phase|Phase 12" Packages/PTFeatures/Sources/PTFeatures/AIChat`
Expected: no runtime-defer comments remain in live AI chat path after edits.

- [ ] **Step 5: Verify the runtime with package tests**

Run: `swift test --package-path Packages/PTAIServices`
Expected: exit 0.

- [ ] **Step 6: Verify the feature layer**

Run: `swift test --package-path Packages/PTFeatures`
Expected: exit 0 once the Readium package-resolution issue is addressed in Task 3.

### Task 3: Make EPUB and Papers flows truly end-to-end

**Files:**
- Modify: `App/ContentView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/BookImportService.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Reader/ReaderViewModel.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDetailView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/PaperDownloadButton.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/PapersView.swift`
- Modify: `Packages/PTReader/Package.swift`
- Modify: `Packages/PTFeatures/Package.swift`
- Test: `Packages/PTReader/Tests/PTReaderTests/EPUB/`
- Test: `Packages/PTFeatures/Tests/PTFeaturesTests/Papers/`

- [ ] **Step 1: Write failing tests for EPUB import/open and Papers import completion**

Run: `swift test --package-path Packages/PTReader --filter EPUB`
Expected: current package-resolution failure is reproduced and documented before the fix.

- [ ] **Step 2: Fix standalone package resolution for Readium-dependent packages**

Implement:
- platform/dependency configuration so `PTReader` and `PTFeatures` are testable under SwiftPM on the current machine;
- no regression to the working Xcode project build.

- [ ] **Step 3: Connect bookshelf importer and navigation to EPUB**

Implement:
- `.epub` support in file importer;
- reader selection by file type;
- `ReaderViewModel` / app routing updates needed for EPUB open flow.

- [ ] **Step 4: Complete Papers download-to-library import**

Implement:
- downloaded paper file persistence;
- import into bookshelf via existing import service or a shared import path;
- UI copy that reflects the true state instead of claiming “Imported” before import occurs.

- [ ] **Step 5: Verify package tests**

Run: `swift test --package-path Packages/PTReader`
Expected: exit 0.

- [ ] **Step 6: Verify dependent feature tests**

Run: `swift test --package-path Packages/PTFeatures`
Expected: exit 0.

### Task 4: Complete deep links, intents, migration, and share extension wiring

**Files:**
- Modify: `App/PaperTokReaderApp.swift`
- Modify: `App/ContentView.swift`
- Modify: `App/Platform/DeepLink/DeepLinkHandler.swift`
- Modify: `App/Platform/DeepLink/DeepLinkRouter.swift`
- Modify: `App/Platform/Intents/AskAIIntent.swift`
- Modify: `App/Platform/Intents/OpenBookIntent.swift`
- Modify: `App/Platform/Intents/IntentsDonationService.swift`
- Modify: `App/Platform/Migration/FlutterMigrationService.swift`
- Modify: `App/Platform/Migration/MigrationProgressView.swift`
- Modify: `App/Extensions/ShareExtension/ShareViewController.swift`
- Modify: `App/Extensions/ShareExtension/ShareHandler.swift`
- Modify: `project.yml`

- [ ] **Step 1: Reproduce current integration gaps from code evidence**

Run: `rg -n "handleDeepLinks|placeholder|return FlutterData\\(booksSQL: \\[\\]" App project.yml`
Expected: current deep-link and migration gaps are confirmed from source before edits.

- [ ] **Step 2: Wire deep-link consumption into the live tab container**

Implement:
- active consumption of `DeepLinkRouter.pendingDestination`;
- tab switching and import presentation;
- `AskAIIntent` / `OpenBookIntent` routes reaching visible UI state.

- [ ] **Step 3: Replace Flutter migration no-ops with real import logic**

Implement:
- read-only open of the Flutter SQLite database;
- row mapping for books, notes, reading time;
- safe idempotency / duplicate handling;
- “complete” flag only after real import succeeds.

- [ ] **Step 4: Convert share extension from excluded placeholder to real target-owned flow**

Implement:
- XcodeGen target/source configuration for the extension;
- App Group-safe shared file handoff;
- main-app import URL or shared-inbox pickup path that matches the live import flow.

- [ ] **Step 5: Verify build-level integration**

Run: `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReader -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: exit 0.

### Task 5: Finalize localization, docs truthfulness, and release automation

**Files:**
- Modify: `App/Resources/Localizable.xcstrings`
- Modify: `docs/superpowers/plans/2026-04-06-progress-tracker.md`
- Modify: `fastlane/Fastfile`
- Modify: `project.yml`
- Add: `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

- [ ] **Step 1: Audit user-facing strings added by closure work**

Run: `rg -n 'Text\\(|Label\\(|navigationTitle\\(|ContentUnavailableView\\(' App Packages/PTFeatures | head -n 200`
Expected: all new user-facing literals that need localization are enumerated.

- [ ] **Step 2: Update localization resources for closure changes**

Implement:
- add missing strings for AI runtime, EPUB flow, migration, papers import, and share-extension surfaced text;
- keep 14-language coverage intact.

- [ ] **Step 3: Refresh tracker docs from fresh evidence**

Implement:
- mark completed phases accurately;
- distinguish “code exists”, “verified passing”, and “remaining debt”;
- remove stale statements such as Anthropic pending or tabs unmerged.

- [ ] **Step 4: Ensure TestFlight lane matches current branch reality**

Run: `bundle exec fastlane ios release_testflight version:<TARGET_VERSION>`
Expected: build and upload with a monotonic build number after env vars are present.

### Task 6: Run the final verification matrix and produce release evidence

**Files:**
- Add: `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

- [ ] **Step 1: Verify package tests**

Run: `swift test --package-path Packages/PTCore && swift test --package-path Packages/PTNetworking && swift test --package-path Packages/PTUI && swift test --package-path Packages/PTAIServices && swift test --package-path Packages/PTReader && swift test --package-path Packages/PTFeatures`
Expected: all commands exit 0.

- [ ] **Step 2: Verify app build**

Run: `xcodebuild -project PaperTokReader.xcodeproj -scheme PaperTokReader -configuration Release -destination 'generic/platform=iOS' build`
Expected: exit 0.

- [ ] **Step 3: Record verification evidence**

Implement:
- write exact commands, dates, outcomes, and unresolved caveats into `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`.

- [ ] **Step 4: Upload fresh TestFlight build**

Run: `bundle exec fastlane ios release_testflight version:<TARGET_VERSION>`
Expected: Fastlane reports successful upload and the produced build number is recorded in the verification report.

---

## Done Definition

This closure plan is complete only when all of the following are true from fresh evidence:

- `swift test` passes for all six packages.
- `xcodebuild` succeeds for the app target after the closure changes.
- AI chat can select a provider/model and stream real responses through the feature runtime.
- tool execution uses a real `ToolContext`, not default empty context or disconnected service state.
- `spawn_sub_agent` no longer returns the current placeholder queue JSON for supported runtime conditions.
- EPUB files can be imported and opened from the bookshelf.
- Papers downloads enter the bookshelf through a real import path.
- Flutter migration imports actual data and cannot silently mark success with zero imported rows unless zero rows are truly present.
- deep links, intents, and share-extension handoff affect the visible app state.
- localization and docs reflect the post-closure truth.
- a fresh TestFlight build is uploaded and documented.

# Swift-Native Dirty Delta Ledger

**Date:** 2026-04-10  
**Branch:** `swift-native`  
**Purpose:** Record the current uncommitted implementation delta by subsystem so closure work can land it intentionally instead of layering new work on top of unidentified changes.

## Snapshot

As of 2026-04-10, the worktree is still dirty and contains meaningful local implementation across product and infrastructure surfaces. These changes are not assumed to be disposable.

Primary commands used for this snapshot:

```bash
git -C /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native status -sb
git -C /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native diff --stat
```

## Buckets

### 1. Reader Product Delta

Primary files:

- `Packages/PTFeatures/Sources/PTFeatures/Reader/**`
- `Packages/PTReader/Sources/PTReader/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/**`
- `Packages/PTReader/Tests/PTReaderTests/**`

Current themes:

- EPUB annotation/editor flows
- shared reader controls model
- EPUB/PDF per-book settings work
- reader AI panel host
- image analysis / viewer / export workflow
- PDF annotation editing support
- reader session bridging and related tests

Target wave:

- Wave C

### 2. AI Runtime And Chat Delta

Primary files:

- `Packages/PTAIServices/Sources/PTAIServices/**`
- `Packages/PTAIServices/Tests/PTAIServicesTests/**`
- `Packages/PTFeatures/Sources/PTFeatures/AIChat/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/**`
- `App/Platform/AI/**`

Current themes:

- tool runtime context
- tool registry/runtime honesty
- sub-agent parameter compatibility
- shortcut AI handoff
- AI chat runtime integration

Target wave:

- Wave D

### 3. Papers And Bookshelf Delta

Primary files:

- `Packages/PTFeatures/Sources/PTFeatures/Papers/**`
- `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/**`
- `Packages/PTNetworking/Sources/PTNetworking/PaperTok/**`
- `Packages/PTNetworking/Sources/PTNetworking/HTTP/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/Papers/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/**`

Current themes:

- PaperTok detail decoding and download worker
- byte progress and import-phase reporting
- detail metadata and filter surfaces
- duplicate-safe import and EPUB extraction
- bookshelf organization, edit, and filtering flows

Target wave:

- Wave B

### 4. Platform, Share, Intents, And Migration Delta

Primary files:

- `App/Platform/DeepLink/**`
- `App/Platform/Intents/**`
- `App/Platform/Migration/**`
- `App/Platform/Share/**`
- `App/Extensions/ShareExtension/**`
- `Tests/AppTests/Platform/**`

Current themes:

- deep-link routing
- share route contract
- shared inbox processing
- migration planning and service hardening
- shortcut-intent handoff
- platform-focused app tests

Target wave:

- Wave E

### 5. Notes, Statistics, And Reading-Time Delta

Primary files:

- `Packages/PTFeatures/Sources/PTFeatures/Notes/**`
- `Packages/PTFeatures/Sources/PTFeatures/Statistics/**`
- `Packages/PTCore/Sources/PTCore/Database/ReadingTimeDAO.swift`
- `Packages/PTCore/Sources/PTCore/Database/ReadingSessionRecorder.swift`
- `Packages/PTCore/Tests/PTCoreTests/Database/ReadingTimeDAOTests.swift`
- `Packages/PTCore/Tests/PTCoreTests/Database/ReadingSessionRecorderTests.swift`
- `Packages/PTFeatures/Tests/PTFeaturesTests/Notes/**`
- `Packages/PTFeatures/Tests/PTFeaturesTests/Statistics/**`

Current themes:

- note grouping/export/productization
- statistics dashboard support
- per-book trend breakdown
- native reading-time persistence
- timezone-stable statistics behavior

Target wave:

- Wave C for reader-fed statistics integration
- Wave F for final statistics/settings closure

### 6. Project And Documentation Delta

Primary files:

- `project.yml`
- `PaperTokReader.xcodeproj/**`
- `fastlane/Fastfile`
- `docs/superpowers/plans/2026-04-06-progress-tracker.md`
- `docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`
- `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

Current themes:

- scheme/project generation
- closure truth tracking
- release automation updates

Target wave:

- Wave A for structure and truth reset
- Wave G for final release closure

## Handling Rules

- Do not discard this delta wholesale.
- Do not treat all dirty files as one change set.
- Verify and land each bucket in the wave where it belongs.
- If a local file belongs to a later wave, do not allow an earlier-wave task to overwrite it casually.

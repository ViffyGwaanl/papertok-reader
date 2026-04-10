# Swift-Native Full-Spec Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the `swift-native` branch to full spec parity against the approved Swift-native migration contract and the `main` Flutter product behavior, with native-grade delivery on iPhone, iPad, and macOS.

**Architecture:** Execute in closure waves. Use the approved 2026-04-10 full-spec closure design as the controlling contract, the 2026-04-10 gap matrix as the operating truth table, and the `main` Flutter product as the behavioral reference where the approved contract is silent or underspecified. Begin by reducing structural risk in the app shell and project topology so later waves can run safely through subagent-driven parallel execution.

**Tech Stack:** Swift 5.9+, SwiftUI, Observation, GRDB.swift, Readium 3.x, PDFKit, Vision, AppIntents, EventKit, XcodeGen, Swift Testing, XCTest, Fastlane, Flutter main-branch parity references

---

## Execution Mode

The user explicitly selected subagent-driven execution. After this master plan is saved, execute through `superpowers:subagent-driven-development`, with controlled parallel exploration and disjoint write ownership.

---

## Working Artifacts

This closure plan is anchored to:

- `docs/superpowers/specs/2026-04-10-swift-native-full-spec-closure-design.md`
- `docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md`
- `docs/superpowers/specs/2026-04-03-swift-migration-requirements.md`
- `docs/superpowers/specs/2026-04-03-swift-native-migration-design.md`
- `docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`
- `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

Wave execution should also keep these truth-bearing docs current:

- `docs/superpowers/plans/2026-04-06-progress-tracker.md`
- `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

---

## Current Branch Checkpoint

Before new implementation is layered on top, assume the following are true and plan accordingly:

- the worktree is already ahead of `origin/swift-native`;
- the worktree contains substantial uncommitted implementation across Reader, AI, Platform, Papers, Notes, and Statistics;
- those local changes are not noise and must be triaged, verified, and landed rather than discarded;
- `project.yml` currently defines only an iOS app target and iOS share extension, so native macOS delivery is not yet structurally real;
- `App/ContentView.swift` is too large to be a safe long-term edit hotspot.

---

## File Structure For Closure Work

This plan assumes the following new or stabilized artifacts will exist by the end of Wave A:

- `docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md`
- `docs/superpowers/plans/2026-04-10-swift-native-dirty-delta-ledger.md`
- `App/AppShell/`
- `App/Platform/iOS/`
- `App/Platform/macOS/`
- `App/Entitlements/macOS.entitlements`
- a standalone macOS target in `project.yml`

Later waves will primarily operate in:

- `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/**`
- `Packages/PTFeatures/Sources/PTFeatures/Papers/**`
- `Packages/PTFeatures/Sources/PTFeatures/Reader/**`
- `Packages/PTFeatures/Sources/PTFeatures/AIChat/**`
- `Packages/PTFeatures/Sources/PTFeatures/Settings/**`
- `Packages/PTAIServices/Sources/PTAIServices/**`
- `Packages/PTReader/Sources/PTReader/**`
- `App/Platform/**`
- `Tests/AppTests/**`

---

### Task 1: Establish The Closure Truth Table

**Files:**
- Create: `docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md`
- Create: `docs/superpowers/plans/2026-04-10-swift-native-dirty-delta-ledger.md`
- Modify: `docs/superpowers/plans/2026-04-06-progress-tracker.md`
- Modify: `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

- [ ] **Step 1: Snapshot the current worktree and record the dirty delta by subsystem**

Run:
```bash
git -C /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native status -sb
git -C /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native diff --stat
```

Expected:

- current dirty files are grouped into Reader, AI, Platform, Papers/Bookshelf, and Notes/Statistics buckets;
- the resulting ledger identifies which existing local deltas belong to which wave.

- [ ] **Step 2: Refine the gap matrix with `main` references and current branch status**

Update the matrix rows for FR-01 through FR-23 using:

```markdown
| FR | Scope | `main` parity reference | `swift-native` current state | Status | Target wave | Verification focus |
```

Expected:

- every FR row points to real `main` file families;
- every FR row has a truthful status and target wave;
- no closure-critical area remains "floating" outside the matrix.

- [ ] **Step 3: Update the progress tracker so the 2026-04-10 design and matrix become the active truth**

Add a short section like:

```markdown
## 2026-04-10 closure reset

- Active contract: `docs/superpowers/specs/2026-04-10-swift-native-full-spec-closure-design.md`
- Active matrix: `docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md`
- Execution mode: subagent-driven full-spec closure against `main` + approved spec
```

Expected:

- older phase framing is clearly subordinated to the new closure design and matrix;
- no doc ambiguity remains about what the controller should follow.

- [ ] **Step 4: Commit the truth-table docs before structural code work**

Run:
```bash
git -C /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native add \
  docs/superpowers/plans/2026-04-10-swift-native-gap-matrix.md \
  docs/superpowers/plans/2026-04-10-swift-native-dirty-delta-ledger.md \
  docs/superpowers/plans/2026-04-06-progress-tracker.md \
  docs/superpowers/plans/2026-04-07-swift-native-verification-report.md
git -C /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native commit -m "docs: establish full-spec closure truth table"
```

Expected:

- docs truth becomes checkpointed before code restructuring starts.

---

### Task 2: Introduce A Standalone macOS Target

**Files:**
- Modify: `project.yml`
- Modify: `PaperTokReader.xcodeproj/project.pbxproj` (generated)
- Create: `App/Entitlements/macOS.entitlements`
- Create: `App/Platform/macOS/MacRootScene.swift`
- Modify: `App/PaperTokReaderApp.swift`
- Test: `Tests/AppTests/Platform/` (macOS-friendly app-shell tests as needed)

- [ ] **Step 1: Add a macOS target to `project.yml`**

Add a new target following this shape:

```yaml
  PaperTokReader-macOS:
    type: application
    platform: macOS
    sources:
      - path: App
        type: group
        excludes:
          - Extensions/ShareExtension/**
          - Platform/iOS/**
    resources:
      - path: App/Resources/Localizable.xcstrings
    dependencies:
      - package: PTFeatures
      - sdk: EventKit.framework
      - sdk: AppIntents.framework
    settings:
      base:
        INFOPLIST_FILE: App/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: ai.papertok.paperreader.mac
        PRODUCT_NAME: "PaperTok Reader"
        CODE_SIGN_ENTITLEMENTS: App/Entitlements/macOS.entitlements
```

Expected:

- the project definition exposes a true macOS app target instead of only iOS compatibility-on-Mac.

- [ ] **Step 2: Add a macOS entitlements file**

Create `App/Entitlements/macOS.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.ai.papertok.paperreader</string>
  </array>
</dict>
</plist>
```

Expected:

- macOS has a dedicated entitlements surface that can be evolved intentionally.

- [ ] **Step 3: Create a macOS root scene wrapper**

Create `App/Platform/macOS/MacRootScene.swift`:

```swift
import SwiftUI

struct MacRootScene: Scene {
    let rootView: MainTabView

    var body: some Scene {
        WindowGroup {
            rootView
        }
        .commands {
            MacMenuCommands()
        }
    }
}
```

Expected:

- macOS scene composition is no longer implicit inside the iOS-first app entry point.

- [ ] **Step 4: Regenerate and verify the project topology**

Run:
```bash
cd /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native
xcodegen generate
xcodebuild -list -project PaperTokReader.xcodeproj
```

Expected:

- a macOS target and at least one macOS buildable scheme appear in the generated project inventory.

- [ ] **Step 5: Build the macOS target**

Run:
```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PaperTokReader-macOS \
  -destination 'platform=macOS' \
  build
```

Expected:

- the standalone macOS app target builds, or remaining blockers are isolated and documented for immediate fixing.

---

### Task 3: Split The App Shell Into Parallel-Safe Boundaries

**Files:**
- Create: `App/AppShell/AppEnvironment.swift`
- Create: `App/AppShell/RootScene.swift`
- Create: `App/AppShell/RootNavigationCoordinator.swift`
- Modify: `App/PaperTokReaderApp.swift`
- Modify: `App/ContentView.swift`
- Test: `Tests/AppTests/Platform/AppAIToolContextFactoryTests.swift`

- [ ] **Step 1: Extract root environment assembly**

Create `App/AppShell/AppEnvironment.swift`:

```swift
import Foundation
import PTCore
import PTFeatures
import PTAIServices

struct AppEnvironment {
    let database: AppDatabase
    let toolContextFactory: AppAIToolContextFactory
}
```

Expected:

- root dependency construction is represented explicitly and can be reused by iOS and macOS scenes.

- [ ] **Step 2: Move root scene composition out of `PaperTokReaderApp.swift`**

Create `App/AppShell/RootScene.swift`:

```swift
import SwiftUI

struct RootScene: View {
    let environment: AppEnvironment

    var body: some View {
        MainTabView(
            database: environment.database,
            toolContextFactory: environment.toolContextFactory
        )
    }
}
```

Expected:

- the app entry point becomes a thin shell instead of the long-term host for cross-feature logic.

- [ ] **Step 3: Trim `ContentView.swift` by moving root-only responsibilities out**

Move app-shell-only logic behind a coordinator boundary:

```swift
@Observable
final class RootNavigationCoordinator {
    var selectedTab: AppTab = .papers
}
```

Expected:

- `ContentView.swift` stops being the default landing zone for every root concern;
- later feature work can target smaller hosts instead of a monolith.

- [ ] **Step 4: Rebuild and run current app/platform smoke tests**

Run:
```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PaperTokReaderAppTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:PaperTokReaderTests/AppAIToolContextFactoryTests \
  -only-testing:PaperTokReaderTests/DeepLinkRouterTests \
  test
```

Expected:

- root app-shell extractions preserve current platform behavior.

---

### Task 4: Triage And Land The Existing Dirty Delta In Verified Slices

**Files:**
- Modify: wave-owned source and test files already dirty in the worktree
- Modify: `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`

- [ ] **Step 1: Group the dirty delta into reviewable slices**

Use these buckets:

- Reader + reader tests
- AI runtime + AI chat tests
- Papers/Bookshelf + import tests
- Platform/share/migration + app tests
- Notes/Statistics + supporting core tests

Expected:

- no future wave starts by layering new work on top of unidentified local deltas.

- [ ] **Step 2: Verify and land each slice with focused commands before new feature expansion**

Run the slice-specific commands already proven useful, such as:

```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTCore --filter 'ReadingTimeDAOTests|ReadingSessionRecorderTests'
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices --filter 'ToolRegistryTests|ToolRuntimeContextTests'
```

Expected:

- current local improvements stop living as untrusted background state and become deliberate wave inputs.

---

### Task 5: Finish Wave B — Navigation, Bookshelf, Papers, And Directory Scanning

**Files:**
- Modify: `App/ContentView.swift` or extracted host replacements
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Bookshelf/**`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Papers/**`
- Modify: `App/Platform/Share/**`
- Create/Modify: directory-scanning persistence and monitoring files in `PTCore`/`PTFeatures`
- Test: `Packages/PTFeatures/Tests/PTFeaturesTests/Papers/**`
- Test: `Packages/PTFeatures/Tests/PTFeaturesTests/Bookshelf/**`
- Test: `Tests/AppTests/Platform/SharedInbox*`

- [ ] **Step 1: Close navigation parity across iPhone, iPad, and macOS**
- [ ] **Step 2: Close Bookshelf sort/filter/tag/group/custom-order/drag-drop/AI-organize parity**
- [ ] **Step 3: Close Papers feed/detail/download/import parity against `main` and the approved contract**
- [ ] **Step 4: Implement directory scanning with security-scoped bookmarks, rescan, monitoring, and recovery**
- [ ] **Step 5: Re-run targeted Papers/Bookshelf/app import regressions**

Run:
```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PTFeaturesPackageTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:PTFeaturesTests/PapersViewModelTests \
  -only-testing:PTFeaturesTests/PaperDetailDataLoaderTests \
  -only-testing:PTFeaturesTests/PaperDownloadPlanTests \
  -only-testing:PTFeaturesTests/PaperDownloadWorkerTests \
  -only-testing:PTFeaturesTests/BookImportServiceEPUBTests \
  -only-testing:PTFeaturesTests/BookshelfViewModelTests \
  test
```

Expected:

- Wave B closes FR-01 through FR-03 parity-critical gaps, including directory scanning.

---

### Task 6: Finish Wave C — Reader Full Parity

**Files:**
- Modify: `Packages/PTReader/Sources/PTReader/**`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Reader/**`
- Modify: reader hosting surfaces in `App/**`
- Test: `Packages/PTReader/Tests/PTReaderTests/**`
- Test: `Packages/PTFeatures/Tests/PTFeaturesTests/Reader/**`

- [ ] **Step 1: Close EPUB parity gaps in settings, annotations, and platform behavior**
- [ ] **Step 2: Close PDF parity gaps in settings, annotations, and platform behavior**
- [ ] **Step 3: Close reader AI panel parity across all three platforms**
- [ ] **Step 4: Close TTS product parity including controls and background behavior**
- [ ] **Step 5: Re-run reader regression suites and three-platform walkthroughs**

Run:
```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PTReaderPackageTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test

xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PTFeaturesPackageTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:PTFeaturesTests/ReaderViewModelTests \
  -only-testing:PTFeaturesTests/EPUBReaderAnnotationsViewModelTests \
  -only-testing:PTFeaturesTests/PDFReaderAnnotationsViewModelTests \
  -only-testing:PTFeaturesTests/ReaderAIPanelPreferencesStoreTests \
  test
```

Expected:

- EPUB, PDF, reader AI, annotations, settings, and TTS all reach closure-grade parity.

---

### Task 7: Finish Wave D — AI Product System

**Files:**
- Modify: `Packages/PTAIServices/Sources/PTAIServices/**`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/**`
- Modify: `App/Platform/AI/**`
- Test: `Packages/PTAIServices/Tests/PTAIServicesTests/**`
- Test: `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/**`

- [ ] **Step 1: Close provider center, attachments, history, branching, thinking, and usage parity**
- [ ] **Step 2: Close end-user tool parity, including MCP, sub-agent, and skills surfaces**
- [ ] **Step 3: Close translation, RAG, and memory product parity**
- [ ] **Step 4: Re-run PTAIServices and AIChat regressions**

Run:
```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices

xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PTFeaturesPackageTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:PTFeaturesTests/AIChatViewModelExtTests \
  test
```

Expected:

- AI becomes product-complete, not only runtime-capable.

---

### Task 8: Finish Wave E — Platform Integration, Migration, And Localization

**Files:**
- Modify: `App/Platform/DeepLink/**`
- Modify: `App/Platform/Intents/**`
- Modify: `App/Platform/Migration/**`
- Modify: `App/Platform/Share/**`
- Modify: `App/Resources/Localizable.xcstrings`
- Modify: `Tests/AppTests/Platform/**`

- [ ] **Step 1: Close share, deep-link, and App Intents end-to-end parity**
- [ ] **Step 2: Close Flutter migration completeness for DB, files, and settings**
- [ ] **Step 3: Verify localization on all touched user paths**
- [ ] **Step 4: Re-run app-platform regression suites on iOS and macOS where applicable**

Run:
```bash
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PaperTokReaderAppTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  test
```

Expected:

- system integration behavior is defensible and migration is closure-grade.

---

### Task 9: Finish Wave F — Settings, Sync/Backup, TTS Deep Settings, And KAIROS

**Files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Settings/**`
- Modify: sync-related core/networking files
- Modify: reader TTS settings surfaces
- Modify/Create: proactive or KAIROS product surfaces and tests

- [ ] **Step 1: Close settings depth parity**
- [ ] **Step 2: Close sync/backup configuration, execution, and restore parity**
- [ ] **Step 3: Close KAIROS/proactive assistant parity**
- [ ] **Step 4: Re-run settings/sync/TTS/proactive verification passes**

Expected:

- the remaining deep configuration and proactive-system gaps are gone.

---

### Task 10: Finish Wave G — Full Verification And Release Closure

**Files:**
- Modify: `docs/superpowers/plans/2026-04-06-progress-tracker.md`
- Modify: `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`
- Modify: `fastlane/Fastfile`
- Modify: `project.yml`
- Modify: platform signing/entitlement surfaces as needed

- [ ] **Step 1: Run the full three-platform verification matrix**
- [ ] **Step 2: Run closure-grade walkthroughs against the gap matrix**
- [ ] **Step 3: Update truth-bearing docs with final evidence**
- [ ] **Step 4: Archive and run TestFlight/release workflows only after feature closure is honest**

Run:
```bash
xcodegen generate
xcodebuild -list -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PaperTokReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  build
xcodebuild -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj \
  -scheme PaperTokReader-macOS \
  -destination 'platform=macOS' \
  build
```

Expected:

- release readiness is the final confirmation, not a proxy for unfinished product work.

---

## Controller Rules During Execution

- Do not discard the existing dirty delta; triage and land it intentionally.
- Do not run large parallel implementation tasks against the same hotspot file.
- Do not claim closure for a row in the gap matrix without fresh evidence.
- Do not let release/TestFlight work begin before Waves A-F are honestly closed.
- Update the progress tracker and verification report after each wave.

---

## Immediate Next Action

Begin with Tasks 1 through 3 as Wave A. Once Wave A is merged into the branch as verified slices, proceed with Wave B using subagent-driven development and disjoint write ownership.
